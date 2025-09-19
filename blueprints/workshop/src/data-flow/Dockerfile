# Notes:
# Flink operator does not support flink 2.1 as of this writing. This means:
# 1. We need to use flink 2.0
# 2. flink 2.0 on arm64 requires python 3.11 because one of dependencies requires a package removed in 3.12.


FROM docker.io/library/flink:2.0.0-java17 AS builder

USER root
RUN apt-get update && \
    apt-get install -y build-essential cmake openjdk-17-jdk-headless && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

USER flink
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-arm64/
ENV PATH="/opt/flink/.local/bin:$PATH"
RUN uv python install 3.11
RUN uv venv
ENV VIRTUAL_ENV=.venv
ENV PATH=.venv/bin:$PATH
ENV CMAKE_BUILD_PARALLEL_LEVEL="$(nproc)"
RUN uv pip install --only-binary=all apache-flink==2.0.0

FROM docker.io/library/flink:2.0.0-java17

USER flink
COPY --from=builder /opt/flink/.local /opt/flink/.local
COPY --from=builder /opt/flink/.venv /opt/flink/.venv
RUN mkdir ./plugins/s3-fs-hadoop && cp ./opt/flink-s3-fs-hadoop-2.0.0.jar ./plugins/s3-fs-hadoop/

# Add Kafka and Iceberg connectors
RUN curl -L https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-kafka/2.0.0/flink-sql-connector-kafka-2.0.0.jar -o /opt/flink/lib/flink-sql-connector-kafka-2.0.0.jar
RUN curl -L https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-flink-runtime-2.0/1.10.0/iceberg-flink-runtime-2.0-1.10.0.jar -o /opt/flink/lib/iceberg-flink-runtime-2.0.0.jar



RUN ln -sf /opt/flink/.local/share/uv/python/cpython-3.11*/bin/python /opt/flink/.local/bin/python

ENV PATH="/opt/flink/.local/bin:$PATH"
ENV VIRTUAL_ENV=.venv
ENV PATH=.venv/bin:$PATH


# /docker-entrypoint.sh
# bash -c kubernetes-jobmanager.sh kubernetes-application

cp /opt/flink/conf/config.yaml /tmp/config.yaml
sed -i 's/port: '\''6124'\''/port: '\''6125'\''/' /tmp/config.yaml
sed -i '/jobmanager:/,/rpc:/{/rpc:/a\    port: 7124
}' /tmp/config.yaml
echo "rest:
  port: 8082" >> /tmp/config.yaml
export FLINK_CONF_DIR=/tmp
kubernetes-jobmanager.sh kubernetes-application

wget https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-kafka/3.4.0-1.20/flink-sql-connector-kafka-3.4.0-1.20.jar

wget https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-kafka/3.4.0-1.20/flink-sql-connector-kafka-3.4.0-1.20.jar