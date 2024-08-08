# docker build -t ray2.32.0-neuron-vllm .
FROM rayproject/ray:2.32.0-py311

ENV DEBIAN_FRONTEND=noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN=true

RUN sudo apt-get update \
      && sudo apt-get install -y --no-install-recommends \
            ca-certificates \
            autoconf \
            automake \
            build-essential \
            git \
            gperf \
            libre2-dev \
            libssl-dev \
            libtool \
            libcurl4-openssl-dev \
            libb64-dev \
            libgoogle-perftools-dev \
            patchelf \
            python3-dev \
            python3-pip \
            python3-setuptools \
            rapidjson-dev \
            scons \
            software-properties-common \
            pkg-config \
            unzip \
            wget \
            zlib1g-dev \
            libarchive-dev \
            libxml2-dev \
            libnuma-dev \
            wget \
            gnupg2 \
      && sudo rm -rf /var/lib/apt/lists/*

RUN sudo wget -qO - https://apt.repos.neuron.amazonaws.com/GPG-PUB-KEY-AMAZON-AWS-NEURON.PUB > ./GPG-PUB-KEY-AMAZON-AWS-NEURON.PUB
RUN sudo gpg --no-default-keyring --keyring ./aws_neuron_keyring.gpg --import  ./GPG-PUB-KEY-AMAZON-AWS-NEURON.PUB
RUN sudo gpg --no-default-keyring --keyring ./aws_neuron_keyring.gpg  --export >  ./aws_neuron.gpg
RUN sudo mv ./aws_neuron.gpg /etc/apt/trusted.gpg.d/
RUN sudo rm ./GPG-PUB-KEY-AMAZON-AWS-NEURON.PUB

RUN sudo add-apt-repository -y  "deb https://apt.repos.neuron.amazonaws.com jammy main"
RUN sudo apt-get -y update

RUN sudo apt-get -y install aws-neuronx-collectives=2.*
RUN sudo apt-get -y install aws-neuronx-runtime-lib=2.*
RUN sudo apt-get -y install aws-neuronx-tools=2.*

RUN pip3 config set global.extra-index-url https://pip.repos.neuron.amazonaws.com
RUN pip3 install awscli
RUN pip3 install neuronx-cc==2.* --pre torch-neuronx==2.1.* torchvision transformers-neuronx

ENV LD_LIBRARY_PATH=/home/ray/anaconda3/lib:$LD_LIBRARY_PATH
ENV PATH=/opt/aws/neuron/bin:$PATH
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PJRT_DEVICE=NEURON

ENV VLLM_TARGET_DEVICE=neuron
RUN git clone https://github.com/vllm-project/vllm.git
RUN cd vllm && git checkout v0.5.0
COPY patches/vllm_v0.5.0_neuron.patch vllm/vllm_v0.5.0_neuron.patch
RUN cd vllm && git apply --ignore-space-change --ignore-whitespace vllm_v0.5.0_neuron.patch \
      && pip3 install -U -r requirements-neuron.txt && pip3 install .
RUN pip3 install pynvml
RUN pip3 install ray

WORKDIR /serve_app

COPY vllm_asyncllmengine.py /serve_app/vllm_asyncllmengine.py

CMD ["/bin/bash"]