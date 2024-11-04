# Use the base image
FROM rayproject/ray:2.32.0-py311

# Maintainer label
LABEL maintainer="DoEKS"

# Set environment variables to non-interactive (this prevents some prompts)
ENV DEBIAN_FRONTEND=non-interactive \
    LD_LIBRARY_PATH=/home/ray/anaconda3/lib:$LD_LIBRARY_PATH

# Set the working directory
WORKDIR /app

# Install vLLM and other dependencies in a single RUN command to reduce layers
RUN pip install vllm==0.6.3 huggingface_hub==0.26.2

# Copy the serving script into the container
COPY vllm_serve.py /app/vllm_serve.py 
COPY vllm_openai_serve.py /app/vllm_openai_serve.py
