# // Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# // SPDX-License-Identifier: License :: OSI Approved :: MIT No Attribution License (MIT-0)
from constructs import Construct
from aws_cdk import (RemovalPolicy, aws_s3 as s3,aws_s3_deployment as s3deploy)
import os

class S3AppCodeConst(Construct):

    @property
    def code_bucket(self):
        return self.bucket_name

    def __init__(self,scope: Construct, id: str, **kwargs,) -> None:
        super().__init__(scope, id, **kwargs)

       # Upload application code to S3 bucket 
        self._artifact_bucket=s3.Bucket(self, id, 
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.KMS_MANAGED,
            removal_policy= RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

        proj_dir=os.path.split(os.environ['VIRTUAL_ENV'])[0]
        self.deploy=s3deploy.BucketDeployment(self, "DeployCode",
            sources=[s3deploy.Source.asset(proj_dir+'/deployment/app_code')],
            destination_bucket= self._artifact_bucket,
            destination_key_prefix="app_code",
            memory_limit=256
        )
        self.bucket_name = self._artifact_bucket.bucket_name