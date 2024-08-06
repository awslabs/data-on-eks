FROM apache/spark:3.5.1-scala2.12-java11-python3-ubuntu

RUN rm -rf /opt/spark/jars/hadoop*.jar

RUN cd /opt/spark/ && \
    echo 'java -jar ./jars/ivy-2.5.1.jar -dependency $@ -cache /tmp/.ivy -retrieve "./jars/[artifact]-[revision](-[classifier]).[ext]" -types jar -confs default' > install-dep.sh

USER root
RUN chmod +x /opt/spark/install-dep.sh

USER spark

RUN cd /opt/spark/ && \
    /opt/spark/install-dep.sh org.apache.hadoop hadoop-yarn-server-web-proxy 3.4.0 && \
    /opt/spark/install-dep.sh org.apache.hadoop hadoop-client-runtime 3.4.0 && \
    /opt/spark/install-dep.sh org.apache.hadoop hadoop-client-api 3.4.0 && \
    /opt/spark/install-dep.sh org.apache.hadoop hadoop-aws 3.4.0 && \
    rm -rf /tmp/.ivy/
