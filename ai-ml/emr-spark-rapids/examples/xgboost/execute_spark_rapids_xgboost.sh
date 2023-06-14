#!/bin/bash
#--------------------------------------------
# NOTE: COPY INPUT DATA TO S3 TO RUN THIS JOB
#--------------------------------------------
# Follow these instructions -> https://github.com/NVIDIA/spark-rapids-examples/blob/branch-23.04/docs/get-started/xgboost-examples/dataset/mortgage.md
#       to download and copy the input data to your s3 bucket under the below mentioned path
#       ${S3_BUCKET}/${EMR_VIRTUAL_CLUSTER_ID}/${JOB_NAME}/input/fannie-mae-single-family-loan-performance/
#--------------------------------------------

read -p "Enter EMR Virtual Cluster AWS Region: " AWS_REGION
read -p "Enter the EMR Virtual Cluster ID: " EMR_VIRTUAL_CLUSTER_ID
read -p "Enter the EMR Execution Role ARN: " EMR_EXECUTION_ROLE_ARN
read -p "Enter the customized Docker image URI: " XGBOOST_IMAGE
read -p "Enter the CloudWatch Log Group name: " CLOUDWATCH_LOG_GROUP
read -p "Enter the S3 Bucket (Just the Bucket Name) for storing PySpark Scripts, Pod Templates, Input data and Output data. For e.g., <bucket-name>: " S3_BUCKET

#--------------------------------------------
# DEFAULT VARIABLES CAN BE MODIFIED
#--------------------------------------------
JOB_NAME='spark-rapids-emr'
EMR_EKS_RELEASE_LABEL="emr-6.10.0-spark-rapids-latest"
#XGBOOST_IMAGE="public.ecr.aws/o7d8v7g9/emr-6.10.0-spark-rapids:0.11"

S3_BUCKET="s3://${S3_BUCKET}"

SPARK_JOB_S3_PATH="${S3_BUCKET}/${EMR_VIRTUAL_CLUSTER_ID}/${JOB_NAME}"
SCRIPTS_S3_PATH="${SPARK_JOB_S3_PATH}/scripts"

INPUT_DATA_S3_PATH="${SPARK_JOB_S3_PATH}/input"
OUTPUT_DATA_S3_PATH="${SPARK_JOB_S3_PATH}/output"
JARS_PATH="${SCRIPTS_S3_PATH}/jars"

# Download required jars locally
mkdir jars
curl -o ./jars/xgboost4j-spark_3.0-1.4.2-0.3.0.jar https://repo1.maven.org/maven2/com/nvidia/xgboost4j-spark_3.0/1.4.2-0.3.0/xgboost4j-spark_3.0-1.4.2-0.3.0.jar
curl -o ./jars/xgboost4j_3.0-1.4.2-0.3.0.jar https://mvnrepository.com/artifact/com.nvidia/xgboost4j_3.0/1.4.2-0.3.0/xgboost4j_3.0-1.4.2-0.3.0.jar


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
      "entryPointArguments": ["'"$INPUT_DATA_S3_PATH"'","'"$OUTPUT_DATA_S3_PATH"'"],
      "sparkSubmitParameters": "--conf spark.kubernetes.container.image='"$XGBOOST_IMAGE"' --jars='"$JARS_PATH"'/xgboost4j-spark_3.0-1.4.2-0.3.0.jar,'"$JARS_PATH"'/xgboost4j_3.0-1.4.2-0.3.0.jar --conf spark.pyspark.python=/opt/venv/bin/python"
    }
  }' \
  --configuration-overrides '{
    "applicationConfiguration": [
        {
          "classification": "spark-defaults",
          "properties": {
            "spark.plugins":"com.nvidia.spark.SQLPlugin",
            "spark.shuffle.manager":"com.nvidia.spark.rapids.spark331.RapidsShuffleManager",
            "spark.kubernetes.driver.podTemplateFile":"'"$SCRIPTS_S3_PATH"'/driver-pod-template.yaml",
            "spark.kubernetes.executor.podTemplateFile":"'"$SCRIPTS_S3_PATH"'/executor-pod-template.yaml",
            "spark.kubernetes.executor.podNamePrefix":"'"$JOB_NAME"'",
            "spark.driver.cores":"2",
            "spark.driver.memory":"8G",
            "spark.driver.maxResultSize":"2gb",
            "spark.executor.instances":"8",
            "spark.executor.cores":"5",
            "spark.executor.memory":"26G",
            "spark.executor.memoryOverhead":"2G",
            "spark.executor.extraLibraryPath":"/usr/local/cuda/lib:/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64:/usr/local/cuda/targets/x86_64-linux/lib:/usr/lib/hadoop/lib/native:/usr/lib/hadooplzo/lib/native:/docker/usr/lib/hadoop/lib/native:/docker/usr/lib/hadoop-lzo/lib/native",
            "spark.executor.resource.gpu.vendor":"nvidia.com",
            "spark.executor.resource.gpu.amount":"1",
            "spark.task.cpus":"1",
            "spark.task.resource.gpu.amount":"1",
            "spark.rapids.sql.enabled":"true",
            "spark.rapids.sql.concurrentGpuTasks":"1",
            "spark.rapids.sql.explain":"ALL",
            "spark.rapids.sql.batchSizeBytes":"1gb",
            "spark.rapids.sql.incompatibleOps.enabled":"true",
            "spark.rapids.memory.pinnedPool.size":"1G",
            "spark.rapids.memory.gpu.pool":"ASYNC",
            "spark.rapids.memory.gpu.allocFraction":"0.6",
            "spark.rapids.shuffle.mode":"MULTITHREADED",
            "spark.sql.sources.useV1SourceList":"parquet",
            "spark.sql.files.maxPartitionBytes":"2gb",
            "spark.sql.adaptive.enabled":"true",
            "spark.locality.wait":"0s",
            "spark.dynamicAllocation.enabled":"false",
            "spark.local.dir":"/data1"
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


# Delete local JARS directory
rm -rf ./jars
