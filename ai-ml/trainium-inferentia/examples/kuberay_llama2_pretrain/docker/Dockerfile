ARG REGION
FROM 763104351884.dkr.ecr.${REGION}.amazonaws.com/pytorch-training-neuronx:1.13.1-neuronx-py310-sdk2.17.0-ubuntu20.04

# Install Ray
# Note: For now, we install a Ray nightly until the required Trainium/XLA PR is included in official release
RUN pip3 install "ray[default] @ https://s3-us-west-2.amazonaws.com/ray-wheels/latest/ray-3.0.0.dev0-cp310-cp310-manylinux2014_x86_64.whl" aiohttp \
  && rm -fr /root/.cache

# Install dependencies for Llama2 pretraining example
RUN pip3 install wget awscli regex boto3 pyarrow transformers==4.31.0 tensorboard datasets \
  && rm -fr /root/.cache/

# Copy Llama2 pretraining example files into container and download tokenizer
COPY ./llama2_pretrain /llama2_pretrain
RUN cd /llama2_pretrain \
  && wget https://huggingface.co/NousResearch/Llama-2-7b-hf/resolve/main/tokenizer.model
WORKDIR /llama2_pretrain
