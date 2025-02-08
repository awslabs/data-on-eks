# Use the base image
FROM rayproject/ray:2.41.0-py310-cu118 AS base

# Maintainer label
LABEL maintainer="DoEKS"

# Set environment variables to non-interactive (this prevents some prompts)
ENV DEBIAN_FRONTEND=non-interactive

# Set LD_LIBRARY_PATH to include the directory with libpython3.10.so.1.0
ENV LD_LIBRARY_PATH=/home/ray/anaconda3/lib:$LD_LIBRARY_PATH

# Set the working directory
WORKDIR /app

# Install vLLM and other dependencies in a single RUN command to reduce layers
RUN pip install vllm==0.7.0 huggingface_hub==0.27.1
