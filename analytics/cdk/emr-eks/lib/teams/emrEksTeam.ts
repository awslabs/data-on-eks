import { Cluster, KubernetesManifest } from "aws-cdk-lib/aws-eks";
import { ApplicationTeam, ClusterAddOn, ClusterInfo, Team, TeamProps } from "@aws-quickstart/eks-blueprints";
import { readYamlDocument, loadYaml, dependable } from "@aws-quickstart/eks-blueprints/dist/utils"
import { CfnServiceLinkedRole, FederatedPrincipal, IManagedPolicy, IRole, Role } from "aws-cdk-lib/aws-iam";
import { Aws, CfnJson, CfnOutput, Stack } from "aws-cdk-lib";
import * as blueprints from '@aws-quickstart/eks-blueprints';
import * as SimpleBase from 'simple-base';
import { CfnVirtualCluster } from "aws-cdk-lib/aws-emrcontainers";
import { EmrEksAddOn } from "../AddOns/emrEksAddOn";
import { create } from "domain";


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
        
        const emrVcPrerequisit = this.setEmrContainersForNamespace (cluster, this.emrTeam.virtualClusterNamespace, this.emrTeam.createNamespace);

        this.emrTeam.excutionRoles.forEach(excutionRole => {
          this.createExecutionRole(
            cluster, 
            excutionRole.excutionRoleIamPolicy, 
            this.emrTeam.virtualClusterNamespace, 
            excutionRole.excutionRoleName);
        });

        const teamVC = new CfnVirtualCluster(cluster.stack, `${this.emrTeam.virtualClusterName}-VirtualCluster`, {
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

        teamVC.node.addDependency(emrVcPrerequisit)

        new CfnOutput (cluster.stack, `${this.emrTeam.virtualClusterName}-id`, {
          value: teamVC.attrId
        })
        
    }

    private setEmrContainersForNamespace(cluster: Cluster, namespace: string, createNamespace: boolean): KubernetesManifest {

      let emrContainersK8sRole = readYamlDocument(`${__dirname}/emrContainersRole.yaml`);
      emrContainersK8sRole =  emrContainersK8sRole.replace('<REPLACE-NAMESPACE>', namespace);
      const emrContainersK8sRoleManifest = loadYaml(emrContainersK8sRole);

      const emrContainersK8sRoleResource = cluster.addManifest('emrContainersK8sRoleManifest', 
        emrContainersK8sRoleManifest
      );
      
      let emrContainersK8sRoleBinding = readYamlDocument(`${__dirname}/emrContainersRoleBinding.yaml`);
      emrContainersK8sRoleBinding =  emrContainersK8sRoleBinding.replace('<REPLACE-NAMESPACE>', namespace);      
      const emrContainersK8sRoleBindingManifest = loadYaml(emrContainersK8sRoleBinding);

      const emrContainersK8sRoleBindingResource = cluster.addManifest('emrContainersK8sRoleBindingManifest', 
        emrContainersK8sRoleBindingManifest
      );

      emrContainersK8sRoleBindingResource.node.addDependency(emrContainersK8sRoleResource);

      if(createNamespace) {
        const namespaceManifest = blueprints.utils.createNamespace(namespace, cluster, true);
        emrContainersK8sRoleResource.node.addDependency(namespaceManifest);
      }

      return emrContainersK8sRoleBindingResource;
    }


    private createExecutionRole(cluster: Cluster, policy: IManagedPolicy, namespace: string, name: string): Role {

      const stack = cluster.stack;
  
      let irsaConditionkey: CfnJson = new CfnJson(stack, `${name}roleIrsaConditionkey'`, {
        value: {
          [`${cluster.openIdConnectProvider.openIdConnectProviderIssuer}:sub`]: 'system:serviceaccount:' + namespace + ':emr-containers-sa-*-*-' + Aws.ACCOUNT_ID.toString() +'-'+ SimpleBase.base36.encode(name),
        },
      });
  
      // Create an execution role assumable by EKS OIDC provider and scoped to the service account of the virtual cluster
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


