FROM docker.io/kubeflow/spark-operator:v1beta2-1.6.2-3.5.0

ENV SPARK_HOME /opt/spark

RUN rm -rf /opt/spark/jars/hadoop*.jar

RUN cd /opt/spark/ && \
    echo '#!/bin/sh\nset -ex\njava -jar ./jars/ivy-2.5.1.jar -dependency $@ -cache /tmp/.ivy -retrieve "./jars/[artifact]-[revision](-[classifier]).[ext]" -types jar -confs default' > install-dep.sh && \
    chmod +x install-dep.sh

RUN cd /opt/spark/ && \
    ./install-dep.sh org.apache.hadoop hadoop-yarn-server-web-proxy 3.4.0 && \
    ./install-dep.sh org.apache.hadoop hadoop-client-runtime 3.4.0 && \
    ./install-dep.sh org.apache.hadoop hadoop-client-api 3.4.0 && \
    ./install-dep.sh org.apache.hadoop hadoop-aws 3.4.0 && \
    rm -rf /tmp/.ivy/