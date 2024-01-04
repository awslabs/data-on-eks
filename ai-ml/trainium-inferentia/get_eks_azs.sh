#!/bin/bash

# Desired AWS region should be passed in as arg1, ex 'us-west-2'
REGION_CODE=$1

# Determine appropriate EKS AZs based on the AWS region. (EKS requires that we specify 2 AZs)
#   The AZs specified here currently support both trn1 and inf2, but inf2 is also supported
#   in additional AZs. AZ1 should be preferred when launching nodes.
if [[ $REGION_CODE == "us-west-2" ]]; then
    AZ1="usw2-az4"
    AZ2="usw2-az1"
elif [[ $REGION_CODE == "us-east-1" ]]; then
    AZ1="use1-az6"
    AZ2="use1-az5"
elif [[ $REGION_CODE == "us-east-2" ]]; then
    AZ1="use2-az3"
    AZ2="use2-az1"
else
    echo "{\"error\": \"Unsupported region: $REGION_CODE\"}"
    exit 1
fi

# Fetch and set the actual names of the availability zones
EKSAZ1=$(aws ec2 describe-availability-zones \
    --region $REGION_CODE \
    --filters "Name=zone-id,Values=$AZ1" \
    --query "AvailabilityZones[].ZoneName" \
    --output text)

EKSAZ2=$(aws ec2 describe-availability-zones \
    --region $REGION_CODE \
    --filters "Name=zone-id,Values=$AZ2" \
    --query "AvailabilityZones[].ZoneName" \
    --output text)

# Check if EKSAZ1 and EKSAZ2 are not empty and output as JSON
if [ -n "$EKSAZ1" ] && [ -n "$EKSAZ2" ]; then
    echo "{\"EKSAZ1\": \"$EKSAZ1\", \"EKSAZ2\": \"$EKSAZ2\"}"
else
    # Output errors as JSON
    echo "{\"error\": \"Unable to determine EKS availability zones\"}"
    exit 1
fi
