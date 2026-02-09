FROM docker.io/library/spark:4.0.0

RUN wget -P /opt/spark/jars/ \
    https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark/1.10.0/iceberg-spark-1.10.0.jar \
    https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-4.0_2.13/1.10.0/iceberg-spark-runtime-4.0_2.13-1.10.0.jar \
    https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-extensions-4.0_2.13/1.10.0/iceberg-spark-extensions-4.0_2.13-1.10.0.jar \
    https://repo1.maven.org/maven2/software/amazon/awssdk/bundle/2.34.0/bundle-2.34.0.jar \
    https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.4.1/hadoop-aws-3.4.1.jar

RUN wget -P /opt/spark/jars/ https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.8/postgresql-42.7.8.jar
