#!/bin/bash

export AWS_REGION=$(terraform output --state="../terraform.tfstate" --raw configure_kubectl | awk '{ print $4 }')
export BUCKET=$(terraform output --state="../terraform.tfstate" --raw data_bucket)
export ACCOUNT_ID=$(aws sts get-caller-identity | jq -r .Account)
export GLUE_DB_NAME=taxi_hive_database
export CRAWLER_NAME=taxi-data-crawler
echo "The name of your bucket is: ${BUCKET}"

echo "Now copying sample data into the S3 bucket..."

## Copy sample data into the S3 bucket. Later on, we'd replace sample data with a more robust dataset.
aws s3 cp "s3://aws-data-analytics-workshops/shared_datasets/tripdata/" s3://$BUCKET/hive/ --recursive

sleep 2
echo "Now we create the Glue Database..."
# Create Glue Database
aws glue create-database --database-input Name=$GLUE_DB_NAME --region $AWS_REGION

sleep 2
echo "We will now create the role necessary to run a Glue crawler..."
aws iam create-role \
--role-name AWSGlueServiceRole-test-hive \
--assume-role-policy-document file://glue-role-trust.json \
--no-paginate
aws iam attach-role-policy \
--role-name AWSGlueServiceRole-test-hive \
--policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole \
--no-paginate
aws iam put-role-policy \
--role-name AWSGlueServiceRole-test-hive \
--policy-name glue-s3-policy \
--policy-document '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:::'$BUCKET'/*"
            ]
        }
    ]
}'

sleep 5
echo "Now we will create a crawler..."
# Run a crawler against the S3 bucket
aws glue create-crawler \
--region $AWS_REGION \
--name $CRAWLER_NAME \
--role arn:aws:iam::"$ACCOUNT_ID":role/AWSGlueServiceRole-test-hive \
--database-name $GLUE_DB_NAME \
--targets "{\"S3Targets\": [{\"Path\": \"s3://$BUCKET/hive/\"}]}" \
--no-paginate

sleep 5
echo "Now we run the crawler to read the S3 bucket to create a Glue table..."
aws glue start-crawler --region $AWS_REGION --name $CRAWLER_NAME --no-paginate

x=0
while [ $(aws glue get-crawler --name $CRAWLER_NAME --region $AWS_REGION | jq -r .Crawler.State ) != "READY" ]
do
  seconds=$((x * 10))
  echo "Crawl job in progress...(${seconds}s)"
  sleep 10
  x=$(( x + 1 ))
done
echo "Crawl job finished"

sleep 2
echo "Let's check and make sure our table is now generated."
# Confirm that the database metadata is now collected
export GLUE_TABLE_NAME=$(aws glue get-tables --database-name $GLUE_DB_NAME --region $AWS_REGION | jq -r '.TableList[0].Name')
echo "The table name is: $GLUE_TABLE_NAME."
