#--------------------------------------------------------------------------------------------
# Dockerfile for Apache Spark 3.3.1 with S3A Support on multi-arch platforms (AMD64 & ARM64)
#--------------------------------------------------------------------------------------------
# Step1: Create a Private or Public ECR repo from AWS Console or CLI
#   e.g., aws ecr-public create-repository --repository-name spark --region us-east-1
#---
# Step2: Docker Login:
#   aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws/<repoAlias>
#---
# Step3: Build multi arch image and push it to ECR:
#   docker buildx build --platform linux/amd64,linux/arm64 -t public.ecr.aws/<repoAlias>/spark:3.5.3-scala2.12-java17-python3-ubuntu --push .
#--------------------------------------------------------------------------------------------

# Use the official Spark base image with Java 17 and Python 3
FROM apache/spark:3.5.3-scala2.12-java17-python3-ubuntu

# Arguments for version control
ARG HADOOP_VERSION=3.4.1
ARG AWS_SDK_VERSION=2.29.0
ARG SPARK_UID=185

# Set environment variables
ENV SPARK_HOME=/opt/spark

# Set up as root to install dependencies and tools
USER root

# Remove any old Hadoop libraries
RUN rm -f ${SPARK_HOME}/jars/hadoop-client-* && \
    rm -f ${SPARK_HOME}/jars/hadoop-yarn-server-web-proxy-*.jar

# Add Hadoop AWS connector and AWS SDK for S3A support, along with hadoop-common dependencies
# TODO: hadoop-common, hadoop-yarn-server-web-proxy might not be required. Remove these and test it.
RUN cd ${SPARK_HOME}/jars && \
    wget https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/${HADOOP_VERSION}/hadoop-aws-${HADOOP_VERSION}.jar && \
    wget https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-client-api/${HADOOP_VERSION}/hadoop-client-api-${HADOOP_VERSION}.jar && \
    wget https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-client-runtime/${HADOOP_VERSION}/hadoop-client-runtime-${HADOOP_VERSION}.jar && \
    wget https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-common/${HADOOP_VERSION}/hadoop-common-${HADOOP_VERSION}.jar && \
    wget https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-yarn-server-web-proxy/${HADOOP_VERSION}/hadoop-yarn-server-web-proxy-${HADOOP_VERSION}.jar && \
    wget https://repo1.maven.org/maven2/software/amazon/awssdk/bundle/${AWS_SDK_VERSION}/bundle-${AWS_SDK_VERSION}.jar

# Set working directory
WORKDIR ${SPARK_HOME}

# Switch to non-root user
USER ${SPARK_UID}
