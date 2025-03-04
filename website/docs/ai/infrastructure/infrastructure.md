# Introduction

The AIoEKS foundational infrastructure lives in the `ai-ml/infrastructure` directory. This directory contains the base infrastructure and all its modules that allow composing an environment that supports experimentation, AI/ML training, LLM inference, model tracking, and more. 

In the directory is a `variables.tf` which contains all the variables used for the modules and sets them all to `false`. This enables the ability to deploy an empty environment with Karpenter and GPU and AWS Neuron node pools to enable accelerator utilization for advanced customization.

The reference `jark-stack` deploys an environment that facilitates quick AI/ML development by enabling Jupyterhub for experimentation, the KubeRay operator for training and inference, and Argo Workflows for pipelining as well as the various storage controllers and volumes. This allows deploying the `notebooks`, `training`, and `inference` blueprints in the `gen-ai` folder.   

Other blueprints use the same `infrastructure` base and selectively enable other components based on the needs of the blueprint. 
