```dockerfile
# Java 17과 Python 3이 있는 공식 Spark 베이스 이미지 사용
FROM apache/spark:3.5.3-scala2.12-java17-python3-ubuntu

# 버전 제어를 위한 인자
ARG HADOOP_VERSION=3.4.1
ARG AWS_SDK_VERSION=2.29.0
ARG SPARK_UID=185

# 환경 변수 설정
ENV SPARK_HOME=/opt/spark

# 종속성 및 도구 설치를 위해 root로 설정
USER root

# 필요한 빌드 도구 및 특정 sbt 버전 0.13.18 설치
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
    # sbt 0.13.18 설치
    wget https://github.com/sbt/sbt/releases/download/v0.13.18/sbt-0.13.18.tgz && \
    tar -xzf sbt-0.13.18.tgz -C /usr/local && \
    ln -s /usr/local/sbt/bin/sbt /usr/local/bin/sbt && \
    # 정리
    rm sbt-0.13.18.tgz && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# TPC-DS 툴킷 복제 및 컴파일
WORKDIR /opt
RUN git clone https://github.com/databricks/tpcds-kit.git && \
    cd tpcds-kit/tools && \
    make OS=LINUX && \
    chmod +x dsdgen dsqgen

# SQL perf 라이브러리 및 관련 파일 복제
# 최신 버전은 delta에서 tpcds-v2.13 브랜치로 변경
RUN git clone -b delta https://github.com/aws-samples/emr-on-eks-benchmark.git /tmp/emr-on-eks-benchmark

# Databricks SQL perf 라이브러리 빌드
RUN cd /tmp/emr-on-eks-benchmark/spark-sql-perf && sbt +package

# 컴파일된 Databricks SQL perf 라이브러리를 사용하여 벤치마크 유틸리티 빌드
RUN cd /tmp/emr-on-eks-benchmark/ && \
    mkdir -p /tmp/emr-on-eks-benchmark/benchmark/libs && \
    cp /tmp/emr-on-eks-benchmark/spark-sql-perf/target/scala-2.12/*.jar /tmp/emr-on-eks-benchmark/benchmark/libs && \
    cd /tmp/emr-on-eks-benchmark/benchmark && sbt assembly

# 이전 Hadoop 라이브러리 제거
RUN rm -f ${SPARK_HOME}/jars/hadoop-client-* && \
    rm -f ${SPARK_HOME}/jars/hadoop-yarn-server-web-proxy-*.jar

# S3A 지원을 위한 Hadoop AWS 커넥터 및 AWS SDK와 hadoop-common 종속성 추가
# TODO: hadoop-common, hadoop-yarn-server-web-proxy는 필요하지 않을 수 있음. 제거하고 테스트 필요.
RUN cd ${SPARK_HOME}/jars && \
    wget https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/${HADOOP_VERSION}/hadoop-aws-${HADOOP_VERSION}.jar && \
    wget https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-client-api/${HADOOP_VERSION}/hadoop-client-api-${HADOOP_VERSION}.jar && \
    wget https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-client-runtime/${HADOOP_VERSION}/hadoop-client-runtime-${HADOOP_VERSION}.jar && \
    wget https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-common/${HADOOP_VERSION}/hadoop-common-${HADOOP_VERSION}.jar && \
    wget https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-yarn-server-web-proxy/${HADOOP_VERSION}/hadoop-yarn-server-web-proxy-${HADOOP_VERSION}.jar && \
    wget https://repo1.maven.org/maven2/software/amazon/awssdk/bundle/${AWS_SDK_VERSION}/bundle-${AWS_SDK_VERSION}.jar

# TPC-DS 데이터용 디렉토리 생성 및 권한 설정
RUN mkdir -p /opt/tpcds-data && \
    chown -R ${SPARK_UID}:${SPARK_UID} /opt/tpcds-data

# 빌드된 JAR를 Spark의 jars 디렉토리에 복사
RUN mkdir -p ${SPARK_HOME}/examples/jars/ && \
    cp /tmp/emr-on-eks-benchmark/benchmark/target/scala-2.12/*jar ${SPARK_HOME}/examples/jars/ && \
    chown -R ${SPARK_UID}:${SPARK_UID} ${SPARK_HOME}/examples

# 작업 디렉토리 설정
WORKDIR ${SPARK_HOME}

# 비 root 사용자로 전환
USER ${SPARK_UID}
```
