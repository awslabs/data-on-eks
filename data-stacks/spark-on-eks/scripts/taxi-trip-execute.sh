#!/bin/bash
# Copies the sample PySpark script and test data to your S3 bucket for the Spark Operator examples.
# Usage: ./taxi-trip-execute.sh <S3_BUCKET> <REGION>
# Then replace $S3_BUCKET in the example file and run `kubectl apply -f <example>.yaml`.

if [ $# -ne 2 ]; then
  echo "Usage: $0 <S3_BUCKET> <REGION>"
  exit 1
fi

S3_BUCKET="$1"
REGION="$2"

INPUT_DATA_S3_PATH="s3://${S3_BUCKET}/taxi-trip/input"

mkdir input

aws s3 cp pyspark-taxi-trip.py s3://${S3_BUCKET}/taxi-trip/scripts/ --region ${REGION}

wget https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-01.parquet -O "input/yellow_tripdata_2022-0.parquet"
aws s3 cp "input/yellow_tripdata_2022-0.parquet" ${INPUT_DATA_S3_PATH}/yellow_tripdata_2022-0.parquet

pids=()

# Duplicate copies make the input data larger.
max=25
for (( i=1; i <= $max; ++i ))
do
  aws s3 cp ${INPUT_DATA_S3_PATH}/yellow_tripdata_2022-0.parquet ${INPUT_DATA_S3_PATH}/yellow_tripdata_2022-${i}.parquet &
  pids+=($!)
done

for pid in "${pids[@]}"; do
    wait $pid
done

rm -rf input
