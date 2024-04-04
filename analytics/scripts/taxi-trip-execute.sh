#!/bin/bash
# This job copies Sample PySpark script and some test data to your S3 bucket which will enable you to run the following Spark Operator script

# Prerequisites for running this shell script
#     1/ Execute the shell script with the required arguments
#         ./your_script.sh <S3_BUCKET> <REGION>
#     2/ Ensure <S3_BUCKET> is replaced in "nvme-ephemeral-storage.yaml" file
#     3/ Execute the shell script which creates the input data in your S3 bucket
#     4/ Run `kubectl apply -f nvme-ephemeral-storage.yaml` to trigger the Spark job
#     5/ Monitor the Spark job using "kubectl get pods -n spark-team-a -w"

# Script usage ./taxi-trip-execute my-s3-bucket us-west-2

if [ $# -ne 2 ]; then
  echo "Usage: $0 <S3_BUCKET> <REGION>"
  exit 1
fi

S3_BUCKET="$1"
REGION="$2"

INPUT_DATA_S3_PATH="s3://${S3_BUCKET}/taxi-trip/input/"

# Create a local input folder
mkdir input

# Copy PySpark Script to S3 bucket
aws s3 cp pyspark-taxi-trip.py s3://${S3_BUCKET}/taxi-trip/scripts/ --region ${REGION}

# Copy Test Input data to S3 bucket
wget https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-01.parquet -O "input/yellow_tripdata_2022-0.parquet"
aws s3 cp "input/yellow_tripdata_2022-0.parquet" s3://${S3_BUCKET}/input/yellow_tripdata_2022-0.parquet

pids=()

# Making duplicate copies to increase the size of the data.
max=100
for (( i=1; i <= $max; ++i ))
do
  aws s3 cp s3://${S3_BUCKET}/input/yellow_tripdata_2022-0.parquet s3://${S3_BUCKET}/input/yellow_tripdata_2022-${i}.parquet &
  pids+=($!)
done

for pid in "${pids[@]}"; do
    wait $pid
done

# Delete a local input folder
rm -rf input