#!/bin/bash

# Spark Variables
# NOTE: The Spark version needs to have compatible dependency Hadoop and AWS SDK JAR version files.
HADOOP_VERSION="3.3.1" # Replace with your desired Hadoop version
AWS_SDK_VERSION="1.12.647" # Replace with your desired AWS SDK version

# S3 Variables
S3_BUCKET_NAME="<S3_BUCKET_NAME>"  # Replace with your S3 bucket name
# The folder name in the S3 bucket where the JAR files will be stored
FOLDER_NAME="jars"

# Python SparkApplication
PYTHON_SCRIPT_NAME="pyspark-taxi-trip.py"

# JAR file URLs
HADOOP_URL="https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/${HADOOP_VERSION}/hadoop-aws-${HADOOP_VERSION}.jar"
AWS_SDK_URL="https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/${AWS_SDK_VERSION}/aws-java-sdk-bundle-${AWS_SDK_VERSION}.jar"

# Create folder in S3 bucket
aws s3api put-object --bucket "${S3_BUCKET_NAME}" --key "${FOLDER_NAME}/"
if [ $? -ne 0 ]; then
    echo "Failed to create folder in S3 bucket. Exit status: $?"
    exit 1
else
    echo "Folder ${FOLDER_NAME} already created in S3 bucket ${S3_BUCKET_NAME}"
fi

# Download JAR files if they do not exist locally
if [ ! -f "hadoop-aws-${HADOOP_VERSION}.jar" ]; then
    wget -O "hadoop-aws-${HADOOP_VERSION}.jar" "${HADOOP_URL}"
    if [ $? -ne 0 ]; then
        echo "Failed to download hadoop-aws-${HADOOP_VERSION}.jar. Exit status: $?"
        exit 1
    else
        echo "Downloaded hadoop-aws-${HADOOP_VERSION}.jar successfully"
    fi
else
    echo "hadoop-aws-${HADOOP_VERSION}.jar already exists locally, skipping download"
fi

if [ ! -f "aws-java-sdk-bundle-${AWS_SDK_VERSION}.jar" ]; then
    wget -O "aws-java-sdk-bundle-${AWS_SDK_VERSION}.jar" "${AWS_SDK_URL}"
    if [ $? -ne 0 ]; then
        echo "Failed to download aws-java-sdk-bundle-${AWS_SDK_VERSION}.jar. Exit status: $?"
        exit 1
    else
        echo "Downloaded aws-java-sdk-bundle-${AWS_SDK_VERSION}.jar successfully"
    fi
else
    echo "aws-java-sdk-bundle-${AWS_SDK_VERSION}.jar already exists locally, skipping download"
fi

# Upload JAR files to S3 bucket
aws s3 cp "hadoop-aws-${HADOOP_VERSION}.jar" "s3://${S3_BUCKET_NAME}/${FOLDER_NAME}/"
if [ $? -ne 0 ]; then
    echo "Failed to upload hadoop-aws-${HADOOP_VERSION}.jar to S3. Exit status: $?"
    exit 1
else
    echo "Uploaded hadoop-aws-${HADOOP_VERSION}.jar to S3 successfully"
fi

aws s3 cp "aws-java-sdk-bundle-${AWS_SDK_VERSION}.jar" "s3://${S3_BUCKET_NAME}/${FOLDER_NAME}/"
if [ $? -ne 0 ]; then
    echo "Failed to upload aws-java-sdk-bundle-${AWS_SDK_VERSION}.jar to S3. Exit status: $?"
    exit 1
else
    echo "Uploaded aws-java-sdk-bundle-${AWS_SDK_VERSION}.jar to S3 successfully"
fi

# Upload the Python script to S3 bucket
aws s3 cp "${PYTHON_SCRIPT_NAME}" "s3://${S3_BUCKET_NAME}/${FOLDER_NAME}/"
if [ $? -ne 0 ]; then
    echo "Failed to upload ${PYTHON_SCRIPT_NAME} to S3. Exit status: $?"
    exit 1
else
    echo "Uploaded ${PYTHON_SCRIPT_NAME} to S3 successfully"
fi

# Clean up downloaded files
rm "hadoop-aws-${HADOOP_VERSION}.jar" "aws-java-sdk-bundle-${AWS_SDK_VERSION}.jar"
if [ $? -ne 0 ]; then
    echo "Failed to remove local JAR files. Exit status: $?"
    exit 1
else
    echo "Removed local JAR files successfully"
fi

# List contents of the newly created folder in S3 bucket
aws s3 ls "s3://${S3_BUCKET_NAME}/${FOLDER_NAME}/"
if [ $? -ne 0 ]; then
    echo "Failed to list contents of s3://${S3_BUCKET_NAME}/${FOLDER_NAME}/. Exit status: $?"
    exit 1
else
    echo "Contents of s3://${S3_BUCKET_NAME}/${FOLDER_NAME}/ listed successfully"
fi

echo "Script completed successfully."
