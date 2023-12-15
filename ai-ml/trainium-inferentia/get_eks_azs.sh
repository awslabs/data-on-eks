#!/bin/bash

# Hardcoded AWS region
REGION_CODE="us-west-2"

# Determine appropriate EKS AZs based on the hardcoded region
if [[ $REGION_CODE == "us-west-2" ]]; then
    AZ1="usw2-az4"
    AZ2="usw2-az3"
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
