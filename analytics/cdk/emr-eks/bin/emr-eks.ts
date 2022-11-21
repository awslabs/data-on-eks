#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { EmrEksTeamProps } from '../lib/teams/emrEksTeam';
import { ArnPrincipal, PolicyStatement } from 'aws-cdk-lib/aws-iam';
import EmrEksStack, { EmrEksBlueprintProps } from '../lib/emr-eks-blueprint-stack';
import VpcDefinintion from '../lib/vpc';

const app = new cdk.App();

const account = '1111111';
const region = 'eu-west-1';

const executionRolePolicyStatement: PolicyStatement[] = [
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

const dataTeamA: EmrEksTeamProps = {
  name: 'dataTeamA',
  virtualClusterName: 'mergejob',
  virtualClusterNamespace: 'mergejob',
  createNamespace: true,
  executionRoles: [
    {
      executionRoleIamPolicyStatement: executionRolePolicyStatement,
      executionRoleName: 'myBlueprintExecRoleMerge'
    }
  ]
};

const vpc = new VpcDefinintion(app, 'vpcStack', {env: {account, region}} ).vpc;

const props: EmrEksBlueprintProps = {
  env: { account, region },
  dataTeams: [dataTeamA],
  clusterAdminRoleArn: new ArnPrincipal('arn:aws:iam::11111111111:role/FULL'),
  clusterVpc: vpc
};

new EmrEksStack().build(app, 'BlueprintMergeReady', props);
