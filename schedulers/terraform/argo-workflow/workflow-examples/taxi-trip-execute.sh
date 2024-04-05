#!/bin/bash
# This job copies Sample PySpark script and some test data to your S3 bucket which will enable you to run the following Spark Operator script

# Prerequisites for running this shell script
#     1/ Execute the shell script with the required arguments
#         ./your_script.sh <s3_bucket> <region>
#     2/ Ensure <s3_bcuket> is replaced in "workflow-examples/sensor-sqs-sparkjobs.yaml" file
#     3/ Execute the shell script which creates the input data in your S3 bucket
#     4/ Run `kubectl apply -f workflow-examples/sensor-sqs-sparkjobs.yaml` to schedule the Spark job
#     5/ Monitor the Spark job using "kubectl get pods -n spark-team-a -w"

# Script usage ./taxi-trip-execute my-s3-bucket us-west-2

if [ $# -ne 2 ]; then
  echo "Usage: $0 <s3_bucket> <region>"
  exit 1
fi

s3_bucket="$1"
region="$2"

INPUT_DATA_S3_PATH="s3://${s3_bucket}/taxi-trip/input/"

# Create a local input folder
mkdir input

# Copy PySpark Script to S3 bucket
aws s3 cp pyspark-taxi-trip.py s3://${s3_bucket}/taxi-trip/scripts/ --region ${region}

# Copy Test Input data to S3 bucket
wget https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-01.parquet -O "input/yellow_tripdata_2022-0.parquet"

# Making duplicate copies to increase the size of the data.
max=5
for (( i=1; i <= $max; ++i ))
do
   cp -rf "input/yellow_tripdata_2022-0.parquet" "input/yellow_tripdata_2022-${i}.parquet"
done

aws s3 sync "input/" ${INPUT_DATA_S3_PATH}

# Delete a local input folder
rm -rf input
