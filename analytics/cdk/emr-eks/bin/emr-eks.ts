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
    actions:['s3:PutObject','s3:GetObject','s3:ListBucket'], 
    resources:['YOUR-DATA-S3-BUCKET']
  }),
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
