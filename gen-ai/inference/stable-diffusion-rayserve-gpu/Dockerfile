# https://hub.docker.com/layers/rayproject/ray-ml/2.10.0-py310-gpu/images/sha256-4181ed53b0b25a758b155312ca6ab29a65cb78cd57296d42cfbe4806a2b77df4?context=explore
# docker buildx build --platform=linux/amd64 -t ray2.24.0-py310-gpu-stablediffusion:v1.0 -f Dockerfile .

# Use Ray base image
FROM docker.io/rayproject/ray:2.33.0-py311-gpu

# Maintainer label
LABEL maintainer="DoEKS"

# Set environment variables to non-interactive (this prevents some prompts)
ENV DEBIAN_FRONTEND=non-interactive

# Switch back to a non-root user for the subsequent commands
USER $USER

# Install Ray Serve and other Python packages with specific versions
RUN pip install --no-cache-dir requests torch "diffusers==0.29.2" "transformers==4.42.4" "accelerate==0.30.1"

# Set a working directory
WORKDIR /serve_app

# Copy your Ray Serve script into the container
# The serving script can moved to the ConfigMap, or copied in the container image
# COPY ray_serve_sd.py /serve_app/ray_serve_sd.py

# Set the PYTHONPATH environment variable
ENV PYTHONPATH=/serve_app:$PYTHONPATH
