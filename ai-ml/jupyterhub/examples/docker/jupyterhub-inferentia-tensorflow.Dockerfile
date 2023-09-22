# Base image with Python 3.10
FROM jupyter/datascience-notebook:python-3.10.10

USER root

# Install gnupg and other utilities
RUN apt-get update -y && \
    apt-get install --no-install-recommends -y gnupg

# Install Neuron packages and other utilities
RUN . /etc/os-release && \
    echo "deb https://apt.repos.neuron.amazonaws.com ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/neuron.list && \
    wget -qO - https://apt.repos.neuron.amazonaws.com/GPG-PUB-KEY-AMAZON-AWS-NEURON.PUB | apt-key add - && \
    apt-get update -y && \
    apt-get install --no-install-recommends -y \
    git \
    aws-neuronx-dkms=2.* \
    aws-neuronx-collectives=2.* \
    aws-neuronx-runtime-lib=2.* \
    aws-neuronx-tools=2.* \
    g++ \
    wget && \
    rm -rf /var/lib/apt/lists/* && \
    echo "export PATH=/opt/aws/neuron/bin:$PATH" >> ~/.bashrc

USER $NB_UID

# Install Python packages
RUN python -m pip install -U pip && \
    pip install ipykernel jupyter notebook environment_kernels wget awscli && \
    python -m ipykernel install --user --name aws_neuron_venv_tensorflow --display-name "Python (tensorflow-neuronx)" && \
    python -m pip config set global.extra-index-url https://pip.repos.neuron.amazonaws.com && \
    python -m pip install neuronx-cc==2.* tensorflow-neuronx
