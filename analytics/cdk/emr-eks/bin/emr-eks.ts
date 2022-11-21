#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import EmrEksStack from '../lib/emr-eks-stack';
import { EmrEksTeamProps } from '../lib/teams/emrEksTeam';
import { PolicyStatement } from 'aws-cdk-lib/aws-iam';
import { EmrEksBlueprintProps } from '../lib/emr-eks-blueprint-stack';

const app = new cdk.App();

const account = '123456789012';
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
  virtualClusterName: 'blueprintjob',
  virtualClusterNamespace: 'blueprintjob',
  createNamespace: true,
  executionRoles: [
    {
      executionRoleIamPolicyStatement: executionRolePolicyStatement,
      executionRoleName: 'myBlueprintExecRole'
    }
  ]
};

const props: EmrEksBlueprintProps = {
  env: { account, region },
  dataTeams: [dataTeamA]
};

new EmrEksStack().build(app, 'BlueprintRefactoring', props);
