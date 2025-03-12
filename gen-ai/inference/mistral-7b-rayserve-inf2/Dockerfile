# https://hub.docker.com/layers/rayproject/ray/2.11.0-py310/images/sha256-de798e487b76a8f2412c718c43c5f342b3eb05e0705a71325102904cd27c3613?context=explore
FROM rayproject/ray:2.22.0-py310

# Maintainer label
LABEL maintainer="DoEKS"

# Set environment variables to non-interactive (this prevents some prompts)
ENV DEBIAN_FRONTEND=non-interactive

# Switch to root to add Neuron repo and install necessary packages
USER root

# Set up the Neuron repository and install Neuron packages
RUN . /etc/os-release && \
    sudo echo "deb https://apt.repos.neuron.amazonaws.com ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/neuron.list && \
    sudo wget -qO - https://apt.repos.neuron.amazonaws.com/GPG-PUB-KEY-AMAZON-AWS-NEURON.PUB | apt-key add - && \
    sudo apt-get update -y && \
    sudo apt-get install aws-neuronx-dkms aws-neuronx-collectives=2.* aws-neuronx-runtime-lib=2.* aws-neuronx-tools=2.* -y && \
    sudo apt-get clean

# Switch back to a non-root user for the subsequent commands
USER $USER

# Set pip repository pointing to the Neuron repository and install required Python packages
RUN pip config set global.extra-index-url https://pip.repos.neuron.amazonaws.com && \
    pip install wget awscli regex neuronx-cc==2.* torch-neuronx torchvision transformers-neuronx sentencepiece transformers

# Add Neuron path to PATH
ENV PATH /opt/aws/neuron/bin:$PATH

# Set LD_LIBRARY_PATH to include the directory with libpython3.10.so.1.0
ENV LD_LIBRARY_PATH /home/ray/anaconda3/lib:$LD_LIBRARY_PATH

WORKDIR /serve_app

COPY ray_serve_mistral.py /serve_app/ray_serve_mistral.py
