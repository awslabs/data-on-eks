---
title: 使用 Spark Streaming 的 EMR on EKS
sidebar_position: 2
---

:::danger
**弃用通知**

此蓝图将被弃用，并最终于 **2024年10月27日** 从此 GitHub 存储库中删除。不会修复任何错误，也不会添加新功能。弃用的决定基于对此蓝图缺乏需求和兴趣，以及难以分配资源来维护一个没有任何用户或客户积极使用的蓝图。

如果您在生产中使用此蓝图，请将自己添加到 [adopters.md](https://github.com/awslabs/data-on-eks/blob/main/ADOPTERS.md) 页面并在存储库中提出问题。这将帮助我们重新考虑并可能保留和继续维护该蓝图。否则，您可以制作本地副本或使用现有标签来访问它。
:::

# 使用 Spark Streaming 的 EMR on EKS

这是一个用 Python [CDK](https://docs.aws.amazon.com/cdk/latest/guide/home.html) 开发的项目。
它包括示例数据、Kafka 生产者模拟器，以及可以在 EMR on EC2 或 EMR on EKS 上运行的消费者示例。此外，我们还为不同用例添加了一些 Kinesis 示例。

基础设施部署包括以下内容：
- 一个新的 S3 存储桶来存储示例数据和流作业代码
- 跨 2 个可用区的新 VPC 中的 EKS 集群 v1.24
    - 集群有 2 个默认托管节点组：OnDemand 节点组从 1 扩展到 5，SPOT 实例节点组可以从 1 扩展到 30。
    - 它还有一个标记为 `serverless` 值的 Fargate 配置文件
- 同一 VPC 中的 EMR 虚拟集群
    - 虚拟集群链接到 `emr` 命名空间
    - 命名空间容纳两种类型的 Spark 作业，即在托管节点组上运行或在 Fargate 上运行的无服务器作业
    - 所有 EMR on EKS 配置都已完成，包括通过 AWS 原生解决方案服务账户的 IAM 角色为 Pod 提供细粒度访问控制
- 同一 VPC 中的 MSK 集群，总共有 2 个代理。Kafka 版本是 2.8.1
    - Cloud9 IDE 作为演示中的命令行环境。
    - Kafka 客户端工具将安装在 Cloud9 IDE 上
- 启用托管扩展的 EMR on EC2 集群。
    - 1 个主节点和 1 个核心节点，使用 r5.xlarge。
    - 配置为一次运行一个 Spark 作业。
    - 可以从 1 扩展到 10 个核心 + 任务节点
    - 挂载 EFS 用于检查点测试/演示（引导操作）

## Spark 示例 - 从 MSK 读取流
从 Amazon MSK 读取的 Spark 消费者应用程序：

* [1. 使用 EMR on EKS 运行作业](#1-使用-emr-on-eks-提交作业)
* [2. 在 EMR on EKS 上使用 Fargate 运行相同作业](#2-在-fargate-上使用-emr-on-eks)
* [3. 使用 EMR on EC2 运行相同作业](#3-可选-向-emr-on-ec2-提交步骤)

## Spark 示例 - 从 Kinesis 读取流
* [1. （可选）构建自定义 docker 镜像](#1-可选-构建自定义-docker-镜像)
* [2. 使用 kinesis-sql 连接器运行作业](#2-使用-kinesis-sql-连接器)
* [3. 使用 Spark 的 DStream 运行作业](#3-使用-spark-的-dstream)

## 部署基础设施

配置大约需要 30 分钟才能完成。
两种部署方式：
1. AWS CloudFormation 模板 (CFN)
2. [AWS Cloud Development Kit (AWS CDK)](https://docs.aws.amazon.com/cdk/latest/guide/home.html)。

### CloudFormation 部署

  |   区域  |   启动模板 |
  |  ---------------------------   |   -----------------------  |
  |  ---------------------------   |   -----------------------  |
  **美国东部（弗吉尼亚北部）**| [![部署到 AWS](../../../../../../docs/blueprints/streaming-platforms/img/00-deploy-to-aws.png)](https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/quickcreate?stackName=emr-stream-demo&templateURL=https://blogpost-sparkoneks-us-east-1.s3.amazonaws.com/emr-stream-demo/v2.0.0/emr-stream-demo.template)

* 要在不同的 AWS 区域启动，请查看以下自定义部分，或使用 CDK 部署选项。

### 自定义
您可以自定义解决方案，例如设置为不同的区域，然后在所需区域生成 CFN 模板：
```bash
export BUCKET_NAME_PREFIX=<my-bucket-name> # 自定义代码将驻留的存储桶
export AWS_REGION=<your-region>
export SOLUTION_NAME=emr-stream-demo
export VERSION=v2.0.0 # 自定义代码的版本号

cd data-on-eks/analytics/cdk/stream-emr-on-eks
./deployment/build-s3-dist.sh $BUCKET_NAME_PREFIX $SOLUTION_NAME $VERSION

# 创建自定义代码将驻留的存储桶
aws s3 mb s3://$BUCKET_NAME_PREFIX-$AWS_REGION --region $AWS_REGION

# 将部署资产上传到 S3 存储桶
aws s3 cp ./deployment/global-s3-assets/ s3://$BUCKET_NAME_PREFIX-$AWS_REGION/$SOLUTION_NAME/$VERSION/ --recursive --acl bucket-owner-full-control
aws s3 cp ./deployment/regional-s3-assets/ s3://$BUCKET_NAME_PREFIX-$AWS_REGION/$SOLUTION_NAME/$VERSION/ --recursive --acl bucket-owner-full-control

echo -e "\nIn web browser, paste the URL to launch the template: https://console.aws.amazon.com/cloudformation/home?region=$AWS_REGION#/stacks/quickcreate?stackName=emr-stream-demo&templateURL=https://$BUCKET_NAME_PREFIX-$AWS_REGION.s3.amazonaws.com/$SOLUTION_NAME/$VERSION/emr-stream-demo.template\n"
```

### CDK 部署

#### 先决条件
安装以下工具：
1. [Python 3.6 +](https://www.python.org/downloads/)。
2. [Node.js 10.3.0 +](https://nodejs.org/en/)
3. [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-macos.html#install-macosos-bundled)。通过 `aws configure` 配置 CLI。
4. [CDK 工具包](https://cdkworkshop.com/15-prerequisites/500-toolkit.html)
5. 首次部署的[一次性 CDK 引导](https://cdkworkshop.com/20-typescript/20-create-project/500-deploy.html)。

#### 部署
```bash
python3 -m venv .env
source .env/bin/activate
pip install -r requirements.txt

cdk deploy
```

## 部署后

以下 `post-deployment.sh` 在 Linux 中可执行，不适用于 Mac OSX。如需要请修改脚本。

1. 在 Cloud9 控制台中打开"Kafka Client" IDE。如果 Cloud9 IDE 不存在，请创建一个。
```
VPC 前缀：'emr-stream-demo'
实例类型：'t3.small'
```
2. [将包含 `Cloud9Admin` 的 IAM 角色附加到您的 IDE](https://catalog.us-east-1.prod.workshops.aws/workshops/d90c2f2d-a84b-4e80-b4f9-f5cee0614426/en-US/30-emr-serverless/31-set-up-env#setup-cloud9-ide)。

3. 在 Cloud9 中关闭 AWS 托管临时凭证：
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install --update
/usr/local/bin/aws cloud9 update-environment  --environment-id $C9_PID --managed-credentials-action DISABLE
rm -vf ${HOME}/.aws/credentials
```

4. 运行脚本配置 cloud9 IDE 环境：
```bash
curl https://raw.githubusercontent.com/aws-samples/stream-emr-on-eks/main/deployment/app_code/post-deployment.sh | bash
```
5. 等待 5 分钟，然后检查 [MSK 集群](https://console.aws.amazon.com/msk/) 状态。确保在向集群发送数据之前它是 `active` 状态。
6. 在 Cloud9 中启动新的终端窗口，向 MSK 发送示例数据：
```bash
wget https://github.com/xuite627/workshop_flink1015-1/raw/master/dataset/nycTaxiRides.gz
zcat nycTaxiRides.gz | split -l 10000 --filter="kafka_2.12-2.8.1/bin/kafka-console-producer.sh --broker-list ${MSK_SERVER} --topic taxirides ; sleep 0.2"  > /dev/null
```
6. 启动第 3 个终端窗口并监控源 MSK 主题：
```bash
kafka_2.12-2.8.1/bin/kafka-console-consumer.sh \
--bootstrap-server ${MSK_SERVER} \
--topic taxirides \
--from-beginning
```

## MSK 集成
### 1. 使用 EMR on EKS 提交作业

- [示例作业](https://github.com/aws-samples/stream-emr-on-eks/blob/main/deployment/app_code/job/msk_consumer.py) 消费 MSK 中的数据流
- 提交作业：
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
### 验证作业正在运行：
```bash
# 可以在 EKS 中看到作业 pod
kubectl get po -n emr

# 在 EMR 控制台中验证
# 在 Cloud9 中，运行消费者工具检查目标 Kafka 主题中是否有数据通过
kafka_2.12-2.8.1/bin/kafka-console-consumer.sh --bootstrap-server ${MSK_SERVER} --topic emreks_output --from-beginning
```
### 取消长时间运行的作业（可以从作业提交输出或 EMR 控制台获取作业 ID）
```bash
aws emr-containers cancel-job-run --virtual-cluster-id $VIRTUAL_CLUSTER_ID  --id <YOUR_JOB_ID>
```

### 2. 在 Fargate 上使用 EMR on EKS
在同一个 EKS 集群上运行[相同作业](https://github.com/aws-samples/stream-emr-on-eks/blob/main/deployment/app_code/job/msk_consumer.py)，但使用无服务器选项 - Fargate 计算选择。

为了确保它被 Fargate 而不是 EC2 上的托管节点组选中，我们将用 `serverless` 标签标记 Spark 作业，该标签之前已在 Fargate 配置文件中设置：
```yaml
--conf spark.kubernetes.driver.label.type=serverless
--conf spark.kubernetes.executor.label.type=serverless
```

向 Fargate 提交作业：

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
### 验证作业在 EKS Fargate 上运行
```bash
kubectl get po -n emr

# 在 EMR 控制台中验证
# 在 Cloud9 中，运行消费者工具检查目标 Kafka 主题中是否有数据通过
kafka_2.12-2.8.1/bin/kafka-console-consumer.sh \
--bootstrap-server ${MSK_SERVER} \
--topic emreksfg_output \
--from-beginning
```

### 3. （可选）向 EMR on EC2 提交步骤

```bash
cluster_id=$(aws emr list-clusters --cluster-states WAITING --query 'Clusters[?Name==`emr-stream-demo`].Id' --output text)
MSK_SERVER=$(echo $MSK_SERVER | cut -d',' -f 2)

aws emr add-steps \
--cluster-id $cluster_id \
--steps Type=spark,Name=emrec2_stream,Args=[--deploy-mode,cluster,--conf,spark.cleaner.referenceTracking.cleanCheckpoints=true,--conf,spark.executor.instances=2,--conf,spark.executor.memory=2G,--conf,spark.driver.memory=2G,--conf,spark.executor.cores=2,--packages,org.apache.spark:spark-sql-kafka-0-10_2.12:3.0.1,s3://$S3BUCKET/app_code/job/msk_consumer.py,$MSK_SERVER,s3://$S3BUCKET/stream/checkpoint/emrec2,emrec2_output],ActionOnFailure=CONTINUE
```

### 验证
```bash
# 在 EMR 控制台中验证
# 在 Cloud9 中，运行消费者工具检查目标 Kafka 主题中是否有数据通过
kafka_2.12-2.8.1/bin/kafka-console-consumer.sh \
--bootstrap-server ${MSK_SERVER} \
--topic emrec2_output \
--from-beginning
```

## Kinesis 集成

### 1. （可选）构建自定义 docker 镜像
我们将通过 boto3 动态创建和删除 kinesis 测试流，因此需要包含 Python 库的自定义 EMR on EKS docker 镜像。如果您不需要 boto3 和 kinesis-sql 连接器，则自定义 docker 镜像不是必需的。

基于 EMR on EKS 6.5 构建镜像：
```bash
export AWS_REGION=$(aws configure list | grep region | awk '{print $2}')
export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
export ECR_URL=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 895885662937.dkr.ecr.us-west-2.amazonaws.com
docker build -t emr6.5_custom .

# 在当前账户中创建 ECR 存储库
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL
aws ecr create-repository --repository-name emr6.5_custom_boto3 --image-scanning-configuration scanOnPush=true --region $AWS_REGION

# 推送到 ECR
docker tag emr6.5_custom $ECR_URL/emr6.5_custom_boto3
docker push $ECR_URL/emr6.5_custom_boto3
```

### 2. 使用 kinesis-sql 连接器
此演示使用 `com.qubole.spark/spark-sql-kinesis_2.12/1.2.0-spark_3.0` 连接器与 Kinesis 交互。

为了启用作业级访问控制，即 [IRSA 功能](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)，我们分叉了 [kinesis-sql git 存储库](https://github.com/aws-samples/kinesis-sql) 并在升级 AWS java SDK 后重新编译了新的 jar。上面的自定义 docker 构建将自动选择升级的连接器。

- [示例作业](https://github.com/aws-samples/stream-emr-on-eks/blob/main/deployment/app_code/job/qubole-kinesis.py) 消费 Kinesis 中的数据流
- 提交作业：
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

### 3. 使用 Spark 的 DStream

此演示使用 `spark-streaming-kinesis-asl_2.12` 库从 Kinesis 读取。查看 [Spark 官方文档](https://spark.apache.org/docs/latest/streaming-kinesis-integration.html)。Spark 语法与 spark-sql-kinesis 方法略有不同。它在 RDD 级别操作。

- [示例作业](https://github.com/aws-samples/stream-emr-on-eks/blob/main/deployment/app_code/job/pyspark-kinesis.py) 从 Kinesis 消费数据流
- 提交作业：
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

## 有用的命令

 * `kubectl get pod -n emr`               列出正在运行的 Spark 作业
 * `kubectl delete pod --all -n emr`      删除所有 Spark 作业
 * `kubectl logs <pod name> -n emr`       检查 emr 命名空间中 pod 的日志
 * `kubectl get node --label-columns=eks.amazonaws.com/capacityType,topology.kubernetes.io/zone` 检查 EKS 计算容量类型和可用区分布。

## 清理
运行清理脚本：
```bash
curl https://raw.githubusercontent.com/aws-samples/stream-emr-on-eks/main/deployment/app_code/delete_all.sh | bash
```
转到 [CloudFormation 控制台](https://console.aws.amazon.com/cloudformation/home?region=us-east-1)，如需要手动删除剩余资源。
