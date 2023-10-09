# // Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# // SPDX-License-Identifier: License :: OSI Approved :: MIT No Attribution License (MIT-0)
#!/usr/bin/env python3
from aws_cdk import (App,Tags,CfnOutput,Aws)
from source.lib.emr_on_ec2_stack import EMREC2Stack
from source.lib.msk_stack import MSKStack
from source.lib.spark_on_eks_stack import SparkOnEksStack

app = App()
proj_name = app.node.try_get_context('project_name')
emr_release_v=app.node.try_get_context('emr_version')

# main stacks
eks_stack = SparkOnEksStack(app, proj_name, proj_name)
msk_stack = MSKStack(eks_stack,'kafka', proj_name, eks_stack.eksvpc)

# OPTIONAL: nested stack to setup EMR on EC2
emr_ec2_stack = EMREC2Stack(eks_stack, 'emr-on-ec2', emr_release_v, proj_name, eks_stack.eksvpc, eks_stack.code_bucket)

Tags.of(eks_stack).add('project', proj_name)
Tags.of(msk_stack).add('project', proj_name)
Tags.of(emr_ec2_stack).add('for-use-with-amazon-emr-managed-policies', 'true')

# Deployment Output
CfnOutput(eks_stack,'CODE_BUCKET', value=eks_stack.code_bucket)
CfnOutput(eks_stack,"MSK_CLIENT_URL",
    value=f"https://{Aws.REGION}.console.aws.amazon.com/cloud9/home/environments/{msk_stack.Cloud9URL}?permissions=owner",
    description="Cloud9 Url, Use this URL to access your command line environment in a browser"
)
CfnOutput(eks_stack, "MSK_BROKER", value=msk_stack.MSKBroker)
CfnOutput(eks_stack, "VirtualClusterId",value=eks_stack.EMRVC)
CfnOutput(eks_stack, "FargateVirtualClusterId",value=eks_stack.EMRFargateVC)
CfnOutput(eks_stack, "EMRExecRoleARN", value=eks_stack.EMRExecRole)

app.synth()
