ARG REGION

# Base image: PyTorch training image for NeuronX
FROM public.ecr.aws/neuron/pytorch-training-neuronx:2.1.2-neuronx-py310-sdk2.20.0-ubuntu20.04

# Install Ray for distributed computing
RUN pip3 install aiohttp \
    && rm -rf /root/.cache

# Install additional Python dependencies
RUN pip3 install wget awscli regex boto3 pyarrow \
    && rm -rf /root/.cache/

# Copy the Llama2 training code into the container
# (Separate layer to rebuild only if the code changes)
COPY ./llama3.1_pretraining /llama3.1_pretraining 

# Make shell scripts executable
RUN chmod +x /llama3.1_pretraining/run_llama3.1_8b.sh

# Set the working directory
WORKDIR /llama3.1_pretraining

# Installing the requirements 
RUN pip install -r requirements.txt --extra-index-url https://pip.repos.neuron.amazonaws.com 

# Installing the requirements 
# RUN pip install transformers==4.32.1 --no-warn-conflicts

# # Installing neuronx-cc 2.0+
RUN pip install neuronx-cc==2.* --extra-index-url https://pip.repos.neuron.amazonaws.com -U

# Replacing libneuronxla with torch_neuronx for neuron parallel compile in Ray config file
COPY ./config.py /usr/local/lib/python3.10/site-packages/ray/train/torch/xla/config.py
