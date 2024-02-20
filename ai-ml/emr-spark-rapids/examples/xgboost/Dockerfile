# Instructions to build a custom docker image with xgboost and EMR 7.0.0 Spark Rapids base image
#--------------------------------------------------------------
# 1. aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws
# 2. docker buildx build --platform=linux/amd64 -t emr-7.0.0-spark-rapids-xgboost-custom .
# 3. Create a new ECR repository from ECR console. e.g., <ECR_ACCOUNT_ID>/<ECR_REPO>/emr-7.0.0-spark-rapids-xgboost-custom
# 4. docker tag emr-7.0.0-spark-rapids-xgboost-custom:latest <ECR_ACCOUNT_ID>/<ECR_REPO>/emr-7.0.0-spark-rapids-xgboost-custom:latest
# 5. docker push <ECR_ACCOUNT_ID>/<ECR_REPO>/emr-7.0.0-spark-rapids-xgboost-custom:latest
#--------------------------------------------------------------
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
