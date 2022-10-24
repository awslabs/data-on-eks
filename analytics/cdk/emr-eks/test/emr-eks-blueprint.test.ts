/**
 * Tests EMR on EKS AddOn
 *
 * @group unit/emr-eks-blueprint
 */

import * as blueprints from '@aws-quickstart/eks-blueprints';
import * as cdk from 'aws-cdk-lib';
import { EmrEksAddOn } from '../lib/AddOns/emrEksAddOn';
import {EmrEksTeam, EmrEksTeamProps} from '../lib/teams/emrEksTeam';
import { PolicyStatement } from 'aws-cdk-lib/aws-iam';
import { Match, Template } from 'aws-cdk-lib/assertions';
import EmrEksStack from '../lib/emr-eks-stack';

const app = new cdk.App();

const account = '123456789012';
const region = 'eu-west-1';
const props = { env: { account, region } };

const myStack = new EmrEksStack().build(app, 'AddonRefactotingblueprint', props);

const template = Template.fromStack(myStack);

test('Verify the creation of emr-containters service role', () => {
    
    template.hasResourceProperties('AWS::IAM::ServiceLinkedRole', {
        AWSServiceName: "emr-containers.amazonaws.com"
      }
    );

});