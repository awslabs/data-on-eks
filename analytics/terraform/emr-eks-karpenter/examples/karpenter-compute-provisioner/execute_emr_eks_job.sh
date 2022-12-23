#!/bin/bash

if [ $# -ne 3 ];
then
  echo "$0: Missing arguments EMR_VIRTUAL_CLUSTER_NAME, S3_BUCKET_NAME and EMR_JOB_EXECUTION_ROLE_ARN"
  echo "USAGE: ./execute_emr_eks_job.sh '<EMR_VIRTUAL_CLUSTER_NAME>' '<s3://ENTER_BUCKET_NAME>' '<EMR_JOB_EXECUTION_ROLE_ARN>'"
  exit 1
else
  echo "We got some argument(s)"
  echo "==========================="
  echo "Number of arguments.: $#"
  echo "List of arguments...: $@"
  echo "Arg #1..............: $1"
  echo "Arg #2..............: $2"
  echo "Arg #3..............: $3"
  echo "==========================="
fi

#--------------------------------------------
# INPUT VARIABLES
#--------------------------------------------
EMR_VIRTUAL_CLUSTER_NAME=$1     # Terraform output variable is `emrcontainers_virtual_cluster_id`
S3_BUCKET=$2                    # This script requires s3 bucket as input parameter e.g., s3://<bucket-name>
EMR_JOB_EXECUTION_ROLE_ARN=$3   # Terraform output variable is emr_on_eks_role_arn

#--------------------------------------------
# DERIVED VARIABLES
#--------------------------------------------
EMR_VIRTUAL_CLUSTER_ID=$(aws emr-containers list-virtual-clusters --query "virtualClusters[?name == '$EMR_VIRTUAL_CLUSTER_NAME' && state == 'RUNNING'].id" --output text)

#--------------------------------------------
# DEFAULT VARIABLES CAN BE MODIFIED
#--------------------------------------------
JOB_NAME='taxidata'
EMR_EKS_RELEASE_LABEL="emr-6.7.0-latest" # Spark 3.2.1
CW_LOG_GROUP="/emr-on-eks-logs/${EMR_VIRTUAL_CLUSTER_NAME}" # Create CW Log group if not exist

SPARK_JOB_S3_PATH="${S3_BUCKET}/${EMR_VIRTUAL_CLUSTER_NAME}/${JOB_NAME}"
SCRIPTS_S3_PATH="${SPARK_JOB_S3_PATH}/scripts"
INPUT_DATA_S3_PATH="${SPARK_JOB_S3_PATH}/input"
OUTPUT_DATA_S3_PATH="${SPARK_JOB_S3_PATH}/output"

#--------------------------------------------
# Copy PySpark Scripts, Pod Templates and Input data to S3 bucket
#--------------------------------------------
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

if [[ $EMR_VIRTUAL_CLUSTER_ID != "" ]]; then
  echo "Found Cluster $EMR_VIRTUAL_CLUSTER_NAME; Executing the Spark job now..."
  aws emr-containers start-job-run \
    --virtual-cluster-id $EMR_VIRTUAL_CLUSTER_ID \
    --name $JOB_NAME \
    --execution-role-arn $EMR_JOB_EXECUTION_ROLE_ARN \
    --release-label $EMR_EKS_RELEASE_LABEL \
    --job-driver '{
      "sparkSubmitJobDriver": {
        "entryPoint": "'"$SCRIPTS_S3_PATH"'/pyspark-taxi-trip.py",
        "entryPointArguments": ["'"$INPUT_DATA_S3_PATH"'",
          "'"$OUTPUT_DATA_S3_PATH"'"
        ],
        "sparkSubmitParameters": "--conf spark.executor.instances=6"
      }
   }' \
    --configuration-overrides '{
      "applicationConfiguration": [
          {
            "classification": "spark-defaults",
            "properties": {
              "spark.driver.cores":"1",
              "spark.executor.cores":"1",
              "spark.driver.memory": "10g",
              "spark.executor.memory": "10g",
              "spark.kubernetes.driver.podTemplateFile":"'"$SCRIPTS_S3_PATH"'/driver-pod-template.yaml",
              "spark.kubernetes.executor.podTemplateFile":"'"$SCRIPTS_S3_PATH"'/executor-pod-template.yaml",
              "spark.local.dir" : "/data1,/data2",

              "spark.kubernetes.executor.podNamePrefix":"'"$JOB_NAME"'",
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
          "logGroupName":"'"$CW_LOG_GROUP"'",
          "logStreamNamePrefix":"'"$JOB_NAME"'"
        }
      }
    }'
else
  echo "Cluster is not in running state $EMR_VIRTUAL_CLUSTER_NAME"
fi
