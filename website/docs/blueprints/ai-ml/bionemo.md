---
sidebar_position: 2
sidebar_label: Bionemo on EKS
---
import CollapsibleContent from '../../../src/components/CollapsibleContent';

# Bionemo on EKS

:::caution
This blueprint should be considered as experimental and should only be used for proof of concept.
:::

:::info
As part of our ongoing efforts to make this blueprint more enterprise-ready, we are actively working on adding several key functionalities. This includes cost management with Kubecost, advanced observability with Amazon Managed Prometheus, and Grafana, as well as improved security and data governance using tools such as IRSA. If you have specific requirements or suggestions for this blueprint, please feel free to open an issue on our GitHub repository.
:::

## Introduction

[NVIDIA Bionemo](https://www.nvidia.com/en-us/clara/bionemo/) is a generative AI platform for drug discovery that simplifies and accelerates the training of models using your own data and scaling the deployment of models for drug discovery applications. BioNeMo offers the quickest path to both AI model development and deployment, accelerating the journey to AI-powered drug discovery. It has a growing community of users and contributors, and is actively maintained and developed by the NVIDIA.

Since Bionemo is containerized, we can deploy it to Amazon Sagemaker, AWS ParallelCluster, Amazon ECS and Amazon EKS. In this solution we are going to focus on running Bionemo on Amazon EKS. 

*Source: https://blogs.nvidia.com/blog/bionemo-on-aws-generative-ai-drug-discovery/*

## Bionemo on Kubernetes

In order to deploy Bionemo on Kubernetes, we need 4 major components. 

1) [**Kubeflow Training Operator**](https://www.kubeflow.org/docs/components/training/)
2) [**MPI Operator**](https://github.com/kubeflow/mpi-operator)
3) [**NVIDIA Device Plugin**](https://github.com/NVIDIA/k8s-device-plugin)
4) [**FSx for Lustre CSI Driver**](https://docs.aws.amazon.com/eks/latest/userguide/fsx-csi.html)


## Deploying the Example

In this example we are going to deploy an Amazon EKS cluster and run a data preparation job and a distributed model training job.

<CollapsibleContent header={<h3><span>Pre-requisites</span></h3>}>

Ensure that you have installed the following tools on your machine.

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [python3](https://www.python.org/)

</CollapsibleContent>

<CollapsibleContent header={<h3><span>Deploy the EKS Cluster with KubeRay Operator</span></h3>}>

#### Clone the repository

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

#### Initialize Terraform

Navigate into the example directory

```bash
cd data-on-eks/ai-ml/bionemo
```

#### Run the install script

Use the provided helper script `install.sh` to run the terraform init and apply commands. By default the script deploys EKS cluster to `us-west-2` region. Update `variables.tf` to change the region. This is also the time to update any other input variables or make any other changes to the terraform template.


```bash
./install .sh
```

</CollapsibleContent>

<CollapsibleContent header={<h3><span>Verify Deployment</span></h3>}>

Update local kubeconfig so we can access kubernetes cluster

```bash
aws eks update-kubeconfig --name bionemo-cluster #or whatever you used for EKS cluster name
```

First, lets verify that we have worker nodes running in the cluster.

```bash
kubectl get nodes
```
:::info
```bash
NAME                                          STATUS   ROLES    AGE   VERSION
ip-100-64-243-22.us-west-2.compute.internal   Ready    <none>   47h   v1.29.0-eks-5e0fdde
ip-100-64-70-74.us-west-2.compute.internal    Ready    <none>   47h   v1.29.0-eks-5e0fdde
```
:::

Next, lets verify all the pods are running.

```bash
kubectl get pods -A
```
Make sure mpi-operator, training-operator, nvidia-device-plungin and fsx-csi-controller pods are running and healthy.

#### Run bionemo jobs

Once we are sure everything is working, we can start submitting jobs to our clusters.

First job we are going to run is uniref50-job which will download and split the data for efficient processing.

```bash
cd training
kubectl apply -f uniref50-job.yaml
```

If you look at the yaml manifest you would see it is a kubernetes Job, which simply runs a python script within the bionemo container.

This process takes relatively a long time (~15-16 hours). In order to see if it is working check the logs from this pod:

```bash
kubectl logs uniref50-download-xnz42
[NeMo I 2024-02-26 23:02:20 preprocess:289] Download and preprocess of UniRef50 data does not currently use GPU. Workstation or CPU-only instance recommended.
[NeMo I 2024-02-26 23:02:20 preprocess:115] Data processing can take an hour or more depending on system resources.
[NeMo I 2024-02-26 23:02:20 preprocess:117] Downloading file from https://ftp.uniprot.org/pub/databases/uniprot/uniref/uniref50/uniref50.fasta.gz...
[NeMo I 2024-02-26 23:02:20 preprocess:75] Downloading file to /fsx/raw/uniref50.fasta.gz...
[NeMo I 2024-02-26 23:08:33 preprocess:89] Extracting file to /fsx/raw/uniref50.fasta...
[NeMo I 2024-02-26 23:12:46 preprocess:311] UniRef50 data processing complete.
[NeMo I 2024-02-26 23:12:46 preprocess:313] Indexing UniRef50 dataset.
[NeMo I 2024-02-26 23:16:21 preprocess:319] Writing processed dataset files to /fsx/processed...
[NeMo I 2024-02-26 23:16:21 preprocess:255] Creating train split...
```

After this job is done, our processed dataset will be placed in /fsx/processed directory.

After this step we can run the training job by running:

```bash
cd training
kubectl apply -f esm1nv_pretrain-job.yaml
```

This manifest uses kubeflow's Pytorch training CRD. There are bunch of parameters within this manifest that could be modified. See [Bionemo's Docs](https://docs.nvidia.com/bionemo-framework/latest/notebooks/model_training_esm1nv.html) for detailed explanations of each parameter and how to tune them.

#### Clean up
Use the provided helper script `cleanup.sh` to tear down EKS cluster and other AWS resources.

```bash
cd ../../
./cleanup.sh
```

</CollapsibleContent>
