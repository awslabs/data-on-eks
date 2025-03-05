# Introduction

The AIoEKS foundational infrastructure lives in the `ai-ml/infrastructure` directory. This directory contains the base infrastructure and all its modules that allow composing an environment that supports experimentation, AI/ML training, LLM inference, model tracking, and more. 

In the directory is a `variables.tf` which contains all the parameters used to enable or disable desired modules (set to `false` by default). This enables the ability to deploy a bare environment with Karpenter and GPU and AWS Neuron nodepools to enable accelerator use and for further customization.

The reference `jark-stack` deploys an environment that facilitates quick AI/ML development by enabling Jupyterhub for experimentation, the KubeRay operator for training and inference using [Ray Clusters](https://docs.ray.io/en/latest/cluster/getting-started.html), Argo Workflows for automating workflows, and storage controllers and volumes. This allows deploying the `notebooks`, `training`, and `inference` blueprints in the `gen-ai` folder.   

Other blueprints use the same `infrastructure` base and selectively enable other components based on the needs of the blueprint. 
