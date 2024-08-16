FROM public.ecr.aws/neuron/pytorch-inference-neuronx:2.1.2-neuronx-py310-sdk2.19.1-ubuntu20.04

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

# Amazon Internal version of vLLM code; Upstream PR is in progres
COPY Vllm /Vllm
RUN python3 -m pip install /Vllm

# Patch Neuron SDK
COPY neuron_artifacts/. /neuron_artifacts/
RUN python3 -m pip install --no-deps /neuron_artifacts/pip/*

# TODO: Findout the unreleased code?? 
RUN apt-get install -y /neuron_artifacts/apt/aws-neuronx-collectives-2.x.14874.0-83d73c6de.deb
RUN apt-get install -y --allow-downgrades /neuron_artifacts/apt/aws-neuronx-tools-2.17.0.0.deb
RUN apt-get install -y /neuron_artifacts/apt/aws-neuronx-runtime-lib-2.x.14063.0-abb94ca8a.deb

# Install ray
RUN python3 -m pip install ray
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

# Ray Cluster for future Ray implementation
# COPY ray_init.sh /usr/local/bin/ray_init.sh

# Entry scripts
RUN pip install aws-embedded-metrics

COPY main.py /usr/local/bin/main.py
COPY run.sh /usr/local/bin/run.sh
