ARG REGION
FROM 763104351884.dkr.ecr.${REGION}.amazonaws.com/pytorch-training-neuronx:1.13.1-neuronx-py310-sdk2.17.0-ubuntu20.04

# Install Ray
# Note: For now, we install an older Ray nightly and then install the trainium PR over top. Newer Ray nightlies result in errors (PR needs to be rebased?)
RUN pip3 install "ray[default] @ https://s3-us-west-2.amazonaws.com/ray-wheels/master/18b2cab6ca79220d1d0470a60b91b1eb95c1e4a6/ray-3.0.0.dev0-cp310-cp310-manylinux2014_x86_64.whl" aiohttp \
  && git clone https://github.com/ray-project/ray.git \
  && cd ray \
  && git checkout 18b2cab6ca79220d1d0470a60b91b1eb95c1e4a6 \
  && git pull origin pull/39130/head \
  && python3 ./python/ray/setup-dev.py -y --skip dashboard \
  && rm -fr /root/.cache

# Install dependencies for Llama2 pretraining example
RUN pip3 install wget awscli regex boto3 pyarrow transformers==4.31.0 tensorboard datasets \
  && rm -fr /root/.cache/

# Copy Llama2 pretraining example files into container and download tokenizer
COPY ./llama2_pretrain /llama2_pretrain
RUN cd /llama2_pretrain \
  && wget https://huggingface.co/NousResearch/Llama-2-7b-hf/resolve/main/tokenizer.model
WORKDIR /llama2_pretrain
