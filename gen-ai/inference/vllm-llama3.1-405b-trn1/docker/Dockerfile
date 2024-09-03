# -----------------------------------------------------------------------------------
# Important Notice:
# This image cannot be built directly as it relies on internal vLLM and Neuron code.
# For testing purposes, we have provided a public image that includes the necessary internal code.
#
# Please be aware of the following:
# 1. The line "COPY neuron_artifacts/. /neuron_artifacts/" will be replaced or removed once Neuron SDK 2.20 is released.
# 2. The line "COPY vllm /vllm" will be replaced or removed once Neuron SDK 2.20 is released, and the Neuron team upstreams the changes to the vLLM project.
# -----------------------------------------------------------------------------------

ENV VLLM_TARGET_DEVICE=neuron
ENV AWS_DOEKS_MAX_BATCH_SIZE=1
ENV NEURON_CONTEXT_LENGTH_ESTIMATE='[1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072]'
ENV NEURON_QUANT=False
ENV NEURON_SEQUENCE_PARALLEL=True
ENV NEURON_CC_PIPELINE_FACTOR=4
ENV NEURON_ON_DEVICE_EMBEDDING=False
ENV NEURON_SHARD_OVER_SEQUENCE=True
ENV NEURON_MLP_FUSE=True
ENV NEURON_MLP_TRANSPOSE=True


WORKDIR /usr/local/bin

# Internal code
# TODO: Remove this block once Neuron vLLM code is merged in upstream vLLM project
COPY vllm /vllm

# Ensure the vllm directory has the right permissions
RUN chmod -R u+w /vllm
RUN python3 -m pip install -e /vllm

# Patch Neuron SDK
# TODO: Remove this block once Neuron sdk2.20 is released
COPY neuron_artifacts/. /neuron_artifacts/
RUN python3 -m pip install --no-deps /neuron_artifacts/pip/*

RUN apt-get install -y /neuron_artifacts/apt/aws-neuronx-collectives-2.x.14874.0-83d73c6de.deb
RUN apt-get install -y --allow-downgrades /neuron_artifacts/apt/aws-neuronx-tools-2.17.0.0.deb
RUN apt-get install -y /neuron_artifacts/apt/aws-neuronx-runtime-lib-2.x.14063.0-abb94ca8a.deb


RUN pip install pynvml
RUN python3 -m pip install ml-dtypes==0.2.0

# EFA Installer - required - installs libfabric (but no EFA driver) inside the container
ENV LD_LIBRARY_PATH="/opt/aws/neuron/lib:${LD_LIBRARY_PATH}"
ENV LD_LIBRARY_PATH="/opt/amazon/efa/lib:${LD_LIBRARY_PATH}"
ENV LD_LIBRARY_PATH="/opt/amazon/efa/lib64:${LD_LIBRARY_PATH}"
ENV LD_LIBRARY_PATH="/opt/amazon/openmpi/lib64:${LD_LIBRARY_PATH}"
ENV LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}"
RUN apt-get update \
    && cd $HOME \
    && curl -O https://efa-installer.amazonaws.com/aws-efa-installer-latest.tar.gz \
    && wget https://efa-installer.amazonaws.com/aws-efa-installer.key && gpg --import aws-efa-installer.key \
    && cat aws-efa-installer.key | gpg --fingerprint \
    && wget https://efa-installer.amazonaws.com/aws-efa-installer-latest.tar.gz.sig && gpg --verify ./aws-efa-installer-latest.tar.gz.sig \
    && tar -xf aws-efa-installer-latest.tar.gz \
    && cd aws-efa-installer \
    && ./efa_installer.sh -y -g -d --skip-kmod --skip-limit-conf --no-verify \
    && rm -fr /root/aws-efa-installer* \
    && cd $HOME \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/tmp* \
    && apt-get clean


COPY neuron_multi_node_runner.py /usr/local/bin/neuron_multi_node_runner.py
COPY run.sh /usr/local/bin/run.sh
