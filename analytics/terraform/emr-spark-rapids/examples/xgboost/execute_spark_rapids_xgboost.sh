#!/bin/bash
#--------------------------------------------
# NOTE: Download fannie-mae-single-family-loan-performance dataset and copy to S3 bucket under the below mentioned path
#       ${S3_BUCKET}/${EMR_VIRTUAL_CLUSTER_ID}/${JOB_NAME}/input/fannie-mae-single-family-loan-performance/
#       Follow these instructions to download the input data -> https://github.com/NVIDIA/spark-rapids-examples/blob/branch-23.04/docs/get-started/xgboost-examples/dataset/mortgage.md
#--------------------------------------------
#--------------------------------------------
# DEFAULT VARIABLES CAN BE MODIFIED
#--------------------------------------------
JOB_NAME='spark-rapids-emr'
EMR_EKS_RELEASE_LABEL="emr-7.0.0-spark-rapids-latest"
AWS_REGION="${AWS_REGION:-us-west-2}"  # Example default region
XGBOOST_IMAGE="${XGBOOST_IMAGE:-public.ecr.aws/data-on-eks/emr-7.0.0-spark-rapids-xgboost-custom:latest}"
NUM_WORKERS="${NUM_WORKERS:-8}"  # Example default number of executors

read -p "Did you copy the Fannie Mae Loan Performance data to S3 bucket (y/n): "
if [[ $REPLY != "y" ]]; then
  echo "Please copy the input data set to S3 before proceeding."
  exit 1
fi

if [[ -z "$XGBOOST_IMAGE" ]]; then
  read -p "Enter the customized Docker image URI (leave blank for default): " XGBOOST_IMAGE
fi

if [[ -z "$AWS_REGION" ]]; then
  read -p "Enter EMR Virtual Cluster AWS Region (leave blank for default): " AWS_REGION
fi

if [[ -z "$NUM_WORKERS" ]]; then
  read -p "Enter number of Spark executors (leave blank for default): " NUM_WORKERS
fi

read -p "Enter the EMR Virtual Cluster ID: (Check Terraform output values): " EMR_VIRTUAL_CLUSTER_ID
read -p "Enter the EMR Execution Role ARN: (Check Terraform output values) " EMR_EXECUTION_ROLE_ARN
read -p "Enter the CloudWatch Log Group name: (Check Terraform output values) " CLOUDWATCH_LOG_GROUP
read -p "Enter the S3 Bucket for storing PySpark Scripts, Pod Templates, Input data and Output data. e.g., test-bucket-123 : " S3_BUCKET

S3_BUCKET="s3://${S3_BUCKET}"

SPARK_JOB_S3_PATH="${S3_BUCKET}/${EMR_VIRTUAL_CLUSTER_ID}/${JOB_NAME}"
SCRIPTS_S3_PATH="${SPARK_JOB_S3_PATH}/scripts"

INPUT_DATA_S3_PATH="${SPARK_JOB_S3_PATH}/input"
OUTPUT_DATA_S3_PATH="${SPARK_JOB_S3_PATH}/output"
JARS_PATH="${SCRIPTS_S3_PATH}/jars"

#--------------------------------------------
# Copy PySpark Scripts, Pod Templates and Input data to S3 bucket
#--------------------------------------------
aws s3 sync "./" ${SCRIPTS_S3_PATH}

#--------------------------------------------
# Execute Spark job
#--------------------------------------------
aws emr-containers start-job-run \
  --virtual-cluster-id $EMR_VIRTUAL_CLUSTER_ID \
  --name $JOB_NAME \
  --region $AWS_REGION \
  --execution-role-arn $EMR_EXECUTION_ROLE_ARN \
  --release-label $EMR_EKS_RELEASE_LABEL \
  --job-driver '{
    "sparkSubmitJobDriver": {
      "entryPoint": "'"$SCRIPTS_S3_PATH"'/etl-xgboost-train-transform.py",
      "entryPointArguments": ["'"$INPUT_DATA_S3_PATH"'","'"$OUTPUT_DATA_S3_PATH"'","'"$NUM_WORKERS"'"],
      "sparkSubmitParameters": "--conf spark.kubernetes.container.image='"$XGBOOST_IMAGE"' --jars=local:///usr/lib/xgboost/spark-rapids-xgboost-jar-1.0.0.jar"
    }
  }' \
  --configuration-overrides '{
    "applicationConfiguration": [
        {
          "classification": "spark-defaults",
          "properties": {
            "spark.kubernetes.file.upload.path": "'"$SCRIPTS_S3_PATH"'/path/",
            "spark.plugins":"com.nvidia.spark.SQLPlugin",
            "spark.shuffle.manager":"com.nvidia.spark.rapids.spark350.RapidsShuffleManager",
            "spark.kubernetes.driver.podTemplateFile":"'"$SCRIPTS_S3_PATH"'/driver-pod-template.yaml",
            "spark.kubernetes.executor.podTemplateFile":"'"$SCRIPTS_S3_PATH"'/executor-pod-template.yaml",
            "spark.kubernetes.executor.podNamePrefix":"'"$JOB_NAME"'",

            "spark.driver.cores":"2",
            "spark.driver.memory":"8G",
            "spark.driver.maxResultSize":"2gb",

            "spark.executor.instances":"'"$NUM_WORKERS"'",
            "spark.executor.cores":"5",
            "spark.executor.memory":"26G",
            "spark.executor.memoryOverhead":"2G",
            "spark.executor.extraLibraryPath":"/usr/local/cuda/lib:/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64:/usr/local/cuda/targets/x86_64-linux/lib:/usr/lib/hadoop/lib/native:/usr/lib/hadooplzo/lib/native:/docker/usr/lib/hadoop/lib/native:/docker/usr/lib/hadoop-lzo/lib/native",
            "spark.executor.resource.gpu.vendor":"nvidia.com",
            "spark.executor.resource.gpu.amount":"1",

            "spark.task.cpus":"1",
            "spark.task.resource.gpu.amount":"1",

            "spark.rapids.sql.enabled":"true",
            "spark.rapids.sql.concurrentGpuTasks":"2",
            "spark.rapids.sql.explain":"ALL",
            "spark.rapids.sql.incompatibleOps.enabled":"true",

            "spark.rapids.memory.pinnedPool.size":"2G",
            "spark.rapids.memory.gpu.pool":"ASYNC",
            "spark.rapids.memory.gpu.allocFraction":"0.6",
            "spark.rapids.shuffle.mode":"MULTITHREADED",

            "spark.sql.sources.useV1SourceList":"parquet",
            "spark.sql.files.maxPartitionBytes":"512MB",
            "spark.sql.adaptive.enabled":"true",
            "spark.sql.execution.arrow.maxRecordsPerBatch":"200000",
            "spark.locality.wait":"0s",
            "spark.sql.shuffle.partitions":"64",
            "spark.dynamicAllocation.enabled":"false"
          }
        }
      ],
    "monitoringConfiguration": {
      "persistentAppUI":"ENABLED",
      "cloudWatchMonitoringConfiguration": {
        "logGroupName":"'"$CLOUDWATCH_LOG_GROUP"'",
        "logStreamNamePrefix":"'"$JOB_NAME"'"
      },
      "s3MonitoringConfiguration": {
        "logUri": "'"$S3_BUCKET"'/logs/spark/"
      }
    }
  }'
