import { Cluster } from "aws-cdk-lib/aws-eks";
import { ApplicationTeam, ClusterAddOn, ClusterInfo, Team, TeamProps } from "@aws-quickstart/eks-blueprints";
import { readYamlDocument, loadYaml } from "@aws-quickstart/eks-blueprints/dist/utils"
import { CfnServiceLinkedRole, FederatedPrincipal, IManagedPolicy, IRole, Role } from "aws-cdk-lib/aws-iam";
import { Aws, CfnJson, Stack } from "aws-cdk-lib";
import * as blueprints from '@aws-quickstart/eks-blueprints';
import * as SimpleBase from 'simple-base';
import { CfnVirtualCluster } from "aws-cdk-lib/aws-emrcontainers";

export interface excutionRoleDefinition {
  excutionRoleName: string,
  excutionRoleIamPolicy: IManagedPolicy,
}

export interface EmrEksTeamProps extends TeamProps {
  virtualClusterNamespace: string,
  createNamespace: boolean,
  virtualClusterName: string,
  excutionRoles: excutionRoleDefinition []
}


export class EmrEksTeam extends ApplicationTeam {

    private emrTeam: EmrEksTeamProps;

    constructor (props: EmrEksTeamProps) {
      super(props);
      this.emrTeam = props;
    }

    setup(clusterInfo: ClusterInfo): void {
        const cluster = clusterInfo.cluster;

        new CfnServiceLinkedRole(cluster.stack, 'EmrServiceRole', {
            awsServiceName: 'emr-containers.amazonaws.com',
          });

        const emrEksServiceRole: IRole = Role.fromRoleArn(
                cluster.stack,
                'ServiceRoleForAmazonEMRContainers',
                `arn:aws:iam::${
                  Stack.of(cluster.stack).account
                }:role/AWSServiceRoleForAmazonEMRContainers`,
              );

        cluster.awsAuth.addRoleMapping(
          emrEksServiceRole,
          {
            username: 'emr-containers',
            groups : ['']
          }
        );
        
        
        this.setEmrContainersForNamespace (cluster, this.emrTeam.virtualClusterNamespace, this.emrTeam.createNamespace);

        this.emrTeam.excutionRoles.forEach(excutionRole => {
          this.createExecutionRole(
            cluster, 
            excutionRole.excutionRoleIamPolicy, 
            this.emrTeam.virtualClusterNamespace, 
            excutionRole.excutionRoleName);
        });

        new CfnVirtualCluster(cluster.stack, `${this.emrTeam.virtualClusterName}-VirtualCluster`, {
          name: this.emrTeam.virtualClusterName,
          containerProvider: {
            id: cluster.clusterName,
            type: 'EKS',
            info: { eksInfo: { namespace: this.emrTeam.virtualClusterNamespace } },
          },
          tags: [{
            key: 'created-with',
            value: 'cdk-blueprint',
          }],
        });

        
    }

    private setEmrContainersForNamespace(cluster: Cluster, namespace: string, createNamespace: boolean) {

      if(createNamespace) {
        blueprints.utils.createNamespace(namespace, cluster, true);
      }

      let emrContainersK8sRole = readYamlDocument(`${__dirname}/emrContainersRole.yaml`);
      emrContainersK8sRole =  emrContainersK8sRole.replace('<REPLACE-NAMESPACE>', namespace);
      const emrContainersK8sRoleManifest = loadYaml(emrContainersK8sRole);

      cluster.addManifest('emrContainersK8sRoleManifest', 
        emrContainersK8sRoleManifest
      );

      let emrContainersK8sRoleBinding = readYamlDocument(`${__dirname}/emrContainersRoleBinding.yaml`);
      emrContainersK8sRoleBinding =  emrContainersK8sRoleBinding.replace('<REPLACE-NAMESPACE>', namespace);      
      const emrContainersK8sRoleBindingManifest = loadYaml(emrContainersK8sRoleBinding);

      cluster.addManifest('emrContainersK8sRoleBindingManifest', 
        emrContainersK8sRoleBindingManifest
      );
    }


    private createExecutionRole(cluster: Cluster, policy: IManagedPolicy, namespace: string, name: string): Role {

      const stack = cluster.stack;
  
      let irsaConditionkey: CfnJson = new CfnJson(stack, `${name}roleIrsaConditionkey'`, {
        value: {
          [`${cluster.openIdConnectProvider.openIdConnectProviderIssuer}:sub`]: 'system:serviceaccount:' + namespace + ':emr-containers-sa-*-*-' + Aws.ACCOUNT_ID.toString() +'-'+ SimpleBase.base36.encode(name),
        },
      });
  
      // Create an execution role assumable by EKS OIDC provider
      return new Role(stack, `${name}ExecutionRole`, {
        assumedBy: new FederatedPrincipal(
          cluster.openIdConnectProvider.openIdConnectProviderArn,
          {
            StringLike: irsaConditionkey,
          },
          'sts:AssumeRoleWithWebIdentity'),
        roleName: name,
        managedPolicies: [policy],
      });
    }


}


