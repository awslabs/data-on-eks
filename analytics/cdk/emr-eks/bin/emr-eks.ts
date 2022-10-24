#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import EmrEksStack from '../lib/emr-eks-stack';
import { Stack } from 'aws-cdk-lib';
import { EmrEksTeamProps } from '../lib/teams/emrEksTeam';
import { PolicyStatement } from 'aws-cdk-lib/aws-iam';

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

  const dataTeam: EmrEksTeamProps = {
    name: 'dataTeam',
    virtualClusterName: 'batchJob',
    virtualClusterNamespace: 'batchjob',
    createNamespace: true,
    excutionRoles: [
      {
        excutionRoleIamPolicyStatement: executionRolePolicyStatement,
        excutionRoleName: 'myBlueprintExecRole'
      }
    ]
  };

  const props = { 
                    env: { account, region },
                    dataTeams: [dataTeam]
                };

new EmrEksStack().build(app, 'BlueprintRefactoring', props);
