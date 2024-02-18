FROM public.ecr.aws/emr-on-eks/spark/emr-7.0.0-spark-rapids:latest

ARG MAVEN_VERSION=3.9.6
ARG MAVEN_URL=https://apache.osuosl.org/maven/maven-3/${MAVEN_VERSION}/binaries
ARG VERSION=1.0.0
ARG XGBOOST_VERSION=2.0.3

USER root

ADD pom.xml /tmp/pom.xml

RUN yum install -y wget tar \
    && mkdir -p /usr/share/maven \
    && curl -o /tmp/apache-maven.tar.gz ${MAVEN_URL}/apache-maven-${MAVEN_VERSION}-bin.tar.gz \
    && tar -xzf /tmp/apache-maven.tar.gz -C /usr/share/maven --strip-components=1 \
    && rm -f /tmp/apache-maven.tar.gz \
    && ln -s /usr/share/maven/bin/mvn /usr/bin/mvn \
    && cd /tmp && mvn clean install -f pom.xml \
    && mkdir -p /usr/lib/xgboost \
    && cp target/spark-rapids-xgboost-jar-${VERSION}.jar /usr/lib/xgboost/spark-rapids-xgboost-jar-${VERSION}.jar

RUN python3 -m pip install \
      xgboost==${XGBOOST_VERSION} \
      s3fs \
      fsspec \
      scikit-learn \
      pandas \
      pyarrow

USER hadoop:hadoop
