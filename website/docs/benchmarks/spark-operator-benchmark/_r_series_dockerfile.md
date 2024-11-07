```dockerfile
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

# Install necessary build tools and specific sbt version 0.13.18
RUN apt-get update && \
    apt-get install -y \
        gcc \
        make \
        flex \
        bison \
        git \
        openjdk-17-jdk \
        wget \
        curl && \
    # Install sbt 0.13.18
    wget https://github.com/sbt/sbt/releases/download/v0.13.18/sbt-0.13.18.tgz && \
    tar -xzf sbt-0.13.18.tgz -C /usr/local && \
    ln -s /usr/local/sbt/bin/sbt /usr/local/bin/sbt && \
    # Cleanup
    rm sbt-0.13.18.tgz && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Clone and compile TPC-DS toolkit
WORKDIR /opt
RUN git clone https://github.com/databricks/tpcds-kit.git && \
    cd tpcds-kit/tools && \
    make OS=LINUX && \
    chmod +x dsdgen dsqgen

# Clone the SQL perf library and related files
# Change the branch from delta to tpcds-v2.13 for latest
RUN git clone -b delta https://github.com/aws-samples/emr-on-eks-benchmark.git /tmp/emr-on-eks-benchmark

# Build the Databricks SQL perf library
RUN cd /tmp/emr-on-eks-benchmark/spark-sql-perf && sbt +package

# Use the compiled Databricks SQL perf library to build benchmark utility
RUN cd /tmp/emr-on-eks-benchmark/ && \
    mkdir -p /tmp/emr-on-eks-benchmark/benchmark/libs && \
    cp /tmp/emr-on-eks-benchmark/spark-sql-perf/target/scala-2.12/*.jar /tmp/emr-on-eks-benchmark/benchmark/libs && \
    cd /tmp/emr-on-eks-benchmark/benchmark && sbt assembly

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

# Create directory for TPC-DS data and set permissions
RUN mkdir -p /opt/tpcds-data && \
    chown -R ${SPARK_UID}:${SPARK_UID} /opt/tpcds-data

# Copy the built JARs to Spark's jars directory
RUN mkdir -p ${SPARK_HOME}/examples/jars/ && \
    cp /tmp/emr-on-eks-benchmark/benchmark/target/scala-2.12/*jar ${SPARK_HOME}/examples/jars/ && \
    chown -R ${SPARK_UID}:${SPARK_UID} ${SPARK_HOME}/examples

# Set working directory
WORKDIR ${SPARK_HOME}

# Switch to non-root user
USER ${SPARK_UID}
```
