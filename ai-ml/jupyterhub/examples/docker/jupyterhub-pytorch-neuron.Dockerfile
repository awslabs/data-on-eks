# Use the Jupyter base notebook with Python 3.10 as the base image
FROM jupyter/base-notebook:python-3.10

# Maintainer label
LABEL maintainer="DoEKS"

# Set environment variables to non-interactive (this prevents some prompts)
ENV DEBIAN_FRONTEND=non-interactive

# Switch to root to add Neuron repo and install necessary packages
USER root

# Install gnupg and other required packages
RUN apt-get update -y && \
    apt-get install -y gnupg git g++

RUN \
  . /etc/os-release && \
  echo "deb https://apt.repos.neuron.amazonaws.com ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/neuron.list && \
  wget -qO - https://apt.repos.neuron.amazonaws.com/GPG-PUB-KEY-AMAZON-AWS-NEURON.PUB | apt-key add - && \
  apt-get update -y && \
  apt-get install aws-neuronx-collectives=2.* aws-neuronx-runtime-lib=2.* aws-neuronx-tools=2.* -y

# Switch back to jovyan user for Python package installations
USER jovyan

# Set pip repository pointing to the Neuron repository and install required Python packages
RUN pip config set global.extra-index-url https://pip.repos.neuron.amazonaws.com && \
    pip install transformers-neuronx sentencepiece transformers wget awscli ipywidgets neuronx-cc==2.* torch-neuronx torchvision ipykernel environment_kernels && \
    # Install new Jupyter Notebook kernel
    python -m ipykernel install --user --name aws_neuron_venv_pytorch --display-name "Python (torch-neuronx)"

# Add Neuron path to PATH
ENV PATH /opt/aws/neuron/bin:$PATH
