#--------------------------------------------------------------------------------------------
# Dockerfile for Apache Spark 4.0.1 with S3A Support on multi-arch platforms (AMD64 & ARM64)
#--------------------------------------------------------------------------------------------
# Step1: Create a Private or Public ECR repo from AWS Console or CLI
#   e.g., aws ecr-public create-repository --repository-name spark --region us-east-1
#---
# Step2: Docker Login:
#   aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws/<repoAlias>
#---
# Step3: Build multi arch image and push it to ECR:
#   docker buildx build --platform linux/amd64,linux/arm64 -t public.ecr.aws/<repoAlias>/spark:4.0.1-scala2.13-java21-python3-r-ubuntu --push .
#--------------------------------------------------------------------------------------------
# Use the official Spark base image with Java 21 and Python 3
FROM apache/spark:4.0.1-scala2.13-java21-python3-r-ubuntu
# Arguments for version control
ARG HADOOP_VERSION=3.4.2
ARG AWS_SDK_VERSION=2.38.0
ARG ICEBERG_SPARK_VERSION=1.10.0
ARG ICEBERG_RUNTIME_VERSION=4.0_2.13
ARG ICEBERG_EXT_VERSION=4.0_2.13
ARG POSTGRES_VERSION=42.7.8
ARG S3_TABLES_VERSION=0.1.3
ARG CELEBORN_VERSION=0.6.1
ARG SPARK_UID=185
# Set environment variables
ENV SPARK_HOME=/opt/spark
# Set up as root to install dependencies and tools
USER root
# Remove any existing/older libraries to avoid conflicts
RUN rm -f ${SPARK_HOME}/jars/bundle-* && \
    rm -f ${SPARK_HOME}/jars/hadoop-client-* && \
    rm -f ${SPARK_HOME}/jars/hadoop-aws-* && \
    rm -f ${SPARK_HOME}/jars/iceberg-spark-* && \
    rm -f ${SPARK_HOME}/jars/s3-tables-* && \
    rm -f ${SPARK_HOME}/jars/celeborn-client-* && \
    rm -f ${SPARK_HOME}/jars/postgresql-*
# Add Hadoop AWS connector and AWS SDK for S3A support, Iceberg and S3 Tables jars, Apache Celeborn, and Postgres for workshop example
RUN wget -P /opt/spark/jars/ \
    https://repo1.maven.org/maven2/software/amazon/awssdk/bundle/${AWS_SDK_VERSION}/bundle-${AWS_SDK_VERSION}.jar \
    https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-client-api/${HADOOP_VERSION}/hadoop-client-api-${HADOOP_VERSION}.jar \
    https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-client-runtime/${HADOOP_VERSION}/hadoop-client-runtime-${HADOOP_VERSION}.jar \
    https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/${HADOOP_VERSION}/hadoop-aws-${HADOOP_VERSION}.jar \
    https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark/${ICEBERG_SPARK_VERSION}/iceberg-spark-${ICEBERG_SPARK_VERSION}.jar \
    https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-${ICEBERG_RUNTIME_VERSION}/${ICEBERG_SPARK_VERSION}/iceberg-spark-runtime-${ICEBERG_RUNTIME_VERSION}-${ICEBERG_SPARK_VERSION}.jar \
    https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-extensions-${ICEBERG_EXT_VERSION}/${ICEBERG_SPARK_VERSION}/iceberg-spark-extensions-${ICEBERG_EXT_VERSION}-${ICEBERG_SPARK_VERSION}.jar \
    https://repo1.maven.org/maven2/software/amazon/s3tables/s3-tables-catalog-for-iceberg-runtime/${S3_TABLES_VERSION}/s3-tables-catalog-for-iceberg-runtime-${S3_TABLES_VERSION}.jar \
    https://repo1.maven.org/maven2/org/apache/celeborn/celeborn-client-spark-4-shaded_2.13/${CELEBORN_VERSION}/celeborn-client-spark-4-shaded_2.13-${CELEBORN_VERSION}.jar \
    https://repo1.maven.org/maven2/org/postgresql/postgresql/${POSTGRES_VERSION}/postgresql-${POSTGRES_VERSION}.jar
# Set working directory
WORKDIR ${SPARK_HOME}
# Switch to non-root user
USER ${SPARK_UID}