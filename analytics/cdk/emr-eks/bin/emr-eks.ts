#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { EmrEksTeamProps } from '@aws-quickstart/eks-blueprints';
import { ArnPrincipal, PolicyStatement } from 'aws-cdk-lib/aws-iam';
import EmrEksStack, { EmrEksBlueprintProps } from '../lib/emr-eks-blueprint-stack';
import VpcDefinintion from '../lib/vpc';

const app = new cdk.App();

const account = process.env.CDK_DEFAULT_ACCOUNT;
const region = process.env.CDK_DEFAULT_REGION;

const executionRolePolicyStatement: PolicyStatement[] = [
  new PolicyStatement({
    actions:['logs:PutLogEvents','logs:CreateLogStream','logs:DescribeLogGroups','logs:DescribeLogStreams'],
    resources:['arn:aws:logs:*:*:*'],
  }),
];

const dataTeamA: EmrEksTeamProps = {
  name: 'emr-data-team-a',
  virtualClusterName: 'emr-data-team-a',
  virtualClusterNamespace: 'batchjob',
  createNamespace: true,
  executionRoles: [
    {
      executionRoleIamPolicyStatement: executionRolePolicyStatement,
      executionRoleName: 'myBlueprintExecRole'
    }
  ]
};

const vpc = new VpcDefinintion(app, 'vpcStack', {env: {account, region}} ).vpc;

const props: EmrEksBlueprintProps = {
  env: { account, region },
  dataTeams: [dataTeamA],
  clusterAdminRoleArn: new ArnPrincipal('arn:aws:iam::11111111111:role/<ROLE-NAME>'),
  clusterVpc: vpc
};

new EmrEksStack().build(app, 'data-on-eks', props);
