FROM public.ecr.aws/ubuntu/ubuntu:22.04_stable

# Install prereqs & utils
RUN apt-get update && apt-get install -y software-properties-common && add-apt-repository ppa:maveonair/helix-editor
RUN apt-get install -y gnupg git python3 python3-pip wget unzip vim helix

# Install Neuron system packages
RUN echo 'deb https://apt.repos.neuron.amazonaws.com jammy main' > /etc/apt/sources.list.d/neuron.list
RUN wget -qO - https://apt.repos.neuron.amazonaws.com/GPG-PUB-KEY-AMAZON-AWS-NEURON.PUB | apt-key add - && apt-get update
RUN apt-get install -y aws-neuronx-collectives=2.* aws-neuronx-runtime-lib=2.* aws-neuronx-tools=2.*
RUN echo "export PATH=/opt/aws/neuron/bin:\$PATH" >> /root/.bashrc
ENV PATH="${PATH}:/opt/aws/neuron/bin"

# Install Neuron pip packages
RUN pip3 install -U pip \
  && pip3 install torch-neuronx==2.* neuronx-distributed neuronx-cc==2.* --extra-index-url https://pip.repos.neuron.amazonaws.com

WORKDIR /neuron

# Install Optimum Neuron from source
RUN mkdir -p src && cd src \
  && git clone https://github.com/huggingface/optimum-neuron.git \
  && cd optimum-neuron \
  # && git checkout 281d9bb40347dad752b97cf71cbee17970858445 \
  && git checkout 493a134902c2cba33e456464156aefaa0fa9f67a \
  && pip3 install -e /neuron/src/optimum-neuron

RUN pip3 install peft trl
COPY ./assets /neuron
