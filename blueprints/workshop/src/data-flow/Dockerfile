FROM docker.io/library/flink:scala_2.12 AS builder

USER root
RUN apt-get update && \
    apt-get install -y build-essential cmake openjdk-17-jdk-headless && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

USER flink
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-arm64/
ENV PATH="/opt/flink/.local/bin:$PATH"
RUN uv python install 3.12
RUN uv venv
ENV VIRTUAL_ENV=.venv
ENV PATH=.venv/bin:$PATH
# CMAKE_BUILD_PARALLEL_LEVEL="$(nproc)"
RUN uv pip install --only-binary=all apache-flink==2.1.0

FROM docker.io/library/flink:scala_2.12

USER flink
COPY --from=builder /opt/flink/.local /opt/flink/.local
COPY --from=builder /opt/flink/.venv /opt/flink/.venv

RUN ln -sf /opt/flink/.local/share/uv/python/cpython-3.12*/bin/python /opt/flink/.local/bin/python

ENV PATH="/opt/flink/.local/bin:$PATH"
ENV VIRTUAL_ENV=.venv
ENV PATH=.venv/bin:$PATH
