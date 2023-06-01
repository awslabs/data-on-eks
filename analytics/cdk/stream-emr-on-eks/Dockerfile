FROM 895885662937.dkr.ecr.us-west-2.amazonaws.com/spark/emr-6.5.0:latest
USER root
RUN pip3 install --upgrade boto3 pandas numpy
COPY spark-sql-kinesis_2.12-1.2.0_spark-3.0.jar ${SPARK_HOME}/jars/
USER hadoop:hadoop