# // Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# // SPDX-License-Identifier: License :: OSI Approved :: MIT No Attribution License (MIT-0)
#
from constructs import Construct
from aws_cdk import (Aws,NestedStack,RemovalPolicy,Tags,CfnTag,aws_iam as iam,aws_ec2 as ec2,aws_efs as efs)
from aws_cdk.aws_emr import CfnCluster
from lib.util.manifest_reader import load_yaml_replace_var_local
import os

class EMREC2Stack(NestedStack):

    def __init__(self, scope: Construct, id: str, emr_version: str, cluster_name:str, eksvpc: ec2.IVpc, code_bucket:str, **kwargs) -> None:
        super().__init__(scope, id, **kwargs)

        source_dir=os.path.split(os.environ['VIRTUAL_ENV'])[0]+'/source'
        # The VPC requires a Tag to allow EMR to create the relevant security groups
        Tags.of(eksvpc).add("for-use-with-amazon-emr-managed-policies", "true")

        #######################################
        #######                         #######
        #######  EFS for checkpointing  #######
        #######                         #######
        #######################################
        _efs_sg = ec2.SecurityGroup(self,'EFSSg',
            security_group_name=cluster_name + '-EFS-sg',
            vpc=eksvpc,
            description='NFS access to EFS from EMR on EC2 cluster',
        )
        _efs_sg.add_ingress_rule(ec2.Peer.ipv4(eksvpc.vpc_cidr_block),ec2.Port.tcp(port=2049))
        Tags.of(_efs_sg).add('Name', cluster_name+'-EFS-sg')

        _efs=efs.FileSystem(self,'EFSCheckpoint',
            vpc=eksvpc,
            security_group=_efs_sg,
            encrypted=True,
            lifecycle_policy=efs.LifecyclePolicy.AFTER_60_DAYS,
            performance_mode=efs.PerformanceMode.MAX_IO,
            removal_policy=RemovalPolicy.DESTROY,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS, one_per_az=True)
        )

        ###########################
        #######             #######
        #######  EMR Roles  #######
        #######             #######
        ###########################
        # emr job flow role
        emr_job_role = iam.Role(self,"EMRJobRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AmazonElasticMapReduceforEC2Role"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonMSKFullAccess"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonElasticFileSystemReadOnlyAccess"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore")
            ]
        )
        _iam = load_yaml_replace_var_local(source_dir+'/app_resources/emr-iam-role.yaml',
            fields= {
                "{{codeBucket}}": code_bucket
            })
        for statmnt in _iam:
            emr_job_role.add_to_policy(iam.PolicyStatement.from_json(statmnt)
        )

        # emr service role
        svc_role = iam.Role(self,"EMRSVCRole",
            assumed_by=iam.ServicePrincipal("elasticmapreduce.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AmazonEMRServicePolicy_v2")
            ]
        )
        svc_role.add_to_policy(
            iam.PolicyStatement(
                actions=["iam:PassRole"],
                resources=[emr_job_role.role_arn],
                conditions={"StringEquals": {"iam:PassedToService": "ec2.amazonaws.com"}},
            )
        )

        # emr job flow profile
        emr_job_flow_profile = iam.CfnInstanceProfile(self,"EMRJobflowProfile",
            roles=[emr_job_role.role_name],
            instance_profile_name=emr_job_role.role_name
        )

        ####################################
        #######                      #######
        #######  Create EMR Cluster  #######
        #######                      #######
        ####################################
        emr_c = CfnCluster(self,"emr_ec2_cluster",
            name=cluster_name,
            applications=[CfnCluster.ApplicationProperty(name="Spark")],
            log_uri=f"s3://{code_bucket}/elasticmapreduce/",
            release_label=emr_version,
            visible_to_all_users=True,
            service_role=svc_role.role_name,
            job_flow_role=emr_job_role.role_name,
            tags=[CfnTag(key="project", value=cluster_name)],
            instances=CfnCluster.JobFlowInstancesConfigProperty(
                termination_protected=False,
                master_instance_group=CfnCluster.InstanceGroupConfigProperty(
                    instance_count=1,
                    instance_type="r5.xlarge",
                    market="ON_DEMAND"
                ),
                core_instance_group=CfnCluster.InstanceGroupConfigProperty(
                    instance_count=1,
                    instance_type="r5.xlarge",
                    market="ON_DEMAND",
                    ebs_configuration=CfnCluster.EbsConfigurationProperty(
                        ebs_block_device_configs=[CfnCluster.EbsBlockDeviceConfigProperty(
                        volume_specification=CfnCluster.VolumeSpecificationProperty(
                            size_in_gb=100,
                            volume_type='gp2'))
                    ])
                ),
                ec2_subnet_id=eksvpc.public_subnets[0].subnet_id
            ),
            configurations=[
                # use python3 for pyspark
                CfnCluster.ConfigurationProperty(
                    classification="spark-env",
                    configurations=[
                        CfnCluster.ConfigurationProperty(
                            classification="export",
                            configuration_properties={
                                "PYSPARK_PYTHON": "/usr/bin/python3",
                                "PYSPARK_DRIVER_PYTHON": "/usr/bin/python3",
                            },
                        )
                    ],
                ),
                # dedicate cluster to single jobs
                CfnCluster.ConfigurationProperty(
                    classification="spark",
                    configuration_properties={"maximizeResourceAllocation": "true"},
                ),
            ],
            managed_scaling_policy=CfnCluster.ManagedScalingPolicyProperty(
                compute_limits=CfnCluster.ComputeLimitsProperty(
                    unit_type="Instances",
                    maximum_capacity_units=10,
                    minimum_capacity_units=1,
                    maximum_core_capacity_units=1,
                    maximum_on_demand_capacity_units=1
                )
            ),
            bootstrap_actions=[CfnCluster.BootstrapActionConfigProperty(
                name="mountEFS",
                script_bootstrap_action=CfnCluster.ScriptBootstrapActionConfigProperty(
                    path=f"s3://{code_bucket}/app_code/job/emr-mount-efs.sh",
                    args=[_efs.file_system_id, Aws.REGION]
                )
            )]
        )
        emr_c.add_dependency(emr_job_flow_profile)
