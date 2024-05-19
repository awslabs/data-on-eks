ARG REGION
FROM 763104351884.dkr.ecr.${REGION}.amazonaws.com/pytorch-training-neuronx:1.13.1-neuronx-py310-sdk2.17.0-ubuntu20.04

# Install Ray 2.22.0
RUN pip3 install ray[default]==2.22.0 aiohttp \
  && rm -fr /root/.cache

# Install dependencies for Llama2 pretraining example
RUN pip3 install wget awscli regex boto3 pyarrow transformers==4.31.0 tensorboard datasets \
  && rm -fr /root/.cache/

# Copy Llama2 pretraining example files into container and download tokenizer
COPY ./llama2_pretrain /llama2_pretrain
RUN chmod +x /llama2_pretrain/launch_precompile_job.sh /llama2_pretrain/launch_training_job.sh \
  && cd /llama2_pretrain \
  && wget https://huggingface.co/NousResearch/Llama-2-7b-hf/resolve/main/tokenizer.model

WORKDIR /llama2_pretrain
