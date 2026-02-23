---
title: EMR on EKS 기반 Spark Streaming
sidebar_position: 2
---

:::danger
**지원 중단 공지**

이 블루프린트는 **2024년 10월 27일**에 이 GitHub 저장소에서 지원 중단되고 최종적으로 제거될 예정입니다. 버그 수정 및 새로운 기능 추가가 이루어지지 않습니다. 이 블루프린트에 대한 수요와 관심 부족, 그리고 사용자나 고객이 적극적으로 사용하지 않는 블루프린트를 유지 관리하기 위한 리소스 할당의 어려움으로 인해 지원 중단이 결정되었습니다.

프로덕션에서 이 블루프린트를 사용하고 있다면 [adopters.md](https://github.com/awslabs/data-on-eks/blob/main/ADOPTERS.md) 페이지에 자신을 추가하고 저장소에 이슈를 제기해 주세요. 이를 통해 블루프린트를 재고하고 유지 관리를 계속할 수 있습니다. 그렇지 않으면 로컬 복사본을 만들거나 기존 태그를 사용하여 액세스할 수 있습니다.
:::


# EMR on EKS 기반 Spark Streaming

이것은 Python [CDK](https://docs.aws.amazon.com/cdk/latest/guide/home.html)로 개발된 프로젝트입니다.
샘플 데이터, Kafka 프로듀서 시뮬레이터, EMR on EC2 또는 EMR on EKS로 실행할 수 있는 컨슈머 예제가 포함되어 있습니다. 추가로 다양한 사용 사례를 위한 여러 Kinesis 예제도 추가했습니다.

인프라 배포에는 다음이 포함됩니다:
- 샘플 데이터 및 스트림 작업 코드를 저장할 새 S3 버킷
- 2개의 AZ에 걸친 새 VPC의 EKS 클러스터 v1.24
    - 클러스터에는 2개의 기본 관리형 노드 그룹이 있습니다: OnDemand 노드 그룹은 1에서 5까지 확장되고, SPOT 인스턴스 노드 그룹은 1에서 30까지 확장될 수 있습니다.
    - `serverless` 값으로 레이블이 지정된 Fargate 프로파일도 있습니다.
- 동일한 VPC의 EMR 가상 클러스터
    - 가상 클러스터는 `emr` 네임스페이스에 연결됩니다.
    - 네임스페이스는 두 가지 유형의 Spark 작업을 수용합니다. 즉, 관리형 노드 그룹에서 실행하거나 Fargate에서 서버리스 작업으로 실행합니다.
    - 파드에 대한 세분화된 액세스 제어를 위한 AWS 네이티브 솔루션인 IAM roles for service accounts를 포함한 모든 EMR on EKS 구성이 완료되어 있습니다.
- 총 2개의 브로커가 있는 동일한 VPC의 MSK 클러스터. Kafka 버전은 2.8.1입니다.
    - 데모의 명령줄 환경으로 Cloud9 IDE
    - Cloud9 IDE에 Kafka 클라이언트 도구가 설치됩니다.
- 관리형 스케일링이 활성화된 EMR on EC2 클러스터
    - r5.xlarge의 1개 프라이머리 및 1개 코어 노드
    - 한 번에 하나의 Spark 작업을 실행하도록 구성
    - 1에서 10개의 코어 + 태스크 노드로 확장 가능
    - 체크포인팅 테스트/데모용으로 EFS 마운트됨(부트스트랩 액션)

## Spark 예제 - MSK에서 스트림 읽기
Amazon MSK에서 읽는 Spark 컨슈머 애플리케이션:

* [1. EMR on EKS로 작업 실행](#1-submit-a-job-with-emr-on-eks)
* [2. EMR on EKS에서 Fargate로 동일한 작업 실행](#2-emr-on-eks-with-fargate)
* [3. EMR on EC2로 동일한 작업 실행](#3-optional-submit-step-to-emr-on-ec2)

## Spark 예제 - Kinesis에서 스트림 읽기
* [1. (선택 사항) 커스텀 Docker 이미지 빌드](#1-optional-build-custom-docker-image)
* [2. kinesis-sql 커넥터로 작업 실행](#2-use-kinesis-sql-connector)
* [3. Spark의 DStream으로 작업 실행](#3-use-sparks-dstream)

## 인프라 배포

프로비저닝은 완료하는 데 약 30분이 소요됩니다.
두 가지 배포 방법이 있습니다:
1. AWS CloudFormation 템플릿 (CFN)
2. [AWS Cloud Development Kit (AWS CDK)](https://docs.aws.amazon.com/cdk/latest/guide/home.html)

### CloudFormation 배포

  |   리전  |   템플릿 실행 |
  |  ---------------------------   |   -----------------------  |
  |  ---------------------------   |   -----------------------  |
  **US East (N. Virginia)**| [![Deploy to AWS](img/00-deploy-to-aws.png)](https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/quickcreate?stackName=emr-stream-demo&templateURL=https://blogpost-sparkoneks-us-east-1.s3.amazonaws.com/emr-stream-demo/v2.0.0/emr-stream-demo.template)

* 다른 AWS 리전에서 실행하려면 다음 커스터마이징 섹션을 확인하거나 CDK 배포 옵션을 사용하세요.

### 커스터마이징
다른 리전으로 설정하는 등 솔루션을 커스터마이징한 다음 필요한 리전에서 CFN 템플릿을 생성할 수 있습니다:
```bash
export BUCKET_NAME_PREFIX=<my-bucket-name> # 커스터마이징된 코드가 있을 버킷
export AWS_REGION=<your-region>
export SOLUTION_NAME=emr-stream-demo
export VERSION=v2.0.0 # 커스터마이징된 코드의 버전 번호

cd data-on-eks/analytics/cdk/stream-emr-on-eks
./deployment/build-s3-dist.sh $BUCKET_NAME_PREFIX $SOLUTION_NAME $VERSION

# 커스터마이징된 코드가 있을 버킷 생성
aws s3 mb s3://$BUCKET_NAME_PREFIX-$AWS_REGION --region $AWS_REGION

# 배포 에셋을 S3 버킷에 업로드
aws s3 cp ./deployment/global-s3-assets/ s3://$BUCKET_NAME_PREFIX-$AWS_REGION/$SOLUTION_NAME/$VERSION/ --recursive --acl bucket-owner-full-control
aws s3 cp ./deployment/regional-s3-assets/ s3://$BUCKET_NAME_PREFIX-$AWS_REGION/$SOLUTION_NAME/$VERSION/ --recursive --acl bucket-owner-full-control

echo -e "\n웹 브라우저에서 URL을 붙여넣어 템플릿을 실행하세요: https://console.aws.amazon.com/cloudformation/home?region=$AWS_REGION#/stacks/quickcreate?stackName=emr-stream-demo&templateURL=https://$BUCKET_NAME_PREFIX-$AWS_REGION.s3.amazonaws.com/$SOLUTION_NAME/$VERSION/emr-stream-demo.template\n"
```

### CDK 배포

#### 사전 요구 사항
다음 도구를 설치하세요:
1. [Python 3.6 이상](https://www.python.org/downloads/)
2. [Node.js 10.3.0 이상](https://nodejs.org/en/)
3. [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-macos.html#install-macosos-bundled). `aws configure`로 CLI를 구성하세요.
4. [CDK toolkit](https://cdkworkshop.com/15-prerequisites/500-toolkit.html)
5. 첫 번째 배포를 위한 [일회성 CDK 부트스트랩](https://cdkworkshop.com/20-typescript/20-create-project/500-deploy.html)

#### 배포
```bash
python3 -m venv .env
source .env/bin/activate
pip install -r requirements.txt

cdk deploy
```

## 배포 후

다음 `post-deployment.sh`는 Linux에서 실행 가능하며 Mac OSX에서는 실행할 수 없습니다. 필요한 경우 스크립트를 수정하세요.

1. Cloud9 콘솔에서 "Kafka Client" IDE를 엽니다. Cloud9 IDE가 존재하지 않으면 생성하세요.
```
VPC prefix: 'emr-stream-demo'
Instance Type: 't3.small'
```
2. [`Cloud9Admin`이 포함된 IAM role을 IDE에 연결](https://catalog.us-east-1.prod.workshops.aws/workshops/d90c2f2d-a84b-4e80-b4f9-f5cee0614426/en-US/30-emr-serverless/31-set-up-env#setup-cloud9-ide)합니다.

3. Cloud9에서 AWS 관리형 임시 자격 증명을 끕니다:
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install --update
/usr/local/bin/aws cloud9 update-environment  --environment-id $C9_PID --managed-credentials-action DISABLE
rm -vf ${HOME}/.aws/credentials
```

4. cloud9 IDE 환경을 구성하기 위해 스크립트를 실행합니다:
```bash
curl https://raw.githubusercontent.com/aws-samples/stream-emr-on-eks/main/deployment/app_code/post-deployment.sh | bash
```
5. 5분 정도 기다린 후 [MSK 클러스터](https://console.aws.amazon.com/msk/) 상태를 확인합니다. 클러스터에 데이터를 보내기 전에 `active` 상태인지 확인하세요.
6. Cloud9에서 새 터미널 창을 열고 MSK에 샘플 데이터를 보냅니다:
```bash
wget https://github.com/xuite627/workshop_flink1015-1/raw/master/dataset/nycTaxiRides.gz
zcat nycTaxiRides.gz | split -l 10000 --filter="kafka_2.12-2.8.1/bin/kafka-console-producer.sh --broker-list ${MSK_SERVER} --topic taxirides ; sleep 0.2"  > /dev/null
```
6. 세 번째 터미널 창을 열고 소스 MSK 토픽을 모니터링합니다:
```bash
kafka_2.12-2.8.1/bin/kafka-console-consumer.sh \
--bootstrap-server ${MSK_SERVER} \
--topic taxirides \
--from-beginning
```

## MSK 통합
### 1. EMR on EKS로 작업 제출

- MSK에서 데이터 스트림을 소비하는 [샘플 작업](https://github.com/aws-samples/stream-emr-on-eks/blob/main/deployment/app_code/job/msk_consumer.py)
- 작업 제출:
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
### 작업 실행 확인:
```bash
# EKS에서 작업 파드 확인
kubectl get po -n emr

# EMR 콘솔에서 확인
# Cloud9에서 컨슈머 도구를 실행하여 대상 Kafka 토픽에서 데이터가 들어오는지 확인
kafka_2.12-2.8.1/bin/kafka-console-consumer.sh --bootstrap-server ${MSK_SERVER} --topic emreks_output --from-beginning
```
### 장기 실행 작업 취소 (작업 제출 출력 또는 EMR 콘솔에서 작업 ID를 가져올 수 있음)
```bash
aws emr-containers cancel-job-run --virtual-cluster-id $VIRTUAL_CLUSTER_ID  --id <YOUR_JOB_ID>
```

### 2. Fargate를 사용한 EMR on EKS
동일한 EKS 클러스터에서 [동일한 작업](https://github.com/aws-samples/stream-emr-on-eks/blob/main/deployment/app_code/job/msk_consumer.py)을 실행하지만 서버리스 옵션인 Fargate 컴퓨팅을 선택합니다.

EC2의 관리형 노드 그룹이 아닌 Fargate에서 선택되도록 하려면 이전에 Fargate 프로파일에 설정된 `serverless` 레이블로 Spark 작업에 태그를 지정합니다:
```yaml
--conf spark.kubernetes.driver.label.type=serverless
--conf spark.kubernetes.executor.label.type=serverless
```

Fargate로 작업 제출:

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
### EKS Fargate에서 작업 실행 확인
```bash
kubectl get po -n emr

# EMR 콘솔에서 확인
# Cloud9에서 컨슈머 도구를 실행하여 대상 Kafka 토픽에서 데이터가 들어오는지 확인
kafka_2.12-2.8.1/bin/kafka-console-consumer.sh \
--bootstrap-server ${MSK_SERVER} \
--topic emreksfg_output \
--from-beginning
```

### 3. (선택 사항) EMR on EC2로 step 제출

```bash
cluster_id=$(aws emr list-clusters --cluster-states WAITING --query 'Clusters[?Name==`emr-stream-demo`].Id' --output text)
MSK_SERVER=$(echo $MSK_SERVER | cut -d',' -f 2)

aws emr add-steps \
--cluster-id $cluster_id \
--steps Type=spark,Name=emrec2_stream,Args=[--deploy-mode,cluster,--conf,spark.cleaner.referenceTracking.cleanCheckpoints=true,--conf,spark.executor.instances=2,--conf,spark.executor.memory=2G,--conf,spark.driver.memory=2G,--conf,spark.executor.cores=2,--packages,org.apache.spark:spark-sql-kafka-0-10_2.12:3.0.1,s3://$S3BUCKET/app_code/job/msk_consumer.py,$MSK_SERVER,s3://$S3BUCKET/stream/checkpoint/emrec2,emrec2_output],ActionOnFailure=CONTINUE
```

### 확인
```bash
# EMR 콘솔에서 확인
# Cloud9에서 컨슈머 도구를 실행하여 대상 Kafka 토픽에서 데이터가 들어오는지 확인
kafka_2.12-2.8.1/bin/kafka-console-consumer.sh \
--bootstrap-server ${MSK_SERVER} \
--topic emrec2_output \
--from-beginning
```

## Kinesis 통합

### 1. (선택 사항) 커스텀 Docker 이미지 빌드
boto3를 통해 즉석에서 kinesis 테스트 스트림을 생성 및 삭제할 것이므로 Python 라이브러리를 포함하는 커스텀 EMR on EKS Docker 이미지가 필요합니다. boto3 및 kinesis-sql 커넥터가 필요하지 않은 경우 커스텀 Docker 이미지는 필수가 아닙니다.

EMR on EKS 6.5를 기반으로 이미지 빌드:
```bash
export AWS_REGION=$(aws configure list | grep region | awk '{print $2}')
export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
export ECR_URL=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 895885662937.dkr.ecr.us-west-2.amazonaws.com
docker build -t emr6.5_custom .

# 현재 계정에서 ECR 리포지토리 생성
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL
aws ecr create-repository --repository-name emr6.5_custom_boto3 --image-scanning-configuration scanOnPush=true --region $AWS_REGION

# ECR에 푸시
docker tag emr6.5_custom $ECR_URL/emr6.5_custom_boto3
docker push $ECR_URL/emr6.5_custom_boto3
```

### 2. kinesis-sql 커넥터 사용
이 데모는 `com.qubole.spark/spark-sql-kinesis_2.12/1.2.0-spark_3.0` 커넥터를 사용하여 Kinesis와 상호 작용합니다.

작업 수준 액세스 제어, 즉 [IRSA 기능](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)을 활성화하기 위해 [kinesis-sql git 리포지토리](https://github.com/aws-samples/kinesis-sql)를 포크하고 AWS java SDK를 업그레이드한 후 새 jar를 다시 컴파일했습니다. 위의 커스텀 Docker 빌드는 업그레이드된 커넥터를 자동으로 가져옵니다.

- Kinesis에서 데이터 스트림을 소비하는 [샘플 작업](https://github.com/aws-samples/stream-emr-on-eks/blob/main/deployment/app_code/job/qubole-kinesis.py)
- 작업 제출:
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

### 3. Spark의 DStream 사용

이 데모는 `spark-streaming-kinesis-asl_2.12` 라이브러리를 사용하여 Kinesis에서 읽습니다. [Spark 공식 문서](https://spark.apache.org/docs/latest/streaming-kinesis-integration.html)를 확인하세요. Spark 구문은 spark-sql-kinesis 접근 방식과 약간 다릅니다. RDD 수준에서 작동합니다.

- Kinesis에서 데이터 스트림을 소비하는 [샘플 작업](https://github.com/aws-samples/stream-emr-on-eks/blob/main/deployment/app_code/job/pyspark-kinesis.py)
- 작업 제출:
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

## 유용한 명령어

 * `kubectl get pod -n emr`               실행 중인 Spark 작업 나열
 * `kubectl delete pod --all -n emr`      모든 Spark 작업 삭제
 * `kubectl logs <pod name> -n emr`       emr 네임스페이스의 파드에 대한 로그 확인
 * `kubectl get node --label-columns=eks.amazonaws.com/capacityType,topology.kubernetes.io/zone` EKS 컴퓨팅 용량 유형 및 AZ 분포 확인


## 정리
정리 스크립트 실행:
```bash
curl https://raw.githubusercontent.com/aws-samples/stream-emr-on-eks/main/deployment/app_code/delete_all.sh | bash
```
[CloudFormation 콘솔](https://console.aws.amazon.com/cloudformation/home?region=us-east-1)로 이동하여 필요한 경우 나머지 리소스를 수동으로 삭제합니다.
