import { Construct } from 'constructs';
import * as blueprints from '@aws-quickstart/eks-blueprints'
import { GenericClusterProvider, PlatformTeam, VpcProvider } from '@aws-quickstart/eks-blueprints';
import { CapacityType, Cluster, ClusterLoggingTypes, KubernetesVersion, NodegroupAmiType } from 'aws-cdk-lib/aws-eks';
import { InstanceType, Vpc } from 'aws-cdk-lib/aws-ec2';
import { ManagedPolicy, PolicyStatement } from 'aws-cdk-lib/aws-iam';
import { EmrEksTeam, EmrEksTeamProps } from './teams/emrEksTeam';
import { ArnFormat, Aws, Stack } from 'aws-cdk-lib';
import { EmrEksAddOn } from './AddOns/emrEksAddOn';

/** 
 * show karpenter, CA
 * Add fargate
*/

export interface EmrEksBlueprintProps {
  eksCluster?: Cluster,
  clusterVpc?: Vpc
}


export default class EmrEksStack {

    build (scope: Construct, id: string) {

        const eksClusterLogging: ClusterLoggingTypes [] = [
            ClusterLoggingTypes.API,
            ClusterLoggingTypes.AUTHENTICATOR,
            ClusterLoggingTypes.SCHEDULER,
            ClusterLoggingTypes.CONTROLLER_MANAGER,
            ClusterLoggingTypes.AUDIT,
          ];
        
        const emrCluster: GenericClusterProvider = new blueprints.GenericClusterProvider ({
            clusterName: 'eksblue', 
            version: KubernetesVersion.of('1.21'),
            managedNodeGroups: [
                {
                    id: "core-ng",
                    amiType: NodegroupAmiType.AL2_X86_64,
                    instanceTypes: [new InstanceType('t3.large')],
                    diskSize: 50
                },
                {
                    id: "spark",
                    instanceTypes: [new InstanceType('r5d.xlarge')],
                    nodeGroupCapacityType: CapacityType.ON_DEMAND,
                    diskSize: 50,
                    labels: {
                      app: 'spark'
                    }
                    
                }
            ],
            clusterLogging: eksClusterLogging
        });

        const clusterAdminTeam = new PlatformTeam( {
            name: "adminteam",
            userRoleArn: "arn:aws:iam::372775283473:role/FULL"
        })
        
        const stack = Stack.of(scope);
        
        const policy1 = new ManagedPolicy(scope, 'MyPolicy1', {
            managedPolicyName: 'policyAddOn',
            statements: [
              new PolicyStatement({
                resources: ['*'],
                actions: ['s3:*'],
              }),
              new PolicyStatement({
                resources: ['*'],
                actions: ['glue:*'],
              }),
              new PolicyStatement({
                resources: [
                  stack.formatArn({
                    account: Aws.ACCOUNT_ID,
                    region: Aws.REGION,
                    service: 'logs',
                    resource: '*',
                    arnFormat: ArnFormat.NO_RESOURCE_NAME,
                  }),
                ],
                actions: [
                  'logs:*',
                ],
              }),
            ],
          });

        const dataTeam: EmrEksTeamProps = {
                name:'dataTeam',
                virtualClusterName: 'batchJob',
                virtualClusterNamespace: 'batchjob',
                createNamespace: true,
                excutionRoles: [
                    {
                        excutionRoleIamPolicy: policy1,
                        excutionRoleName: 'myBlueprintExecRole'
                    }
                ]
            };

        blueprints.EksBlueprint.builder()
                .clusterProvider(emrCluster)
                .addOns(
                    new blueprints.VpcCniAddOn(),
                    new blueprints.CoreDnsAddOn(),
                    new blueprints.MetricsServerAddOn,
                    new blueprints.ClusterAutoScalerAddOn,
                    new blueprints.CertManagerAddOn,
                    new blueprints.AwsLoadBalancerControllerAddOn,
                    new blueprints.EbsCsiDriverAddOn,
                    new blueprints.KubeProxyAddOn,
                    new EmrEksAddOn)
                .teams(
                  clusterAdminTeam, 
                  new EmrEksTeam(dataTeam))
                .build(scope, `${id}-emr-eks-blueprint`);      
    }
}

