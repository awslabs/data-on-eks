#!/bin/bash

# Function to get AWS region using Python and Boto3
get_region_with_python() {
    python3 - <<EOF
import boto3

def get_region():
    session = boto3.session.Session()
    return session.region_name

print(get_region())
EOF
}

# Prompt user to enter region or press enter to detect automatically
read -p "Enter AWS region or press enter to detect automatically: " user_region

# Determine region either from user input, EC2 metadata, or Python script
if [ -n "$user_region" ]; then
    REGION_CODE=$user_region
elif REGION_CODE=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region 2>/dev/null); [ -z "$REGION_CODE" ]; then
    REGION_CODE=$(get_region_with_python)
fi

# Validate if REGION_CODE is set
if [ -z "$REGION_CODE" ]; then
    echo "Unable to determine AWS region."
    exit 1
fi

echo "Using AWS region: $REGION_CODE"

# Determine appropriate EKS AZs based on the region
if [[ $REGION_CODE == "us-east-1" ]]; then
    AZ1="use1-az6"
    AZ2="use1-az5"
elif [[ $REGION_CODE == "us-west-2" ]]; then
    AZ1="usw2-az4"
    AZ2="usw2-az3"
else
    echo "Unsupported region: $REGION_CODE"
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

echo "Your EKS availability zones are $EKSAZ1 and $EKSAZ2"
