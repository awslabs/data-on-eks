/**
 * Tests EMR on EKS AddOn
 *
 * @group unit/emr-eks-addon
 */

import * as blueprints from '@aws-quickstart/eks-blueprints';
import * as cdk from 'aws-cdk-lib';
import { EmrEksAddOn } from '../lib/AddOns/emrEksAddOn';
import {EmrEksTeam, EmrEksTeamProps} from '../lib/teams/emrEksTeam';
import { PolicyStatement } from 'aws-cdk-lib/aws-iam';
import { Template } from 'aws-cdk-lib/assertions';

const app = new cdk.App();

const executionRolePolicyStatement: PolicyStatement [] = [
      new PolicyStatement({
        resources: ['*'],
        actions: ['s3:*'],
      }),
      new PolicyStatement({
        resources: ['*'],
        actions: ['glue:*'],
      }),
      new PolicyStatement({
        resources: ['*'],
        actions: [
          'logs:*',
        ],
      }),
    ];

const dataTeam: EmrEksTeamProps = {
        name:'dataTeam',
        virtualClusterName: 'batchJob',
        virtualClusterNamespace: 'batchjob',
        createNamespace: true,
        executionRoles: [
            {
                executionRoleIamPolicyStatement: executionRolePolicyStatement,
                executionRoleName: 'myBlueprintExecRole'
            }
        ]
    };

const parentStack = blueprints.EksBlueprint.builder()
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
            new EmrEksTeam(dataTeam))
        .build(app, "test-emr-eks-blueprint");

const template = Template.fromStack(parentStack);

test('Verify the creation of emr-containters service role', () => {

    template.hasResourceProperties('AWS::IAM::ServiceLinkedRole', {
        AWSServiceName: "emr-containers.amazonaws.com"
      }
    );

});
