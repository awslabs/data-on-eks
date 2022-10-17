#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import EmrEksStack from '../lib/emr-eks-stack';
import { Stack } from 'aws-cdk-lib';

const app = new cdk.App();
const myStack = new Stack(app, 'myStack', {
    env: {account: '123456789012', region: 'eu-west-1'}
})
new EmrEksStack().build(myStack, 'blueprinttesting');