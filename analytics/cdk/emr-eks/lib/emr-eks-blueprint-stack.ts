import { Construct } from 'constructs';
import * as blueprints from '@aws-quickstart/eks-blueprints'
import { GenericClusterProvider, GlobalResources, PlatformTeam, VpcProvider } from '@aws-quickstart/eks-blueprints';
import { CapacityType, Cluster, ClusterLoggingTypes, KubernetesVersion, NodegroupAmiType } from 'aws-cdk-lib/aws-eks';
import { InstanceType, IVpc, Vpc } from 'aws-cdk-lib/aws-ec2';
import { PolicyStatement } from 'aws-cdk-lib/aws-iam';
import { EmrEksTeam, EmrEksTeamProps } from './teams/emrEksTeam';
import { EmrEksAddOn } from './AddOns/emrEksAddOn';
import { StackProps } from 'aws-cdk-lib';

export interface EmrEksBlueprintProps extends StackProps {
  eksCluster?: GenericClusterProvider,
  clusterVpc?: IVpc,
  dataTeams: EmrEksTeamProps [],
  eksClusterName?: string,
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

    const clusterAdminTeam = new PlatformTeam({
      name: "adminteam",
      userRoleArn: "arn:aws:iam::372775283473:role/FULL"
    });

    let emrEksBlueprint = blueprints.EksBlueprint.builder();

    if (props.clusterVpc) {
      emrEksBlueprint.resourceProvider(GlobalResources.Vpc, new VpcProvider(props.clusterVpc.vpcId));
    }

    let emrTeams: EmrEksTeam [];

    props.dataTeams.forEach(dataTeam => {
      emrTeams.push(new EmrEksTeam(dataTeam) )
    });

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
        ...emrTeams!)
      .build(scope, `${id}-emr-eks-blueprint`);

  }
}

