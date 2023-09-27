<<<<<<< HEAD
<<<<<<< HEAD
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
<<<<<<< HEAD

RUN \
  . /etc/os-release && \
  echo "deb https://apt.repos.neuron.amazonaws.com ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/neuron.list && \
  wget -qO - https://apt.repos.neuron.amazonaws.com/GPG-PUB-KEY-AMAZON-AWS-NEURON.PUB | apt-key add - && \
  apt-get update -y && \
  apt-get install aws-neuronx-dkms=2.* aws-neuronx-collectives=2.* aws-neuronx-runtime-lib=2.* aws-neuronx-tools=2.* -y

# Switch back to jovyan user for Python package installations
USER jovyan

# Set pip repository pointing to the Neuron repository and install required Python packages
RUN pip config set global.extra-index-url https://pip.repos.neuron.amazonaws.com && \
    pip install wget awscli neuronx-cc==2.* torch-neuronx torchvision ipykernel environment_kernels && \
    # Install new Jupyter Notebook kernel
    python -m ipykernel install --user --name aws_neuron_venv_pytorch --display-name "Python (torch-neuronx)"

# Add Neuron path to PATH
ENV PATH /opt/aws/neuron/bin:$PATH
=======
# TBD: Create image installing pytorch neuron packages - https://awsdocs-neuron.readthedocs-hosted.com/en/latest/general/setup/neuron-setup/pytorch/neuronx/ubuntu/torch-neuronx-ubuntu22.html#setup-torch-neuronx-ubuntu22
FROM jupyter/datascience-notebook:python-3.10.10
=======
# Use the Jupyter base notebook with Python 3.10 as the base image
FROM jupyter/base-notebook:python-3.10
>>>>>>> 42ea3177 (fix: JupyterHub Images (#326))

# Maintainer label
LABEL maintainer="DoEKS"

# Set environment variables to non-interactive (this prevents some prompts)
ENV DEBIAN_FRONTEND=non-interactive

# Switch to root to add Neuron repo and install necessary packages
USER root

# Install gnupg and other required packages
RUN apt-get update -y && \
    apt-get install -y gnupg git g++ 
=======
>>>>>>> e6f3535e (feat: Updates for jupyterhub blueprint for observability (#327))

RUN \
  . /etc/os-release && \
  echo "deb https://apt.repos.neuron.amazonaws.com ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/neuron.list && \
  wget -qO - https://apt.repos.neuron.amazonaws.com/GPG-PUB-KEY-AMAZON-AWS-NEURON.PUB | apt-key add - && \
  apt-get update -y && \
  apt-get install aws-neuronx-dkms=2.* aws-neuronx-collectives=2.* aws-neuronx-runtime-lib=2.* aws-neuronx-tools=2.* -y

# Switch back to jovyan user for Python package installations
USER jovyan

<<<<<<< HEAD
ENTRYPOINT ["jupyterhub-singleuser"]
>>>>>>> fce4eb45 (Jupyterhub blog (#321))
=======
# Set pip repository pointing to the Neuron repository and install required Python packages
RUN pip config set global.extra-index-url https://pip.repos.neuron.amazonaws.com && \
    pip install wget awscli neuronx-cc==2.* torch-neuronx torchvision ipykernel environment_kernels && \
    # Install new Jupyter Notebook kernel
    python -m ipykernel install --user --name aws_neuron_venv_pytorch --display-name "Python (torch-neuronx)"

# Add Neuron path to PATH
ENV PATH /opt/aws/neuron/bin:$PATH
<<<<<<< HEAD
>>>>>>> 42ea3177 (fix: JupyterHub Images (#326))
=======
>>>>>>> e6f3535e (feat: Updates for jupyterhub blueprint for observability (#327))
