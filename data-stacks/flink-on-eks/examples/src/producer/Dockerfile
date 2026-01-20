FROM docker.io/library/flink:2.1.0-java17

USER root
RUN apt-get update && \
    apt-get install -y build-essential cmake openjdk-17-jdk-headless && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
RUN export JAVA_HOME=$(ls -d /usr/lib/jvm/java-17-openjdk*) && echo "export JAVA_HOME=$JAVA_HOME" >> /etc/bash.bashrc

USER flink
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/opt/flink/.local/bin:$PATH"
RUN uv python install 3.12
RUN uv venv
ENV VIRTUAL_ENV=.venv
ENV PATH=.venv/bin:$PATH

RUN uv pip install --only-binary=all apache-flink==2.1.0 kafka-python==2.2.15
