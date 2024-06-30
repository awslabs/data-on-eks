# docker buildx build --platform=linux/amd64 -t triton-python-api:24.01-py3 -f Dockerfile .

ARG BASE_IMAGE=nvcr.io/nvidia/tritonserver
ARG BASE_IMAGE_TAG=24.01-py3

FROM ${BASE_IMAGE}:${BASE_IMAGE_TAG} as triton-python-api

# Maintainer label
LABEL maintainer="DoEKS"

# Switch back to a non-root user for the subsequent commands
USER $USER

RUN pip install --timeout=2000 "ray[serve]" numpy requests fastapi Pillow scipy accelerate

RUN find /opt/tritonserver/python -maxdepth 1 -type f -name \
    "tritonserver-*.whl" | xargs -I {} pip3 install --force-reinstall --upgrade {}[all]

# Set a working directory
WORKDIR /serve_app

# Copy your Ray Serve script into the container
COPY ray_serve_stablediffusion.py /serve_app/ray_serve_stablediffusion.py

# Copy Triton Server models
COPY ./models /serve_app/models

# Set the PYTHONPATH environment variable
ENV PYTHONPATH=/serve_app:$PYTHONPATH
