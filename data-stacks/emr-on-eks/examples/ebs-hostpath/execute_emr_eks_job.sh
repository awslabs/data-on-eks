#!/bin/bash
set -e

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Get Terraform outputs
echo "Reading Terraform outputs..."
cd "$STACK_DIR/terraform/_local"

EMR_VIRTUAL_CLUSTER_ID=$(terraform output -json emr_on_eks | jq -r '."emr-data-team-a".virtual_cluster_id')
EMR_EXECUTION_ROLE_ARN=$(terraform output -json emr_on_eks | jq -r '."emr-data-team-a".job_execution_role_arn')
CLOUDWATCH_LOG_GROUP=$(terraform output -json emr_on_eks | jq -r '."emr-data-team-a".cloudwatch_log_group_name')
S3_BUCKET="s3://$(terraform output -raw emr_s3_bucket_name)"
AWS_REGION=$(terraform output -raw region)

cd "$SCRIPT_DIR"

#--------------------------------------------
# Job Configuration
#--------------------------------------------
JOB_NAME='taxidata-ebs-hostpath'
EMR_EKS_RELEASE_LABEL="emr-7.12.0-latest"

SPARK_JOB_S3_PATH="${S3_BUCKET}/${EMR_VIRTUAL_CLUSTER_ID}/${JOB_NAME}"
SCRIPTS_S3_PATH="${SPARK_JOB_S3_PATH}/scripts"
INPUT_DATA_S3_PATH="${SPARK_JOB_S3_PATH}/input"
OUTPUT_DATA_S3_PATH="${SPARK_JOB_S3_PATH}/output"

echo "Configuration:"
echo "  EMR_VIRTUAL_CLUSTER_ID: $EMR_VIRTUAL_CLUSTER_ID"
echo "  EMR_EXECUTION_ROLE_ARN: $EMR_EXECUTION_ROLE_ARN"
echo "  S3_BUCKET: $S3_BUCKET"
echo "  AWS_REGION: $AWS_REGION"

#--------------------------------------------
# Copy PySpark Scripts and Pod Templates to S3
#--------------------------------------------
echo "Copying scripts and pod templates to S3..."
aws s3 sync "$SCRIPT_DIR/" ${SCRIPTS_S3_PATH} --exclude "*.sh"

#--------------------------------------------
# Download and prepare test data
# Source: https://registry.opendata.aws/nyc-tlc-trip-records-pds/
#--------------------------------------------
echo "Downloading test data..."
mkdir -p "$SCRIPT_DIR/input"

# Download NYC taxi data
wget -q https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-01.parquet -O "$SCRIPT_DIR/input/yellow_tripdata_2022-0.parquet"

# Create copies to increase data size for testing
for i in $(seq 1 10); do
  cp "$SCRIPT_DIR/input/yellow_tripdata_2022-0.parquet" "$SCRIPT_DIR/input/yellow_tripdata_2022-${i}.parquet"
done

aws s3 sync "$SCRIPT_DIR/input" ${INPUT_DATA_S3_PATH}
rm -rf "$SCRIPT_DIR/input"

#--------------------------------------------
# Execute Spark job
#--------------------------------------------
echo "Submitting EMR on EKS job..."
aws emr-containers start-job-run \
  --virtual-cluster-id $EMR_VIRTUAL_CLUSTER_ID \
  --name $JOB_NAME \
  --region $AWS_REGION \
  --execution-role-arn $EMR_EXECUTION_ROLE_ARN \
  --release-label $EMR_EKS_RELEASE_LABEL \
  --job-driver '{
    "sparkSubmitJobDriver": {
      "entryPoint": "'"$SCRIPTS_S3_PATH"'/pyspark-taxi-trip.py",
      "entryPointArguments": ["'"$INPUT_DATA_S3_PATH"'", "'"$OUTPUT_DATA_S3_PATH"'"]
    }
  }' \
  --configuration-overrides '{
    "applicationConfiguration": [
      {
        "classification": "spark-defaults",
        "properties": {
          "spark.driver.cores": "2",
          "spark.executor.cores": "4",
          "spark.driver.memory": "8g",
          "spark.executor.memory": "16g",
          "spark.kubernetes.driver.podTemplateFile": "'"$SCRIPTS_S3_PATH"'/driver-pod-template.yaml",
          "spark.kubernetes.executor.podTemplateFile": "'"$SCRIPTS_S3_PATH"'/executor-pod-template.yaml",
          "spark.local.dir": "/data1",

          "spark.dynamicAllocation.enabled": "true",
          "spark.dynamicAllocation.shuffleTracking.enabled": "true",
          "spark.dynamicAllocation.minExecutors": "2",
          "spark.dynamicAllocation.maxExecutors": "10",
          "spark.dynamicAllocation.initialExecutors": "2",

          "spark.sql.adaptive.enabled": "true",
          "spark.sql.adaptive.coalescePartitions.enabled": "true",
          "spark.sql.adaptive.skewJoin.enabled": "true",

          "spark.kubernetes.submission.connectionTimeout": "60000000",
          "spark.kubernetes.submission.requestTimeout": "60000000",
          "spark.kubernetes.driver.connectionTimeout": "60000000",
          "spark.kubernetes.driver.requestTimeout": "60000000",
          "spark.kubernetes.executor.podNamePrefix": "'"$JOB_NAME"'",
          "spark.ui.prometheus.enabled": "true",
          "spark.executor.processTreeMetrics.enabled": "true",
          "spark.kubernetes.driver.annotation.prometheus.io/scrape": "true",
          "spark.kubernetes.driver.annotation.prometheus.io/path": "/metrics/executors/prometheus/",
          "spark.kubernetes.driver.annotation.prometheus.io/port": "4040"
        }
      }
    ],
    "monitoringConfiguration": {
      "persistentAppUI": "ENABLED",
      "cloudWatchMonitoringConfiguration": {
        "logGroupName": "'"$CLOUDWATCH_LOG_GROUP"'",
        "logStreamNamePrefix": "'"$JOB_NAME"'"
      },
      "s3MonitoringConfiguration": {
        "logUri": "'"${S3_BUCKET}/logs/"'"
      }
    }
  }'

echo "Job submitted successfully!"
echo "Monitor the job in the EMR console or use: aws emr-containers list-job-runs --virtual-cluster-id $EMR_VIRTUAL_CLUSTER_ID --region $AWS_REGION"
