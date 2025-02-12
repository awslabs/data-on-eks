FROM 763104351884.dkr.ecr.us-east-2.amazonaws.com/huggingface-pytorch-training-neuronx:2.1.2-transformers4.43.2-neuronx-py310-sdk2.20.0-ubuntu20.04


# Install HuggingFace trl library to workaround issue https://github.com/huggingface/optimum-neuron/issues/761
RUN pip3 install -U pip \
  && pip3 install trl==0.11.4

WORKDIR /neuron

COPY ./assets /neuron
