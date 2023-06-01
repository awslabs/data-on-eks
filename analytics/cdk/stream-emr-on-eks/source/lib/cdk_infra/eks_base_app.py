######################################################################################################################
# Copyright 2020-2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.                                      #
#                                                                                                                   #
# Licensed under the Apache License, Version 2.0 (the "License"). You may not use this file except in compliance    #
# with the License. A copy of the License is located at                                                             #
#                                                                                                                   #
#     http://www.apache.org/licenses/LICENSE-2.0                                                                    #
#                                                                                                                   #
# or in the 'license' file accompanying this file. This file is distributed on an 'AS IS' BASIS, WITHOUT WARRANTIES #
# OR CONDITIONS OF ANY KIND, express o#implied. See the License for the specific language governing permissions     #
# and limitations under the License.  																				#                                                                              #
######################################################################################################################
from constructs import Construct
from aws_cdk import Aws
from aws_cdk.aws_eks import ICluster, KubernetesManifest
from lib.util.manifest_reader import *
import os

class EksBaseAppConst(Construct):
    def __init__(self,scope: Construct,id: str,eks_cluster: ICluster, **kwargs,) -> None:
        super().__init__(scope, id, **kwargs)

        source_dir=os.path.split(os.environ['VIRTUAL_ENV'])[0]+'/source'
        
        # Add ALB ingress controller to EKS
        self._alb = eks_cluster.add_helm_chart('ALBChart',
            chart='aws-load-balancer-controller',
            repository='https://aws.github.io/eks-charts',
            release='alb',
            version='1.4.8',
            create_namespace=False,
            namespace='kube-system',
            values=load_yaml_replace_var_local(source_dir+'/app_resources/alb-values.yaml',
                fields={
                    "{{region_name}}": Aws.REGION, 
                    "{{cluster_name}}": eks_cluster.cluster_name, 
                    "{{vpc_id}}": eks_cluster.vpc.vpc_id
                }
            )
        )
        
        # Add Cluster Autoscaler to EKS
        _var_mapping = {
            "{{region_name}}": Aws.REGION, 
            "{{cluster_name}}": eks_cluster.cluster_name, 
        }
        eks_cluster.add_helm_chart('ClusterAutoScaler',
            chart='cluster-autoscaler',
            repository='https://kubernetes.github.io/autoscaler',
            release='nodescaler',
            create_namespace=False,
            namespace='kube-system',
            values=load_yaml_replace_var_local(source_dir+'/app_resources/autoscaler-values.yaml',_var_mapping)
        )
        # Add container insight (CloudWatch Log) to EKS
        KubernetesManifest(self,'ContainerInsight',
            cluster=eks_cluster, 
            manifest=load_yaml_replace_var_remotely('https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluentd-quickstart.yaml', 
                    fields=_var_mapping,
                    multi_resource=True
            )
        )
        # # Add Spark Operator to EKS
        # eks_cluster.add_helm_chart('SparkOperatorChart',
        #     chart='spark-operator',
        #     repository='https://googlecloudplatform.github.io/spark-on-k8s-operator',
        #     release='spark-operator',
        #     version='1.1.27',
        #     create_namespace=True,
        #     values=load_yaml_replace_var_local(source_dir+'/app_resources/spark-operator-values.yaml',fields={'':''})
        # )