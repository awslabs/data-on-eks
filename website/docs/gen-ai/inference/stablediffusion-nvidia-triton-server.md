---
title: Stable Diffusion with NVIDIA Triton Inference Server and Ray Serve
sidebar_position: 8
---

# Deploying Stable Diffusion with NVIDIA Triton Inference Server, Ray Serve and Gradio

This pattern is based on the [Serving models with Triton Server in Ray Serve](https://docs.ray.io/en/latest/serve/tutorials/triton-server-integration.html) example from the Ray documentation. The deployed model is *Stable Diffusion v1-4* from the *Computer Vision & Learning research group* ([CompVis](https://huggingface.co/CompVis)).

## What is NVIDIA Triton Server

:::info

Section under construction

:::

## Deploying the Solution

To deploy the solution, you can follow the same steps explained in the [*Stable Diffusion on GPU* pattern](https://awslabs.github.io/data-on-eks/docs/gen-ai/inference/stablediffusion-gpus), just remember to use `/data-on-eks/gen-ai/inference/stable-diffusion-rayserve-nvidia-triton-server` where it says `/data-on-eks/gen-ai/inference/stable-diffusion-rayserve-gpu`.

The `RayService` manifest references a pre-built Docker image, hosted on a public Amazon ECR repository, which already includes everything needed to run inference.

Should you wish to build it yourself as an exercise, you can perform the following steps:

1. **Launch and connecto to an Amazon EC2 G5 instance**
1. **Build and export the model**
1. **Build the model repository**
1. **Build the Docker image**
1. **Push the newly built image to an Amazon ECR repository**

## Launch an Amazon EC2 G5 instance

1. Select a Deep Learning AMI, e.g. *Deep Learning OSS Nvidia Driver AMI GPU PyTorch*
1. Select a `g5.12xlarge` instance (**note**: at least `12xlarge`)
1. Set the *Root volume* size to 300 GB

**Important Note**: we selected `g5`, because we need to build our model on the same instance type as the one where it will run, and our Ray cluster runs on Amazon EC2 G5 instances.

You can connect to ig by e.g. [using an SSH client](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-linux-inst-ssh.html). 

## Build and export the model

Install the dependencies:

```bash
pip install --timeout=2000 torch diffusers transformers onnx numpy
```

Clone the repository:

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

Move to the blueprint directory and execute `model_definition.py` file:

```bash
cd ./data-on-eks/gen-ai/inference/stable-diffusion-rayserve-nvidia-triton-server
python3 model_definition.py
```

The outputs are 2 files: `vae.onnx` and `encoder.onnx`. Convert the `vae.onnx` model to the TensorRT engine serialized file:

```bash
/usr/src/tensorrt/bin/trtexec  --onnx=vae.onnx --saveEngine=vae.plan --minShapes=latent_sample:1x4x64x64 --optShapes=latent_sample:4x4x64x64 --maxShapes=latent_sample:8x4x64x64 --fp16
```

## Build the model repository

The Triton Inference Server requires a [model repository](https://github.com/triton-inference-server/server/blob/main/docs/user_guide/model_repository.md) with a specific structure. Execute the following commands to build it, and copy over the necessary files:

```bash
mkdir -p models/vae/1
mkdir -p models/text_encoder/1
mkdir -p models/stable_diffusion/1
mv vae.plan models/vae/1/model.plan
mv encoder.onnx models/text_encoder/1/model.onnx
curl -L "https://raw.githubusercontent.com/triton-inference-server/tutorials/main/Conceptual_Guide/Part_6-building_complex_pipelines/model_repository/pipeline/1/model.py" > models/stable_diffusion/1/model.py
curl -L "https://raw.githubusercontent.com/triton-inference-server/tutorials/main/Conceptual_Guide/Part_6-building_complex_pipelines/model_repository/pipeline/config.pbtxt" > models/stable_diffusion/config.pbtxt
curl -L "https://raw.githubusercontent.com/triton-inference-server/tutorials/main/Conceptual_Guide/Part_6-building_complex_pipelines/model_repository/text_encoder/config.pbtxt" > models/text_encoder/config.pbtxt
curl -L "https://raw.githubusercontent.com/triton-inference-server/tutorials/main/Conceptual_Guide/Part_6-building_complex_pipelines/model_repository/vae/config.pbtxt" > models/vae/config.pbtxt
```

Copy the Ray Serve `ray_serve_stablediffusion.py` file and the model repository under a new `serve_app` directory:

```bash
mkdir /serve_app
cp ray_serve_stablediffusion.py /serve_app/ray_serve_stablediffusion.py
cp models /serve_app/models
```

You are ready to build the image.

## Build the Docker image

```bash
docker build -t triton-python-api:24.01-py3 -f Dockerfile .
```

## Push the newly built image to an Amazon ECR repository

You can publish your image to either a public or private Amazon ECR repository. Follow e.g. [this guideline](https://docs.aws.amazon.com/AmazonECR/latest/public/docker-push-ecr-image.html) to publish to a public one.

To run your image on the Ray cluster, you need to replace the exiting image references in `ray-serve-stablediffusion.yaml` with yours.
