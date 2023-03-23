#!/bin/bash
set -o errexit
set -o pipefail

read -p "Enter EMR Virtual Cluster AWS Region: " AWS_REGION
read -p "Enter the EMR Virtual Cluster ID: " EMR_VIRTUAL_CLUSTER_ID
read -p "Enter the EMR Execution Role ARN: " EMR_EXECUTION_ROLE_ARN
read -p "Enter the CloudWatch Log Group name: " CLOUDWATCH_LOG_GROUP
read -p "Enter the CloudWatch Log Group name(e.g., s3://my-bucket-name ): " S3_BUCKET_LOGS

aws emr-containers start-job-run \
   --virtual-cluster-id $EMR_VIRTUAL_CLUSTER_ID \
   --name=pi \
   --region $AWS_REGION \
   --execution-role-arn $EMR_EXECUTION_ROLE_ARN \
   --release-label emr-6.8.0-latest \
   --job-driver '{
       "sparkSubmitJobDriver":{
               "entryPoint": "local:///usr/lib/spark/examples/src/main/python/pi.py",
               "sparkSubmitParameters": "--conf spark.executor.instances=2 --conf spark.executor.memory=2G --conf spark.executor.cores=1 --conf spark.driver.cores=1"
       }
   }' \
   --configuration-overrides '{
        "applicationConfiguration": [
          {
            "classification": "spark-defaults",
            "properties": {
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
           "persistentAppUI": "ENABLED",
           "cloudWatchMonitoringConfiguration": {
               "logGroupName": "'"${CLOUDWATCH_LOG_GROUP}"'",
               "logStreamNamePrefix": "sample-pi"
           },
           "s3MonitoringConfiguration": {
               "logUri": "'"${S3_BUCKET_LOGS}/"'"
           }
       }
   }'
