FROM apache/spark:3.5.6-scala2.12-java17-python3-ubuntu
USER root
ARG PYTHON_VERSION=3.11.3
ARG BEAM_VERSION=2.58.0
ARG HADOOP_VERSION=3.4.1
ARG AWS_SDK_VERSION=2.29.0
ARG SPARK_UID=185

ENV SPARK_HOME=/opt/spark

# Set up as root to install dependencies and tools
USER root

# Remove any old Hadoop libraries to avoid conflicts
RUN rm -f ${SPARK_HOME}/jars/hadoop-client-* && \
    rm -f ${SPARK_HOME}/jars/hadoop-yarn-server-web-proxy-*.jar

# Add Hadoop AWS connector and related Hadoop dependencies
RUN cd ${SPARK_HOME}/jars && \
    wget https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/${HADOOP_VERSION}/hadoop-aws-${HADOOP_VERSION}.jar && \
    wget https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-client-api/${HADOOP_VERSION}/hadoop-client-api-${HADOOP_VERSION}.jar && \
    wget https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-client-runtime/${HADOOP_VERSION}/hadoop-client-runtime-${HADOOP_VERSION}.jar && \
    wget https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-common/${HADOOP_VERSION}/hadoop-common-${HADOOP_VERSION}.jar && \
    wget https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-yarn-server-web-proxy/${HADOOP_VERSION}/hadoop-yarn-server-web-proxy-${HADOOP_VERSION}.jar && \
    wget https://repo1.maven.org/maven2/software/amazon/awssdk/bundle/${AWS_SDK_VERSION}/bundle-${AWS_SDK_VERSION}.jar

RUN apt-get update && \
    apt-get install -y gcc libssl-dev lzma liblzma-dev libbz2-dev libffi-dev tar gzip wget make && \
    wget https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz && \
    tar xzf Python-${PYTHON_VERSION}.tgz && \
    cd Python-${PYTHON_VERSION} && \
    ./configure --enable-optimizations && \
    make install
ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV --copies
RUN cp -r /usr/local/lib/python3.11/* $VIRTUAL_ENV/lib/python3.11
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
RUN python3 -m pip install --upgrade pip && \
    python3 -m pip install apache_beam==${BEAM_VERSION} \
    s3fs \
    boto3
ENV PYSPARK_PYTHON="/opt/venv/bin/python3"
ENV PYSPARK_DRIVER_PYTHON="/opt/venv/bin/python3"
ENV RUN_PYTHON_SDK_IN_DEFAULT_ENVIRONMENT=1
COPY --from=apache/beam_python3.11_sdk:2.58.0 /opt/apache/beam /opt/apache/beam

# Set working directory
WORKDIR ${SPARK_HOME}

USER ${SPARK_UID}
