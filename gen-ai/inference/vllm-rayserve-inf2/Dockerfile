# Use a specific tag for the base image
FROM rayproject/ray:2.32.0-py311

# Combine ENV statements
ENV DEBIAN_FRONTEND=noninteractive \
    DEBCONF_NONINTERACTIVE_SEEN=true \
    LD_LIBRARY_PATH=/home/ray/anaconda3/lib:$LD_LIBRARY_PATH \
    PATH=/opt/aws/neuron/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PJRT_DEVICE=NEURON \
    VLLM_TARGET_DEVICE=neuron

# Switch to root user for system-level operations
USER root

# Combine RUN commands and use multi-line format for readability
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates autoconf automake build-essential git gperf \
        libre2-dev libssl-dev libtool libcurl4-openssl-dev libb64-dev \
        libgoogle-perftools-dev patchelf python3-dev python3-pip \
        python3-setuptools rapidjson-dev scons software-properties-common \
        pkg-config unzip wget zlib1g-dev libarchive-dev libxml2-dev \
        libnuma-dev gnupg2 && \
    rm -rf /var/lib/apt/lists/* && \
    wget -qO - https://apt.repos.neuron.amazonaws.com/GPG-PUB-KEY-AMAZON-AWS-NEURON.PUB | gpg --no-default-keyring --keyring ./aws_neuron_keyring.gpg --import && \
    gpg --no-default-keyring --keyring ./aws_neuron_keyring.gpg --export > /etc/apt/trusted.gpg.d/aws_neuron.gpg && \
    add-apt-repository -y "deb https://apt.repos.neuron.amazonaws.com jammy main" && \
    apt-get update && \
    apt-get install -y aws-neuronx-collectives=2.* aws-neuronx-runtime-lib=2.* aws-neuronx-tools=2.* && \
    rm -rf /var/lib/apt/lists/*

# Combine pip installations
RUN pip3 config set global.extra-index-url https://pip.repos.neuron.amazonaws.com && \
    pip3 install --no-cache-dir awscli neuronx-cc==2.* --pre torch-neuronx==2.1.* torchvision transformers-neuronx pynvml ray

# Copy patch file before cloning and patching vllm
COPY patches/vllm_v0.5.0_neuron.patch /tmp/vllm_v0.5.0_neuron.patch

# Clone vllm, apply patch, and install
RUN git clone --depth 1 --branch v0.5.0 https://github.com/vllm-project/vllm.git && \
    cd vllm && \
    git apply --ignore-space-change --ignore-whitespace /tmp/vllm_v0.5.0_neuron.patch && \
    pip3 install --no-cache-dir -U -r requirements-neuron.txt && \
    pip3 install --no-cache-dir .

# Switch back to the default user if necessary
# USER ray
