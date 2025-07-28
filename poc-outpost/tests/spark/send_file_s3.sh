#!/bin/bash
set -e

if [[ ! $1 =~ \.py$ ]]; then
  echo "Erreur : le premier paramètre doit être un fichier .py"
  exit 1
fi

if [[ ! $2 =~ \.yaml$ ]]; then
  echo "Erreur : le second paramètre doit être un fichier .yaml"
  exit 1
fi

#s3_bucket=$(aws s3 ls | awk '/airflow/ {print $3}')
#s3_bucket_log=$(aws s3 ls | awk '/spark-log/ {print $3}')
cd ../.. && bucket=$(terraform output -raw s3_bucket_id_spark_history_server)
cd -

unique_id=$(date +%s)

export BUCKET_LOG=$bucket

echo init pod file for $BUCKET_TEMPLATE

sparkPiFile="$(basename $2 .yaml)_rendered_${unique_id}.yaml"
sparkJobTemplate="$(basename $1 .py)_${unique_id}.py"

export SPARK_JOB_NAME=spark-job-launcher-${unique_id}
export SPARK_PI=$sparkPiFile
export SPARK_PI_NAME=$(echo "pyspark")${unique_id}

envsubst < $1 > $sparkJobTemplate
envsubst < $2 > $sparkPiFile

echo "Copying files to S3 bucket: $s3_bucket"
#aws s3 cp $sparkJobTemplate s3://$s3_bucket/dags/$sparkJobTemplate
../airflow/send_file_s3.sh $sparkJobTemplate
#aws s3 cp $sparkPiFile s3://$s3_bucket/dags/$sparkPiFile
../airflow/send_file_s3.sh $sparkPiFile

echo "file sent to S3 bucket outpost"
#aws s3 ls s3://$s3_bucket/dags/