ARG REGION

# Base image: PyTorch training image for NeuronX
FROM public.ecr.aws/neuron/pytorch-training-neuronx:1.13.1-neuronx-py310-sdk2.18.2-ubuntu20.04

# Install Ray for distributed computing
RUN pip3 install ray[default]==2.22.0 aiohttp \
    && rm -rf /root/.cache

# Install additional Python dependencies
RUN pip3 install wget awscli regex boto3 pyarrow transformers==4.31.0 tensorboard datasets \
    && rm -rf /root/.cache/

# Copy the Llama2 training code into the container
# (Separate layer to rebuild only if the code changes)
COPY ./llama2_pretrain /llama2_pretrain

# Make shell scripts executable
RUN chmod +x /llama2_pretrain/launch_precompile_job.sh /llama2_pretrain/launch_training_job.sh

# Download tokenizer model directly into the working directory
# (Separate layer to rebuild only if the model changes)
RUN cd /llama2_pretrain \
    && wget https://huggingface.co/NousResearch/Llama-2-7b-hf/resolve/main/tokenizer.model

# Set the working directory
WORKDIR /llama2_pretrain
