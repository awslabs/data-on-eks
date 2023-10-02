# Use the PyTorch Neuron base image
FROM 763104351884.dkr.ecr.us-west-2.amazonaws.com/pytorch-training-neuron:1.11.0-neuron-py38-sdk2.4.0-ubuntu20.04

# Set the working directory inside the container
WORKDIR /app

# Clone the AWS Neuron Samples repository
RUN git clone https://github.com/aws-neuron/aws-neuron-samples.git /app/aws-neuron-samples

# Copy the required files into the container
RUN mkdir -p /app/dockerbuild
RUN cp /app/aws-neuron-samples/torch-neuronx/training/mnist_mlp/train_torchrun.py /app/dockerbuild
RUN cp /app/aws-neuron-samples/torch-neuronx/training/mnist_mlp/model.py /app/dockerbuild

# Set the working directory for running the application
WORKDIR /app/dockerbuild

# Cleanup by removing the cloned repository and unnecessary files
RUN rm -rf /app/aws-neuron-samples
