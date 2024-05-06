# Dockerfile for Apache Spark with additional JARs downloaded at build time
FROM apache/spark-py:v3.3.2
WORKDIR /app

# Use root to create a new user and configure permissions
USER root

# Install wget to download JAR files
RUN apt-get update && apt-get install -y wget && \
    rm -rf /var/lib/apt/lists/*

# Create a new user 'spark-user' with UID 1001
RUN groupadd -r spark-group && useradd -r -u 1001 -g spark-group spark-user

RUN mkdir -p /home/spark-user/.ivy2/cache
RUN mkdir -p /app/jars

RUN cd /app/jars && \
    wget -q "https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.11.1026/aws-java-sdk-bundle-1.11.1026.jar" && \
    wget -q "https://repo1.maven.org/maven2/commons-logging/commons-logging/1.1.3/commons-logging-1.1.3.jar" && \
    wget -q "https://repo1.maven.org/maven2/org/apache/commons/commons-pool2/2.11.1/commons-pool2-2.11.1.jar" && \
    wget -q "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.3.2/hadoop-aws-3.3.2.jar" && \
    wget -q "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-client-api/3.3.2/hadoop-client-api-3.3.2.jar" && \
    wget -q "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-client-runtime/3.3.2/hadoop-client-runtime-3.3.2.jar" && \
    wget -q "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-3.3_2.12/1.0.0/iceberg-spark-runtime-3.3_2.12-1.0.0.jar" && \
    wget -q "https://repo1.maven.org/maven2/com/google/code/findbugs/jsr305/3.0.0/jsr305-3.0.0.jar" && \
    wget -q "https://repo1.maven.org/maven2/org/apache/kafka/kafka-clients/2.8.1/kafka-clients-2.8.1.jar" && \
    wget -q "https://repo1.maven.org/maven2/org/lz4/lz4-java/1.7.1/lz4-java-1.7.1.jar" && \
    wget -q "https://repo1.maven.org/maven2/org/apache/parquet/parquet-avro/1.12.3/parquet-avro-1.12.3.jar" && \
    wget -q "https://repo1.maven.org/maven2/org/scala-lang/scala-library/2.12.15/scala-library-2.12.15.jar" && \
    wget -q "https://repo1.maven.org/maven2/org/slf4j/slf4j-api/1.7.30/slf4j-api-1.7.30.jar" && \
    wget -q "https://repo1.maven.org/maven2/org/xerial/snappy/snappy-java/1.1.8.1/snappy-java-1.1.8.1.jar" && \
    wget -q "https://repo1.maven.org/maven2/org/apache/spark/spark-sql-kafka-0-10_2.12/3.3.2/spark-sql-kafka-0-10_2.12-3.3.2.jar" && \
    wget -q "https://repo1.maven.org/maven2/org/apache/spark/spark-tags_2.12/3.3.2/spark-tags_2.12-3.3.2.jar" && \
    wget -q "https://repo1.maven.org/maven2/org/apache/spark/spark-token-provider-kafka-0-10_2.12/3.3.2/spark-token-provider-kafka-0-10_2.12-3.3.2.jar" && \
    wget -q "https://repo1.maven.org/maven2/org/wildfly/openssl/wildfly-openssl/1.0.7.Final/wildfly-openssl-1.0.7.Final.jar"

# Set the owner of the Ivy cache directory and /app to the new user
RUN chown -R spark-user:spark-group /home/spark-user/
RUN chown -R spark-user:spark-group /app/

# Switch to the new user for running the application
USER spark-user

# Add the Spark application script to the container
ADD app.py /app

# Set the entry point for the container
ENTRYPOINT ["/opt/entrypoint.sh"]
