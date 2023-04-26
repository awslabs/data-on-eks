#!/bin/bash

read -p "Enter EMR Virtual Cluster AWS Region: " AWS_REGION
read -p "Enter the EMR Virtual Cluster ID: " EMR_VIRTUAL_CLUSTER_ID
read -p "Enter the EMR Execution Role ARN: " EMR_EXECUTION_ROLE_ARN
read -p "Enter the CloudWatch Log Group name: " CLOUDWATCH_LOG_GROUP
read -p "Enter the S3 Bucket for storing PySpark Scripts, Pod Templates and Input data. For e.g., s3://<bucket-name>: " S3_BUCKET

#--------------------------------------------
# DEFAULT VARIABLES CAN BE MODIFIED
#--------------------------------------------
JOB_NAME='DELTA_TABLE_LOAD'
EMR_EKS_RELEASE_LABEL="emr-6.9.0-latest" # Spark 3.2.1

SPARK_JOB_S3_PATH="${S3_BUCKET}/${EMR_VIRTUAL_CLUSTER_ID}/${JOB_NAME}"
SCRIPTS_S3_PATH="${SPARK_JOB_S3_PATH}/scripts"
INPUT_DATA_S3_PATH="${SPARK_JOB_S3_PATH}/data"



#--------------------------------------------
# Execute Spark job
#--------------------------------------------

aws emr-containers start-job-run \
  --region $AWS_REGION \
  --virtual-cluster-id $EMR_VIRTUAL_CLUSTER_ID \
  --name job-deltalake \
  --execution-role-arn $EMR_EXECUTION_ROLE_ARN \
  --release-label emr-6.9.0-latest \
  --job-driver '{
  "sparkSubmitJobDriver": {
      "entryPoint": "'$SCRIPTS_S3_PATH'/delta-merge.py",
      "entryPointArguments":["'$SPARK_JOB_S3_PATH'"],
      "sparkSubmitParameters": "--conf spark.executor.memory=2G --conf spark.executor.cores=2"}}' \
  --configuration-overrides '{
    "applicationConfiguration": [
      {
        "classification": "spark-defaults",
        "properties": {
          "spark.sql.extensions": "io.delta.sql.DeltaSparkSessionExtension",
          "spark.sql.catalog.spark_catalog":"org.apache.spark.sql.delta.catalog.DeltaCatalog",
          "spark.jars.packages": "io.delta:delta-core_2.12:2.1.0",
          "spark.serializer":"org.apache.spark.serializer.KryoSerializer",
          "spark.hadoop.hive.metastore.client.factory.class":"com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory",
          "spark.jars": "https://repo1.maven.org/maven2/io/delta/delta-core_2.12/2.1.0/delta-core_2.12-2.1.0.jar,https://repo1.maven.org/maven2/io/delta/delta-storage/2.1.0/delta-storage-2.1.0.jar"
      }}
    ],
    "monitoringConfiguration": {
      "s3MonitoringConfiguration": {"logUri": "s3://'$CLOUDWATCH_LOG_GROUP'/elasticmapreduce/emr-containers"}}}'
