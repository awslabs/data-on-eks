import { Cluster } from "aws-cdk-lib/aws-eks";
import { ApplicationTeam, ClusterInfo, TeamProps, Values } from "@aws-quickstart/eks-blueprints";
import { readYamlDocument, loadYaml } from "@aws-quickstart/eks-blueprints/dist/utils"
import { FederatedPrincipal, IManagedPolicy, ManagedPolicy, PolicyStatement, Role } from "aws-cdk-lib/aws-iam";
import { Aws, CfnJson, CfnOutput, CfnTag } from "aws-cdk-lib";
import * as blueprints from '@aws-quickstart/eks-blueprints';
import * as simplebase from 'simple-base';
import { CfnVirtualCluster } from "aws-cdk-lib/aws-emrcontainers";
import { KubectlProvider, ManifestDeployment } from "@aws-quickstart/eks-blueprints/dist/addons/helm-addon/kubectl-provider";
import { Construct } from "constructs";


/**
 * Interface define the object to create an execution role
 */
 export interface ExecutionRoleDefinition {
  /**
   * The name of the IAM role to create
   */
  executionRoleName: string,
  /**
    * The IAM policy to use with IAM role if it already exists
    * Can be initialized for example by `fromPolicyName` in Policy class
    */
  excutionRoleIamPolicy?: IManagedPolicy,
  /**
    * Takes an array of IAM Policy Statement, you should pass this 
    * if you want the Team to create the policy along the IAM role 
    */
  executionRoleIamPolicyStatement?: PolicyStatement[],
}

/**
 * Interface to define a EMR on EKS team
 */
export interface EmrEksTeamProps extends TeamProps {
  /*
  * The namespace of where the virtual cluster will be created
  */
  virtualClusterNamespace: string,
  /**
   * To define if the namespace that team will use need to be created
   */
  createNamespace: boolean,
  /*
  * The name of the virtual cluster the team will use
  */
  virtualClusterName: string,
  /**
   * List of execution role to associated with the VC namespace {@link ExecutionRoleDefinition}
   */
  executionRoles: ExecutionRoleDefinition[]
  /**
   * Tags to apply to EMR on EKS Virtual Cluster
   */
   virtualClusterTags?: CfnTag[]
}

/*
 *This class define the Team that can be used with EMR on EKS
 *The class will create an EMR on EKS Virtual Cluster to use by the team
 *It can either create a namespace or use an existing one
 *The class will set the necessary k8s RBAC needed by EMR on EKS as defined in the AWS documentation 
 * https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/setting-up-cluster-access.html
 * The class constructor take an EMR on EKS Team definition and need the EMR on EKS AddOn added
 * The EmrEksTeam will `throw` an error if the EMR on EKS AddOn is not added
 */


export class EmrEksTeam extends ApplicationTeam {

  private emrTeam: EmrEksTeamProps;
  /**
   * @public
   * @param {EmrEksTeamProps} props the EMR on EKS team definition {@link EmrEksTeamProps}
   */
  constructor(props: EmrEksTeamProps) {
    super(props);
    this.emrTeam = props;
  }

  setup(clusterInfo: ClusterInfo): void {
    const cluster = clusterInfo.cluster;

    const emrOnEksAddOn = clusterInfo.getProvisionedAddOn('EmrEksAddOn');

    if (emrOnEksAddOn === undefined) {
      throw new Error("EmrEksAddOn must be deployed before creating EMR on EKS team");
    }

    const emrVcPrerequisit = this.setEmrContainersForNamespace(clusterInfo, this.emrTeam.virtualClusterNamespace, this.emrTeam.createNamespace);

    this.emrTeam.executionRoles.forEach(executionRole => {

      const executionRolePolicy = executionRole.excutionRoleIamPolicy ?
        executionRole.excutionRoleIamPolicy :
        new ManagedPolicy(cluster.stack, `executionRole-${executionRole.executionRoleName}-Policy`, {
          statements: executionRole.executionRoleIamPolicyStatement,
        });

      this.createExecutionRole(
        cluster,
        executionRolePolicy,
        this.emrTeam.virtualClusterNamespace,
        executionRole.executionRoleName);
    });

    const blueprintTag: CfnTag = {
      key: 'created-with',
      value: 'cdk-blueprint',
    };

    let virtualClusterTags: CfnTag [] = this.emrTeam.virtualClusterTags ? this.emrTeam.virtualClusterTags : [] ;
    virtualClusterTags.push(blueprintTag);

    const teamVC = new CfnVirtualCluster(cluster.stack, `${this.emrTeam.virtualClusterName}-VirtualCluster`, {
      name: this.emrTeam.virtualClusterName,
      containerProvider: {
        id: cluster.clusterName,
        type: 'EKS',
        info: { eksInfo: { namespace: this.emrTeam.virtualClusterNamespace } },
      },
      tags: virtualClusterTags,
    });

    teamVC.node.addDependency(emrVcPrerequisit);
    teamVC.node.addDependency(emrOnEksAddOn);
    //Force dependency between the EKS cluster and EMR on EKS Virtual cluster
    teamVC.node.addDependency(clusterInfo.cluster);

    new CfnOutput(cluster.stack, `${this.emrTeam.virtualClusterName}-virtual cluster-id`, {
      value: teamVC.attrId
    });

  }
  /**
   * @internal
   * Private method to to apply k8s RBAC to the service account used by EMR on EKS service role
   * For more information on the RBAC read consult the EMR on EKS documentation in this link 
   * https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/setting-up-cluster-access.html
   * This method 
   * @param ClusterInfo EKS cluster where to apply the RBAC
   * @param namespace Namespace where the RBAC are applied
   * @param createNamespace flag to create namespace if not already created
   * @returns 
   */

  private setEmrContainersForNamespace(ClusterInfo: ClusterInfo, namespace: string, createNamespace: boolean): Construct {

    let doc = readYamlDocument(`${__dirname}/emr-containers-rbac-config.ytpl`);

    //Get the RBAC definition and replace with the namespace provided by the user
    const manifest = doc.split("---").map(e => loadYaml(e));

    const values: Values = {
      namespace: namespace
    };

    const manifestDeployment: ManifestDeployment = {
      name: 'emr-containers',
      namespace: namespace,
      manifest,
      values
    };

    const kubectlProvider = new KubectlProvider(ClusterInfo);
    const statement = kubectlProvider.addManifest(manifestDeployment);

    if (createNamespace) {
      const namespaceManifest = blueprints.utils.createNamespace(namespace, ClusterInfo.cluster, true);
      statement.node.addDependency(namespaceManifest);
    }

    return statement;
  }

  /**
   * @internal
   * private method to create the execution role for EMR on EKS scoped to a namespace and a given IAM role
   * @param cluster EKS cluster
   * @param policy IAM policy to use with the role
   * @param namespace Namespace of the EMR Virtual Cluster
   * @param name Name of the IAM role
   * @returns Role
   */
  private createExecutionRole(cluster: Cluster, policy: IManagedPolicy, namespace: string, name: string): Role {

    const stack = cluster.stack;

    let irsaConditionkey: CfnJson = new CfnJson(stack, `${name}roleIrsaConditionkey'`, {
      value: {
        [`${cluster.openIdConnectProvider.openIdConnectProviderIssuer}:sub`]: 'system:serviceaccount:' + namespace + ':emr-containers-sa-*-*-' + Aws.ACCOUNT_ID.toString() + '-' + simplebase.base36.encode(name),
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


