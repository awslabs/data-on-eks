# Spark Structured Streaming Demo with EMR on EKS

:::danger
**DEPRECATION NOTICE**

This blueprint will be deprecated and eventually removed from this GitHub repository on **October 27, 2024**. No bugs will be fixed, and no new features will be added. The decision to deprecate is based on the lack of demand and interest in this blueprint, as well as the difficulty in allocating resources to maintain a blueprint that is not actively used by any users or customers.

If you are using this blueprint in production, please add yourself to the [adopters.md](https://github.com/awslabs/data-on-eks/blob/main/ADOPTERS.md) page and raise an issue in the repository. This will help us reconsider and possibly retain and continue to maintain the blueprint. Otherwise, you can make a local copy or use existing tags to access it.
:::


This is a project developed in Python [CDK](https://docs.aws.amazon.com/cdk/latest/guide/home.html).
It includes sample data, Kafka producer simulator, and a consumer example that can be run with EMR on EC2 or EMR on EKS. Additionally, we have added few Kinesis examples for difference use cases.

The infrastructure deployment includes the following:
- A new S3 bucket to store sample data and stream job code
- An EKS cluster v1.24 in a new VPC across 2 AZs
    - The Cluster has 2 default managed node groups: the OnDemand nodegroup scales from 1 to 5, SPOT instance nodegroup can scale from 1 to 30.
    - It also has a Fargate profile labelled with the value `serverless`
- An EMR virtual cluster in the same VPC
    - The virtual cluster links to `emr` namespace
    - The namespace accommodates two types of Spark jobs, ie. run on managed node group or serverless job on Fargate
    - All EMR on EKS configuration are done, including fine-grained access controls for pods by the AWS native solution IAM roles for service accounts
- A MSK Cluster in the same VPC with 2 brokers in total. Kafka version is 2.8.1
    - A Cloud9 IDE as the command line environment in the demo.
    - Kafka Client tool will be installed on the Cloud9 IDE
- An EMR on EC2 cluster with managed scaling enabled.
    - 1 primary and 1 core nodes with r5.xlarge.
    - configured to run one Spark job at a time.
    - can scale from 1 to 10 core + task nodes
    - mounted EFS for checkpointing test/demo (a bootstrap action)

## Spark examples - read stream from MSK
Spark consumer applications reading from Amazon MSK:

* [1. Run a job with EMR on EKS](#1-submit-a-job-with-emr-on-eks)
* [2. Same job with Fargate on EMR on EKS](#2-EMR-on-EKS-with-Fargate)
* [3. Same job with EMR on EC2](#3-optional-Submit-step-to-EMR-on-EC2)

## Spark examples - read stream from Kinesis
* [1. (Optional) Build a custom docker image](#1-optional-Build-custom-docker-image)
* [2. Run a job with kinesis-sql connector](#2-Use-kinesis-sql-connector)
* [3. Run a job with Spark's DStream](#3-use-spark-s-dstream)

## Deploy Infrastructure

The provisioning takes about 30 minutes to complete.
Two ways to deploy:
1. AWS CloudFormation template (CFN)
2. [AWS Cloud Development Kit (AWS CDK)](https://docs.aws.amazon.com/cdk/latest/guide/home.html).

### CloudFormation Deployment

  |   Region  |   Launch Template |
  |  ---------------------------   |   -----------------------  |
  |  ---------------------------   |   -----------------------  |
  **US East (N. Virginia)**| [![Deploy to AWS](source/app_resources/00-deploy-to-aws.png)](https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/quickcreate?stackName=emr-stream-demo&templateURL=https://blogpost-sparkoneks-us-east-1.s3.amazonaws.com/emr-stream-demo/v2.0.0/emr-stream-demo.template)

* To launch in a different AWS Region, check out the following customization section, or use the CDK deployment option.

### Customization
You can customize the solution, such as set to a different region, then generate the CFN templates in your required region:
```bash
export BUCKET_NAME_PREFIX=<my-bucket-name> # bucket where customized code will reside
export AWS_REGION=<your-region>
export SOLUTION_NAME=emr-stream-demo
export VERSION=v2.0.0 # version number for the customized code

./deployment/build-s3-dist.sh $BUCKET_NAME_PREFIX $SOLUTION_NAME $VERSION

# create the bucket where customized code will reside
aws s3 mb s3://$BUCKET_NAME_PREFIX-$AWS_REGION --region $AWS_REGION

# Upload deployment assets to the S3 bucket
aws s3 cp ./deployment/global-s3-assets/ s3://$BUCKET_NAME_PREFIX-$AWS_REGION/$SOLUTION_NAME/$VERSION/ --recursive --acl bucket-owner-full-control
aws s3 cp ./deployment/regional-s3-assets/ s3://$BUCKET_NAME_PREFIX-$AWS_REGION/$SOLUTION_NAME/$VERSION/ --recursive --acl bucket-owner-full-control

echo -e "\nIn web browser, paste the URL to launch the template: https://console.aws.amazon.com/cloudformation/home?region=$AWS_REGION#/stacks/quickcreate?stackName=emr-stream-demo&templateURL=https://$BUCKET_NAME_PREFIX-$AWS_REGION.s3.amazonaws.com/$SOLUTION_NAME/$VERSION/emr-stream-demo.template\n"
```

### CDK Deployment

#### Prerequisites
Install the following tools:
1. [Python 3.6 +](https://www.python.org/downloads/).
2. [Node.js 10.3.0 +](https://nodejs.org/en/)
3. [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-macos.html#install-macosos-bundled). Configure the CLI by `aws configure`.
4. [CDK toolkit](https://cdkworkshop.com/15-prerequisites/500-toolkit.html)
5. [One-off CDK bootstrap](https://cdkworkshop.com/20-typescript/20-create-project/500-deploy.html) for the first time deployment.

#### Deploy
```bash
python3 -m venv .env
source .env/bin/activate
pip install -r requirements.txt

cdk deploy
```

## Post-deployment

The following `post-deployment.sh` is executable in Linux, not for Mac OSX. Modify the script if needed.

1. Open the "Kafka Client" IDE in Cloud9 console. Create one if the Cloud9 IDE doesn't exist.
```
VPC prefix: 'emr-stream-demo'
Instance Type: 't3.small'
```
2. [Attach the IAM role that contains `Cloud9Admin` to your IDE](https://catalog.us-east-1.prod.workshops.aws/workshops/d90c2f2d-a84b-4e80-b4f9-f5cee0614426/en-US/30-emr-serverless/31-set-up-env#setup-cloud9-ide).

3. Turn off AWS managed temporary credentials in Cloud9:
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install --update
/usr/local/bin/aws cloud9 update-environment  --environment-id $C9_PID --managed-credentials-action DISABLE
rm -vf ${HOME}/.aws/credentials
```

4. Run the script to configure the cloud9 IDE environment:
```bash
curl https://raw.githubusercontent.com/aws-samples/stream-emr-on-eks/main/deployment/app_code/post-deployment.sh | bash
```
5. Wait for 5 mins, then check the [MSK cluster](https://console.aws.amazon.com/msk/) status. Make sure it is `active` before sending data to the cluster.
6. Launching a new terminal window in Cloud9, send the sample data to MSK:
```bash
wget https://github.com/xuite627/workshop_flink1015-1/raw/master/dataset/nycTaxiRides.gz
zcat nycTaxiRides.gz | split -l 10000 --filter="kafka_2.12-2.8.1/bin/kafka-console-producer.sh --broker-list ${MSK_SERVER} --topic taxirides ; sleep 0.2"  > /dev/null
```
6. Launching the 3rd terminal window and monitor the source MSK topic:
```bash
kafka_2.12-2.8.1/bin/kafka-console-consumer.sh \
--bootstrap-server ${MSK_SERVER} \
--topic taxirides \
--from-beginning
```

## MSK integration
### 1. Submit a job with EMR on EKS

- [Sample job](deployment/app_code/job/msk_consumer.py) to consume data stream in MSK
- Submit the job:
```bash
aws emr-containers start-job-run \
--virtual-cluster-id $VIRTUAL_CLUSTER_ID \
--name msk_consumer \
--execution-role-arn $EMR_ROLE_ARN \
--release-label emr-5.33.0-latest \
--job-driver '{
    "sparkSubmitJobDriver":{
        "entryPoint": "s3://'$S3BUCKET'/app_code/job/msk_consumer.py",
        "entryPointArguments":["'$MSK_SERVER'","s3://'$S3BUCKET'/stream/checkpoint/emreks","emreks_output"],
        "sparkSubmitParameters": "--conf spark.jars.packages=org.apache.spark:spark-sql-kafka-0-10_2.11:2.4.7 --conf spark.cleaner.referenceTracking.cleanCheckpoints=true --conf spark.executor.instances=2 --conf spark.executor.memory=2G --conf spark.driver.memory=2G --conf spark.executor.cores=2"}}' \
--configuration-overrides '{
    "applicationConfiguration": [
      {
        "classification": "spark-defaults",
        "properties": {
          "spark.kubernetes.driver.podTemplateFile":"s3://'$S3BUCKET'/app_code/job/driver_template.yaml","spark.kubernetes.executor.podTemplateFile":"s3://'$S3BUCKET'/app_code/job/executor_template.yaml"
         }
      }
    ],
    "monitoringConfiguration": {
        "s3MonitoringConfiguration": {"logUri": "s3://'${S3BUCKET}'/elasticmapreduce/emreks-log/"}}
}'
```
### Verify the job is running:
```bash
# can see the job pod in EKS
kubectl get po -n emr

# verify in EMR console
# in Cloud9, run the consumer tool to check if any data comeing through in the target Kafka topic
kafka_2.12-2.8.1/bin/kafka-console-consumer.sh --bootstrap-server ${MSK_SERVER} --topic emreks_output --from-beginning
```
### Cancel the long-running job (can get job id from the job submission output or in EMR console)
```bash
aws emr-containers cancel-job-run --virtual-cluster-id $VIRTUAL_CLUSTER_ID  --id <YOUR_JOB_ID>
```

### 2. EMR on EKS with Fargate
Run the [same job](deployment/app_code/job/msk_consumer.py) on the same EKS cluster, but with the serverless option - Fargate compute choice.

To ensure it is picked up by Fargate not by the managed nodegroup on EC2, we will tag the Spark job by a `serverless` label, which has setup in a Fargate profile previously:
```yaml
--conf spark.kubernetes.driver.label.type=serverless
--conf spark.kubernetes.executor.label.type=serverless
```

Submit the job to Fargate:

```bash
aws emr-containers start-job-run \
--virtual-cluster-id $VIRTUAL_CLUSTER_ID \
--name msk_consumer_fg \
--execution-role-arn $EMR_ROLE_ARN \
--release-label emr-5.33.0-latest \
--job-driver '{
    "sparkSubmitJobDriver":{
        "entryPoint": "s3://'$S3BUCKET'/app_code/job/msk_consumer.py",
        "entryPointArguments":["'$MSK_SERVER'","s3://'$S3BUCKET'/stream/checkpoint/emreksfg","emreksfg_output"],
        "sparkSubmitParameters": "--conf spark.jars.packages=org.apache.spark:spark-sql-kafka-0-10_2.11:2.4.7 --conf spark.cleaner.referenceTracking.cleanCheckpoints=true --conf spark.executor.instances=2 --conf spark.executor.memory=2G --conf spark.driver.memory=2G --conf spark.executor.cores=2 --conf spark.kubernetes.driver.label.type=serverless --conf spark.kubernetes.executor.label.type=serverless"}}' \
--configuration-overrides '{
    "monitoringConfiguration": {
        "s3MonitoringConfiguration": {"logUri": "s3://'${S3BUCKET}'/elasticmapreduce/emreksfg-log/"}}}'
```
### Verify the job is running on EKS Fargate
```bash
kubectl get po -n emr

# verify in EMR console
# in Cloud9, run the consumer tool to check if any data comeing through in the target Kafka topic
kafka_2.12-2.8.1/bin/kafka-console-consumer.sh \
--bootstrap-server ${MSK_SERVER} \
--topic emreksfg_output \
--from-beginning
```

### 3. (Optional) Submit step to EMR on EC2

```bash
cluster_id=$(aws emr list-clusters --cluster-states WAITING --query 'Clusters[?Name==`emr-stream-demo`].Id' --output text)
MSK_SERVER=$(echo $MSK_SERVER | cut -d',' -f 2)

aws emr add-steps \
--cluster-id $cluster_id \
--steps Type=spark,Name=emrec2_stream,Args=[--deploy-mode,cluster,--conf,spark.cleaner.referenceTracking.cleanCheckpoints=true,--conf,spark.executor.instances=2,--conf,spark.executor.memory=2G,--conf,spark.driver.memory=2G,--conf,spark.executor.cores=2,--packages,org.apache.spark:spark-sql-kafka-0-10_2.12:3.0.1,s3://$S3BUCKET/app_code/job/msk_consumer.py,$MSK_SERVER,s3://$S3BUCKET/stream/checkpoint/emrec2,emrec2_output],ActionOnFailure=CONTINUE
```

### Verify
```bash
# verify in EMR console
# in Cloud9, run the consumer tool to check if any data comeing through in the target Kafka topic
kafka_2.12-2.8.1/bin/kafka-console-consumer.sh \
--bootstrap-server ${MSK_SERVER} \
--topic emrec2_output \
--from-beginning
```

## Kinesis integration

### 1. (Optional) Build custom docker image
We will create & delete a kinesis test stream on the fly via boto3, so a custom EMR on EKS docker image to include the Python library is needed. The custom docker image is not compulsory, if you don't need the boto3 and kinesis-sql connector.

Build a image based on EMR on EKS 6.5:
```bash
export AWS_REGION=$(aws configure list | grep region | awk '{print $2}')
export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
export ECR_URL=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 895885662937.dkr.ecr.us-west-2.amazonaws.com
docker build -t emr6.5_custom .

# create ECR repo in current account
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL
aws ecr create-repository --repository-name emr6.5_custom_boto3 --image-scanning-configuration scanOnPush=true --region $AWS_REGION

# push to ECR
docker tag emr6.5_custom $ECR_URL/emr6.5_custom_boto3
docker push $ECR_URL/emr6.5_custom_boto3
```

### 2. Use kinesis-sql connector
This demo uses the `com.qubole.spark/spark-sql-kinesis_2.12/1.2.0-spark_3.0` connector to interact with Kinesis.

To enable the job-level access control, ie. the [IRSA feature](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html), we have forked the [kinesis-sql git repo](https://github.com/aws-samples/kinesis-sql) and recompiled a new jar after upgraded the AWS java SDK. The custom docker build above will pick up the upgraded connector automatically.

- [Sample job](deployment/app_code/job/qubole-kinesis.py) to consume data stream in Kinesis
- Submit the job:
```bash
export AWS_REGION=$(aws configure list | grep region | awk '{print $2}')
export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
export ECR_URL=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

aws emr-containers start-job-run \
--virtual-cluster-id $VIRTUAL_CLUSTER_ID \
--name kinesis-demo \
--execution-role-arn $EMR_ROLE_ARN \
--release-label emr-6.5.0-latest \
--job-driver '{
    "sparkSubmitJobDriver":{
        "entryPoint": "s3://'$S3BUCKET'/app_code/job/qubole-kinesis.py",
        "entryPointArguments":["'${AWS_REGION}'","s3://'${S3BUCKET}'/qubolecheckpoint","s3://'${S3BUCKET}'/qubole-kinesis-output"],
        "sparkSubmitParameters": "--conf spark.cleaner.referenceTracking.cleanCheckpoints=true"}}' \
--configuration-overrides '{
    "applicationConfiguration": [
        {
            "classification": "spark-defaults",
            "properties": {
                "spark.kubernetes.container.image": "'${ECR_URL}'/emr6.5_custom_boto3:latest"
            }
        }
    ],
    "monitoringConfiguration": {
        "s3MonitoringConfiguration": {"logUri": "s3://'${S3BUCKET}'/elasticmapreduce/kinesis-fargate-log/"}
    }
}'
```

### 3. Use Spark's DStream

This demo uses the `spark-streaming-kinesis-asl_2.12` library to read from Kinesis. Check out the [Spark's official document](https://spark.apache.org/docs/latest/streaming-kinesis-integration.html). The Spark syntax is slightly different from the spark-sql-kinesis approach. It operates at RDD level.

- [Sample job](deployment/app_code/job/pyspark-kinesis.py) to consume data stream from Kinesis
- Submit the job:
```bash
export AWS_REGION=$(aws configure list | grep region | awk '{print $2}')
export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
export ECR_URL=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

aws emr-containers start-job-run \
--virtual-cluster-id $VIRTUAL_CLUSTER_ID \
--name kinesis-demo \
--execution-role-arn $EMR_ROLE_ARN \
--release-label emr-6.5.0-latest \
--job-driver '{
    "sparkSubmitJobDriver":{
        "entryPoint": "s3://'$S3BUCKET'/app_code/job/pyspark-kinesis.py",
        "entryPointArguments":["'${AWS_REGION}'","s3://'$S3BUCKET'/asloutput/"],
        "sparkSubmitParameters": "--jars https://repo1.maven.org/maven2/org/apache/spark/spark-streaming-kinesis-asl_2.12/3.1.2/spark-streaming-kinesis-asl_2.12-3.1.2.jar,https://repo1.maven.org/maven2/com/amazonaws/amazon-kinesis-client/1.12.0/amazon-kinesis-client-1.12.0.jar"}}' \
--configuration-overrides '{
    "applicationConfiguration": [
        {
            "classification": "spark-defaults",
            "properties": {
                "spark.kubernetes.container.image": "'${ECR_URL}'/emr6.5_custom_boto3:latest"
            }
        }
    ],
    "monitoringConfiguration": {
        "s3MonitoringConfiguration": {"logUri": "s3://'${S3BUCKET}'/elasticmapreduce/kinesis-fargate-log/"}
    }
}'
```

## Useful commands

 * `kubectl get pod -n emr`               list running Spark jobs
 * `kubectl delete pod --all -n emr`      delete all Spark jobs
 * `kubectl logs <pod name> -n emr`       check logs against a pod in the emr namespace
 * `kubectl get node --label-columns=eks.amazonaws.com/capacityType,topology.kubernetes.io/zone` check EKS compute capacity types and AZ distribution.


## Clean up
Run the clean-up script with:
```bash
curl https://raw.githubusercontent.com/aws-samples/stream-emr-on-eks/main/deployment/app_code/delete_all.sh | bash
```
Go to the [CloudFormation console](https://console.aws.amazon.com/cloudformation/home?region=us-east-1), manually delete the remaining resources if needed.
