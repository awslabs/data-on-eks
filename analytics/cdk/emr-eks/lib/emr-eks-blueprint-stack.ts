import { Construct } from 'constructs';
import * as blueprints from '@aws-quickstart/eks-blueprints'
import { DirectVpcProvider, GenericClusterProvider, GlobalResources, PlatformTeam, VpcProvider } from '@aws-quickstart/eks-blueprints';
import { CapacityType, Cluster, ClusterLoggingTypes, KubernetesVersion, NodegroupAmiType } from 'aws-cdk-lib/aws-eks';
import { InstanceType, IVpc, SubnetType, Vpc } from 'aws-cdk-lib/aws-ec2';
import { EmrEksTeam, EmrEksTeamProps } from './teams/emrEksTeam';
import { EmrEksAddOn } from './AddOns/emrEksAddOn';
import { Stack, StackProps } from 'aws-cdk-lib';
import VpcDefinintion from './vpc';
import { ArnPrincipal } from 'aws-cdk-lib/aws-iam';
import { cloneDeep } from '@aws-quickstart/eks-blueprints/dist/utils';

export interface EmrEksBlueprintProps extends StackProps {
  eksCluster?: GenericClusterProvider,
  clusterVpc?: IVpc,
  dataTeams: EmrEksTeamProps[],
  eksClusterName?: string,
  clusterAdminRoleArn: ArnPrincipal
}


export default class EmrEksStack {

  build(scope: Construct, id: string, props: EmrEksBlueprintProps) {

    const eksClusterLogging: ClusterLoggingTypes[] = [
      ClusterLoggingTypes.API,
      ClusterLoggingTypes.AUTHENTICATOR,
      ClusterLoggingTypes.SCHEDULER,
      ClusterLoggingTypes.CONTROLLER_MANAGER,
      ClusterLoggingTypes.AUDIT,
    ];

    const emrCluster: GenericClusterProvider = new blueprints.GenericClusterProvider({
      clusterName: props.eksClusterName ? props.eksClusterName : 'eksBlueprintCluster',
      version: KubernetesVersion.V1_23,
      managedNodeGroups: [
        {
          id: "core-node-grp",
          nodeGroupCapacityType: CapacityType.ON_DEMAND,
          amiType: NodegroupAmiType.AL2_X86_64,
          instanceTypes: [new InstanceType('m5.xlarge')],
          diskSize: 50
        },
        {
          id: "spark-node-grp",
          instanceTypes: [new InstanceType('r5d.large')],
          nodeGroupCapacityType: CapacityType.ON_DEMAND,
          amiType: NodegroupAmiType.AL2_X86_64,
          diskSize: 50,
          labels: {
            app: 'spark'
          },
          nodeGroupSubnets: {subnetType: SubnetType.PRIVATE_WITH_EGRESS, availabilityZones: [props.clusterVpc!.availabilityZones[0]]}

        }
      ],
      clusterLogging: eksClusterLogging
    }); 

    const clusterAdminTeam = new PlatformTeam({
      name: "adminteam",
      userRoleArn: props.clusterAdminRoleArn.arn
    });

    let emrEksBlueprint = blueprints.EksBlueprint.builder();

    if (props.clusterVpc) {
      emrEksBlueprint.resourceProvider(GlobalResources.Vpc, new DirectVpcProvider(props.clusterVpc));
    }

    let emrTeams: EmrEksTeam [] = [...props.dataTeams.map(team => new EmrEksTeam(team))];

    emrEksBlueprint = props.eksCluster ?
      emrEksBlueprint.clusterProvider(props.eksCluster) :
      emrEksBlueprint.clusterProvider(emrCluster);

    return emrEksBlueprint.addOns(
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
        ...emrTeams)
      .build(scope, `${id}-emr-eks-blueprint`);

  }
}

