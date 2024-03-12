---
sidebar_position: 3
sidebar_label: BioNeMo on EKS
---
import CollapsibleContent from '../../../src/components/CollapsibleContent';

# BioNeMo on EKS

:::caution
This blueprint should be considered as experimental and should only be used for proof of concept.
:::


## Introduction

[NVIDIA BioNeMo](https://www.nvidia.com/en-us/clara/bionemo/) is a generative AI platform for drug discovery that simplifies and accelerates the training of models using your own data and scaling the deployment of models for drug discovery applications. BioNeMo offers the quickest path to both AI model development and deployment, accelerating the journey to AI-powered drug discovery. It has a growing community of users and contributors, and is actively maintained and developed by the NVIDIA.

Given its containerized nature, BioNeMo finds versatility in deployment across various environments such as Amazon Sagemaker, AWS ParallelCluster, Amazon ECS, and Amazon EKS. This solution, however, zeroes in on the specific deployment of BioNeMo on Amazon EKS.

*Source: https://blogs.nvidia.com/blog/bionemo-on-aws-generative-ai-drug-discovery/*

## Deploying BioNeMo on Kubernetes

This blueprint leverages three major components for its functionality. The NVIDIA Device Plugin facilitates GPU usage, FSx stores training data, and the Kubeflow Training Operator manages the actual training process.

1) [**Kubeflow Training Operator**](https://www.kubeflow.org/docs/components/training/)
2) [**NVIDIA Device Plugin**](https://github.com/NVIDIA/k8s-device-plugin)
3) [**FSx for Lustre CSI Driver**](https://docs.aws.amazon.com/eks/latest/userguide/fsx-csi.html)


In this blueprint, we will deploy an Amazon EKS cluster and execute both a data preparation job and a distributed model training job.

<CollapsibleContent header={<h3><span>Pre-requisites</span></h3>}>

Ensure that you have installed the following tools on your local machine or the machine you are using to deploy the Terraform blueprint, such as Mac, Windows, or Cloud9 IDE:

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [python3](https://www.python.org/)

</CollapsibleContent>

<CollapsibleContent header={<h3><span>Deploy the blueprint</span></h3>}>

#### Clone the repository

First, clone the repository containing the necessary files for deploying the blueprint. Use the following command in your terminal:

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

#### Initialize Terraform

Navigate into the directory specific to the blueprint you want to deploy. In this case, we're interested in the BioNeMo blueprint, so navigate to the appropriate directory using the terminal:

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
aws eks update-kubeconfig --name bionemo-on-eks #or whatever you used for EKS cluster name
```

Since there is no helm chart for Training Operator, we have to manually install the package. If a helm chart gets build by training-operator team, we 
will incorporate it to the terraform-aws-eks-data-addons repository.

Install Kubeflow Training Operator:
```bash
kubectl apply -k "github.com/kubeflow/training-operator/manifests/overlays/standalone?ref=v1.7.0"
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
...
```
:::

Next, lets verify all the pods are running.

```bash
kubectl get pods -A
```
Make sure training-operator, nvidia-device-plugin and fsx-csi-controller pods are running and healthy.

</CollapsibleContent>


### Run BioNeMo Training jobs

Once you've ensured that all components are functioning properly, you can proceed to submit jobs to your clusters.

#### Step1: Initiate the Uniref50 Data Preparation Task:

The first task, named the `uniref50-job.yaml`, involves downloading and partitioning the data to enhance processing efficiency. This task specifically retrieves the `uniref50 dataset` and organizes it within the FSx for Lustre Filesystem. This structured layout is designed for training, testing, and validation purposes. You can learn more about the uniref dataset [here](https://www.uniprot.org/help/uniref).

To execute this job, navigate to the `examples\training` directory and deploy the `uniref50-job.yaml` manifest using the following commands:

```bash
cd training
kubectl apply -f uniref50-job.yaml
```

:::info

It's important to note that this task requires a significant amount of time, typically ranging from 50 to 60 hours. 

:::

To verify its progress, examine the logs generated by the corresponding pod:


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

After finishing this task, the processed dataset will be saved in the `/fsx/processed` directory. Once this is done, we can move forward and start the `pre-training` job by running the following command:

Following this, we can proceed to execute the pre-training job by running:

```bash
cd training
kubectl apply -f esm1nv_pretrain-job.yaml
```

This configuration utilizes Kubeflow's PyTorch training Custom Resource Definition (CRD). Within this manifest, various parameters are available for customization. For detailed insights into each parameter and guidance on fine-tuning, you can refer to [BioNeMo's documentation](https://docs.nvidia.com/bionemo-framework/latest/notebooks/model_training_esm1nv.html).

According to the Training Operator's documentation, the primary process is labeled as `...worker-0`. 

To track the progress of this process, follow these steps:

```bash
kubectl logs esm1nv-pretraining-worker-0

Epoch 0:   7%|▋         | 73017/1017679 [00:38<08:12, 1918.0%
```

Additionally, for comprehensive monitoring, you have the option to connect to your nodes through the EC2 console using Session Manager. Execute the command nvidia-smi to ensure optimal GPU utilization across all resources.

```bash
sh-4.2$ nvidia-smi
Thu Mar  7 16:31:01 2024
+---------------------------------------------------------------------------------------+
| NVIDIA-SMI 535.129.03             Driver Version: 535.129.03   CUDA Version: 12.2     |
|-----------------------------------------+----------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |         Memory-Usage | GPU-Util  Compute M. |
|                                         |                      |               MIG M. |
|=========================================+======================+======================|
|   0  Tesla V100-SXM2-16GB           On  | 00000000:00:17.0 Off |                    0 |
| N/A   51C    P0              80W / 300W |   3087MiB / 16384MiB |    100%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+
|   1  Tesla V100-SXM2-16GB           On  | 00000000:00:18.0 Off |                    0 |
| N/A   44C    P0              76W / 300W |   3085MiB / 16384MiB |    100%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+
|   2  Tesla V100-SXM2-16GB           On  | 00000000:00:19.0 Off |                    0 |
| N/A   43C    P0              77W / 300W |   3085MiB / 16384MiB |    100%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+
|   3  Tesla V100-SXM2-16GB           On  | 00000000:00:1A.0 Off |                    0 |
| N/A   52C    P0              77W / 300W |   3085MiB / 16384MiB |    100%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+
|   4  Tesla V100-SXM2-16GB           On  | 00000000:00:1B.0 Off |                    0 |
| N/A   49C    P0              79W / 300W |   3085MiB / 16384MiB |    100%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+
|   5  Tesla V100-SXM2-16GB           On  | 00000000:00:1C.0 Off |                    0 |
| N/A   44C    P0              74W / 300W |   3085MiB / 16384MiB |    100%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+
|   6  Tesla V100-SXM2-16GB           On  | 00000000:00:1D.0 Off |                    0 |
| N/A   44C    P0              78W / 300W |   3085MiB / 16384MiB |    100%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+
|   7  Tesla V100-SXM2-16GB           On  | 00000000:00:1E.0 Off |                    0 |
| N/A   50C    P0              79W / 300W |   3085MiB / 16384MiB |    100%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+

+---------------------------------------------------------------------------------------+
| Processes:                                                                            |
|  GPU   GI   CI        PID   Type   Process name                            GPU Memory |
|        ID   ID                                                             Usage      |
|=======================================================================================|
|    0   N/A  N/A   1552275      C   /usr/bin/python3                           3084MiB |
|    1   N/A  N/A   1552277      C   /usr/bin/python3                           3082MiB |
|    2   N/A  N/A   1552278      C   /usr/bin/python3                           3082MiB |
|    3   N/A  N/A   1552280      C   /usr/bin/python3                           3082MiB |
|    4   N/A  N/A   1552279      C   /usr/bin/python3                           3082MiB |
|    5   N/A  N/A   1552274      C   /usr/bin/python3                           3082MiB |
|    6   N/A  N/A   1552273      C   /usr/bin/python3                           3082MiB |
|    7   N/A  N/A   1552276      C   /usr/bin/python3                           3082MiB |
+---------------------------------------------------------------------------------------+
```

BioNeMo stands as a formidable generative AI tool tailored for the realm of drug discovery. In this illustrative example, we took the initiative to pretrain a custom model entirely from scratch, utilizing the extensive uniref50 dataset. However, it's worth noting that BioNeMo offers the flexibility to expedite the process by employing pretrained models directly [provided by NVidia](https://catalog.ngc.nvidia.com/orgs/nvidia/teams/clara/containers/bionemo-framework). This alternative approach can significantly streamline your workflow while maintaining the robust capabilities of the BioNeMo framework.


<CollapsibleContent header={<h3><span>Cleanup</span></h3>}>

Use the provided helper script `cleanup.sh` to tear down EKS cluster and other AWS resources.

```bash
cd ../../
./cleanup.sh
```

</CollapsibleContent>
