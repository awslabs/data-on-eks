#--------------------------------------------------------------------------------------------
# Dockerfile for Apache Spark 3.5.1 with S3A Support on multi-arch platforms (AMD64 & ARM64)
#--------------------------------------------------------------------------------------------
# Step1: Create a Private or Public ECR repo from AWS Console or CLI
#   e.g., aws ecr-public create-repository --repository-name spark3.3.1-hadoop3.2-aws-java-sdk-bundle-1.12.647 --region us-east-1
#---
# Step2: Docker Login:
#   aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws/<repoAlias>
#---
# Step3: Build multi arch image and push it to ECR:
#   docker buildx build --platform linux/amd64,linux/arm64 -t public.ecr.aws/<repoAlias>/spark3.3.1-hadoop3.2-aws-java-sdk-bundle-1.12.647:latest --push .
#--------------------------------------------------------------------------------------------

# Use the official Apache Spark base image
FROM apache/spark:3.5.1

# Define Spark and Hadoop versions
ENV SPARK_VERSION=3.5.1
ENV HADOOP_VERSION=3.3.4
ENV AWS_SDK_VERSION=1.12.767

# Install wget, Python, and PySpark
USER root
RUN apt-get update && \
    apt-get install -y wget python3 python3-pip && \
    ln -s /usr/bin/python3 /usr/bin/python && \
    pip3 install pyspark==$SPARK_VERSION


# Add the AWS Java SDK and Hadoop-AWS package to enable S3A support
# These versions should be compatible with the Spark and Hadoop versions used
RUN cd /opt/spark/jars && \
    wget -q "https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/${AWS_SDK_VERSION}/aws-java-sdk-bundle-${AWS_SDK_VERSION}.jar" && \
    wget -q "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/${HADOOP_VERSION}/hadoop-aws-${HADOOP_VERSION}.jar"

# Switch back to the non-root user
USER 1001

# Set the entry point for the container
ENTRYPOINT ["/opt/entrypoint.sh"]
