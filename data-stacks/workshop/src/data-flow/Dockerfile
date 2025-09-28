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

# Add dependencies
# https://www.decodable.co/blog/catalogs-in-flink-sql-hands-on
# https://www.decodable.co/blog/kafka-to-iceberg-with-flink
WORKDIR /opt/flink/lib
RUN wget  https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-kafka/4.0.1-2.0/flink-sql-connector-kafka-4.0.1-2.0.jar
RUN wget  https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-flink-runtime-2.0/1.10.0/iceberg-flink-runtime-2.0-1.10.0.jar

RUN wget https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.4.2/hadoop-aws-3.4.2.jar

RUN wget https://repo1.maven.org/maven2/software/amazon/awssdk/bundle/2.34.0/bundle-2.34.0.jar

RUN wget https://repo1.maven.org/maven2/io/openlineage/openlineage-flink/1.37.0/openlineage-flink-1.37.0.jar

# commented this out because the apache mirror site is very slow as of this writing
# RUN wget https://dlcdn.apache.org/hadoop/common/hadoop-3.4.2/hadoop-3.4.2-lean.tar.gz
ADD hadoop-3.4.2-lean.tar.gz .

# export HADOOP_CLASSPATH=$(./hadoop-3.4.2/bin/hadoop classpath)
ENV HADOOP_CLASSPATH=/opt/flink/hadoop-3.4.2/etc/hadoop:/opt/flink/hadoop-3.4.2/share/hadoop/common/lib/*:/opt/flink/hadoop-3.4.2/share/hadoop/common/*:/opt/flink/hadoop-3.4.2/share/hadoop/hdfs:/opt/flink/hadoop-3.4.2/share/hadoop/hdfs/lib/*:/opt/flink/hadoop-3.4.2/share/hadoop/hdfs/*:/opt/flink/hadoop-3.4.2/share/hadoop/mapreduce/*:/opt/flink/hadoop-3.4.2/share/hadoop/yarn:/opt/flink/hadoop-3.4.2/share/hadoop/yarn/lib/*:/opt/flink/hadoop-3.4.2/share/hadoop/yarn/*

USER root
RUN rm /opt/flink/lib/hadoop-3.4.2/share/hadoop/common/lib/slf4j*
# RUN chown -R flink:flink /opt/flink/lib/hadoop-3.4.2/

WORKDIR /opt/flink

RUN ln -sf /opt/flink/.local/share/uv/python/cpython-3.11*/bin/python /opt/flink/.local/bin/python

ENV PATH="/opt/flink/.local/bin:$PATH"
ENV VIRTUAL_ENV=.venv
ENV PATH=.venv/bin:$PATH
