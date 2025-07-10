#!/bin/bash

# read -p "Enter EMR Virtual Cluster AWS Region: " AWS_REGION
# read -p "Enter the EMR Virtual Cluster ID: " EMR_VIRTUAL_CLUSTER_ID
# read -p "Enter the EMR Execution Role ARN: " EMR_EXECUTION_ROLE_ARN
# read -p "Enter the CloudWatch Log Group name: " CLOUDWATCH_LOG_GROUP
# read -p "Enter the S3 Bucket for storing PySpark Scripts, Pod Templates and Input data. For e.g., s3://<bucket-name>: " S3_BUCKET

cp ../../../terraform.tfstate .
EMR_VIRTUAL_CLUSTER_ID=$(terraform output -json emr_on_eks | jq -r '."data-team-a".virtual_cluster_id')
EMR_EXECUTION_ROLE_ARN=$(terraform output -json emr_on_eks | jq -r '."data-team-a".job_execution_role_arn')
CLOUDWATCH_LOG_GROUP=$(terraform output -json emr_on_eks | jq -r '."data-team-a".cloudwatch_log_group_name')
S3_BUCKET="s3://$(terraform output -json emr_s3_bucket_name | tr -d '"')"
AWS_REGION=$(terraform output -json aws_region | tr -d '"')

rm terraform.tfstate

#--------------------------------------------
# DEFAULT VARIABLES CAN BE MODIFIED
#--------------------------------------------
JOB_NAME='taxidata'
EMR_EKS_RELEASE_LABEL="emr-7.9.0-latest" # Spark 3.3.1

SPARK_JOB_S3_PATH="${S3_BUCKET}/${EMR_VIRTUAL_CLUSTER_ID}/${JOB_NAME}"
SCRIPTS_S3_PATH="${SPARK_JOB_S3_PATH}/scripts"
INPUT_DATA_S3_PATH="${SPARK_JOB_S3_PATH}/input"
OUTPUT_DATA_S3_PATH="${SPARK_JOB_S3_PATH}/output"

#--------------------------------------------
# Copy PySpark Scripts, Pod Templates and Input data to S3 bucket
#--------------------------------------------
echo ${SCRIPTS_S3_PATH}
aws s3 sync "./" ${SCRIPTS_S3_PATH}

#--------------------------------------------
# NOTE: This section downloads the test data from AWS Public Dataset. You can comment this section and bring your own input data required for sample PySpark test
# https://registry.opendata.aws/nyc-tlc-trip-records-pds/
#--------------------------------------------

mkdir -p "../input"
# Download the input data from public data set to local folders
wget https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-01.parquet -O "../input/yellow_tripdata_2022-0.parquet"

# Making duplicate copies to increase the size of the data.
max=20
for (( i=1; i <= $max; ++i ))
do
cp -rf "../input/yellow_tripdata_2022-0.parquet" "../input/yellow_tripdata_2022-${i}.parquet"
done

aws s3 sync "../input" ${INPUT_DATA_S3_PATH} # Sync from local folder to S3 path

rm -rf "../input" # delete local input folder

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
      "entryPoint": "'"$SCRIPTS_S3_PATH"'/pyspark-taxi-trip.py",
      "entryPointArguments": ["'"$INPUT_DATA_S3_PATH"'",
        "'"$OUTPUT_DATA_S3_PATH"'"
      ],
      "sparkSubmitParameters": "--conf spark.executor.instances=2"
    }
  }' \
  --configuration-overrides '{
    "applicationConfiguration": [
        {
          "classification": "spark-defaults",
          "properties": {
            "spark.driver.cores":"1",
            "spark.executor.cores":"1",
            "spark.driver.memory": "4g",
            "spark.executor.memory": "4g",
            "spark.kubernetes.driver.podTemplateFile":"'"$SCRIPTS_S3_PATH"'/driver-pod-template.yaml",
            "spark.kubernetes.executor.podTemplateFile":"'"$SCRIPTS_S3_PATH"'/executor-pod-template.yaml",
            "spark.local.dir":"/data1",
            "spark.kubernetes.submission.connectionTimeout": "60000000",
            "spark.kubernetes.submission.requestTimeout": "60000000",
            "spark.kubernetes.driver.connectionTimeout": "60000000",
            "spark.kubernetes.driver.requestTimeout": "60000000",
            "spark.kubernetes.executor.podNamePrefix":"'"$JOB_NAME"'",
            "spark.metrics.appStatusSource.enabled":"true",
            "spark.ui.prometheus.enabled":"true",
            "spark.executor.processTreeMetrics.enabled":"true",
            "spark.kubernetes.driver.annotation.prometheus.io/scrape":"true",
            "spark.kubernetes.driver.annotation.prometheus.io/path":"/metrics/executors/prometheus/",
            "spark.kubernetes.driver.annotation.prometheus.io/port":"4040",
            "spark.kubernetes.driver.service.annotation.prometheus.io/scrape":"true",
            "spark.kubernetes.driver.service.annotation.prometheus.io/path":"/metrics/driver/prometheus/",
            "spark.kubernetes.driver.service.annotation.prometheus.io/port":"4040",
            "spark.metrics.conf.*.sink.prometheusServlet.class":"org.apache.spark.metrics.sink.PrometheusServlet",
            "spark.metrics.conf.*.sink.prometheusServlet.path":"/metrics/driver/prometheus/",
            "spark.metrics.conf.master.sink.prometheusServlet.path":"/metrics/master/prometheus/",
            "spark.metrics.conf.applications.sink.prometheusServlet.path":"/metrics/applications/prometheus/"
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
        "logUri":"'"${S3_BUCKET}/logs/"'"
      }
    }
  }'
