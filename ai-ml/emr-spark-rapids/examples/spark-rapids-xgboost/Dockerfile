FROM 895885662937.dkr.ecr.us-west-2.amazonaws.com/spark/emr-6.10.0-spark-rapids:latest

USER root

#COPY spark-rapids-benchmarks /usr/local/spark-rapids-benchmarks

RUN yum -y remove openssl-devel-1.0.2k-24.amzn2.0.6.x86_64 && \
    yum -y install gcc openssl11-devel bzip2-devel libffi-devel tar gzip wget make && \
    wget https://www.python.org/ftp/python/3.10.11/Python-3.10.11.tgz && \
    tar -xvvf Python-3.10.11.tgz && \
    cd Python-3.10.11 && \
    ./configure --enable-optimizations && \
    make install

ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV --copies
RUN cp -r /usr/local/lib/python3.10/* $VIRTUAL_ENV/lib/python3.10/


# install python libraries
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

RUN pip3 install \
      xgboost==1.7.5 \
      s3fs \
      fsspec \
      scikit-learn \
      pandas \
      pyarrow

USER hadoop:hadoop
