# -----------------------------------------------------------------------------------
# Important Notice:
# This image cannot be built directly as it relies on internal vLLM and Neuron code.
# For testing purposes, we have provided a public image that includes the necessary internal code.
#
# Please be aware of the following:
# 1. The line "COPY neuron_artifacts/. /neuron_artifacts/" will be replaced or removed once Neuron SDK 2.20 is released.
# 2. The line "COPY vllm /vllm" will be replaced or removed once Neuron SDK 2.20 is released, and the Neuron team upstreams the changes to the vLLM project.
# -----------------------------------------------------------------------------------
FROM public.ecr.aws/neuron/pytorch-inference-neuronx:2.1.2-neuronx-py310-sdk2.20.0-ubuntu20.04

ENV VLLM_TARGET_DEVICE=neuron

WORKDIR /usr/local/bin

# -----------------------------------------------------------------------------------
# The following local vLLM deployment will soon be replaced with the upstream vLLM code.
# For now, this https://github.com/aws-neuron/upstreaming-to-vllm/tree/v0.5.0-neuron is used in the Dockerfile from the AWS Neuron vLLM fork.
COPY vllm /vllm
RUN chmod -R u+w /vllm
# -----------------------------------------------------------------------------------

# Install vLLM with --no-deps and other dependencies
RUN python3 -m pip install --no-cache-dir -e /vllm && \
    pip install --no-cache-dir pynvml ml-dtypes==0.2.0

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


COPY vllm/examples/neuron_multi_nodel/neuron_multi_node_runner.py /usr/local/bin/neuron_multi_node_runner.py
COPY run.sh /usr/local/bin/run.sh
