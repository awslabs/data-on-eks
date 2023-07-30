---
sidebar_position: 5
sidebar_label: Trainium on EKS
---
import CollapsibleContent from '../../../src/components/CollapsibleContent';

# AWS Trainium on EKS
[AWS Trainium](https://aws.amazon.com/machine-learning/trainium/) is an advanced ML accelerator that transforms high-performance deep learning(DL) training. `Trn1` instances, powered by AWS Trainium chips, are purpose-built for high-performance DL training of **100B+ parameter** models. Meticulously designed for exceptional performance, Trn1 instances cater specifically to training popular Natual Language Processing(NLP) models on AWS, offering up to  **50% cost savings ** compared to GPU-based EC2 instances. This cost efficiency makes them an attractive option for data scientists and ML practitioners seeking optimized training costs without compromising performance.

At the core of Trn1 instance's capabilities lies the [AWS Neuron SDK](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/), a software development kit seamlessly integrated with leading ML frameworks and libraries, such as [PyTorch](https://pytorch.org/), [TensorFlow](https://tensorflow.org/), [Megatron-LM](https://huggingface.co/docs/accelerate/usage_guides/megatron_lm), and [Hugging Face](https://huggingface.co/). The Neuron SDK empowers developers to train NLP, computer vision, and recommender models on Trainium with ease, requiring only a few lines of code changes. 

In this blueprint, we will learn how to securely deploy an [Amazon EKS Cluster](https://docs.aws.amazon.com/eks/latest/userguide/clusters.html) with Trainium Node groups (`Trn1.32xlarge` and `Trn1n.32xlarge`) and all the required plugins(EFA Package for EC2, Neuron Device K8s Plugin and EFA K8s plugin). Once the deployment is complete, we will learn how to train a BERT-large(Bidirectional Encoder Representations from Transformers) model  with Distributed PyTorch pre-training using the WikiCorpus dataset. For scheduling the distributed training job, we will utilize [TorchX](https://pytorch.org/torchx/latest/) with the [Volcano Scheduler](https://volcano.sh/en/). Additionally, we can monitor the neuron activity during training using `neuron-top`.

#### Trianium Device Architecture
Each Trainium device (chip) comprises two neuron cores. In the case of `Trn1.32xlarge` instances, `16 Trainium devices` are combined, resulting in a total of `32 Neuron cores`. The diagram below provides a visual representation of the Neuron device's architecture:

![Trainium Device](img/neuron-device.png)

#### AWS Neuron Drivers
Neuron Drivers are a set of essential software components installed on the host operating system of AWS Inferentia-based accelerators, such as Trainium/Inferentia instances. Their primary function is to optimize the interaction between the accelerator hardware and the underlying operating system, ensuring seamless communication and efficient utilization of the accelerator's computational capabilities. 

#### AWS Neuron Runtime
Neuron runtime consists of kernel driver and C/C++ libraries which provides APIs to access Inferentia and Trainium Neuron devices. The Neuron ML frameworks plugins for TensorFlow, PyTorch and Apache MXNet use the Neuron runtime to load and run models on the NeuronCores.

#### AWS Neuron Device Plugin for Kubernetes
The AWS Neuron Device Plugin for Kubernetes is a component that promotes Trainium/Inferentia devices as system hardware resources within the EKS cluster. It is deployed as a [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/), ensuring proper permissions for the device plugin to update the Node and Pod annotations, thereby seamlessly integrating Inferentia devices with Kubernetes pods. 

#### FSx for Lustre
In this blueprint, we utilize TorchX to initiate a DataParallel BERT phase1 pretraining task, employing 64 workers distributed across 2 trn1.32xlarge (or trn1n.32xlarge) instances, with 32 workers per instance. The BERT phase1 pretraining process involves a substantial 50+ GB WikiCorpus dataset as the training data. To handle large datasets efficiently, including the dataset inside the training container image or downloading it at the start of each job is not practical. Instead, we leverage shared file system storage to ensure multiple compute instances can process the training datasets concurrently.

For this purpose, FSx for Lustre emerges as an ideal solution for machine learning workloads. It provides shared file system storage that can process massive data sets at up to hundreds of gigabytes per second of throughput, millions of IOPS, and sub-millisecond latencies. We can dynamically create FSx for Lustre and attach the file system to the Pods using the FSx CSI controller through Persistent Volume Claims(PVC), enabling seamless integration of shared file storage with the distributed training process.

#### TorchX
[TorchX](https://pytorch.org/torchx/main/quickstart.html) SDK or CLI provides the functionality to effortlessly submit PyTorch jobs to Kubernetes. It offers the capability to connect predefined components like hyperparameter optimization, model serving, and distributed data-parallel into sophisticated pipelines, while leveraging popular job schedulers like Slurm, Ray, AWS Batch, Kubeflow Pipelines, and Airflow.

The TorchX Kubernetes scheduler relies on the [Volcano Scheduler](https://volcano.sh/en/docs/), which must be installed on the Kubernetes cluster. Gang scheduling is essential for multi-replica/multi-role execution, and currently, Volcano is the only supported scheduler within Kubernetes that meets this requirement.

TorchX can seamlessly integrate with Airflow and Kubeflow Pipelines. In this blueprint, we will install the TorchX CLI on a local machine/cloud9 ide and use it to trigger job submission on the EKS cluster, which, in turn, submits jobs to the Volcano scheduler queue running on the EKS Cluster.

#### Volcano Scheduler
[Volcano Scheduler](https://volcano.sh/en/docs/) is a custom Kubernetes batch scheduler designed to efficiently manage diverse workloads, making it particularly well-suited for resource-intensive tasks like machine learning. Volcano Queue serves as a collection of PodGroups, adopting a FIFO (First-In-First-Out) approach and forming the basis for resource allocation. VolcanoJob, also known as `vcjob`, is a Custom Resource Definition (CRD) object specifically tailored for Volcano. It stands out from a regular Kubernetes job by offering advanced features, including a specified scheduler, minimum member requirements, task definitions, lifecycle management, specific queue assignment, and priority settings. VolcanoJob is ideally suited for high-performance computing scenarios, such as machine learning, big data applications, and scientific computing.

### Solution Architecture

:::info
COMING SOON
:::


<CollapsibleContent header={<h2><span>Deploying the Solution</span></h2>}>

:::warning
Before deploying this blueprint, it is important to be cognizant of the costs associated with the utilization of AWS Trainium Instances. The blueprint sets up two `Trn1.32xlarge` instances for pre-training the dataset. Be sure to assess and plan for these costs accordingly.
:::

In this [example](https://github.com/awslabs/data-on-eks/tree/main/ai-ml/trainium), you will provision the following resources.

 - Create a new sample VPC, including 2 Private Subnets and 2 Public Subnets.
 - Set up an Internet gateway for the Public Subnets and a NAT Gateway for the Private Subnets.
 - Deploy the EKS Cluster Control plane with a public endpoint (for demo purposes only) and a core managed node group. Also, set up two additional node groups: `trn1-32xl-ng1` with 2 instances and `trn1n-32xl-ng` with 0 instances.
 - Install the EFA package during the bootstrap setup for the trn1-32xl-ng1 node group, and configure 8 Elastic Network Interfaces (ENIs) with EFA on each instance.
 - Use the EKS GPU AMI for the Trainium node groups, which includes Neuron drivers and runtime.
 - Deploy essential add-ons such as Metrics server, Cluster Autoscaler, Karpenter, Grafana, AMP, and Prometheus server.
 - Enable FSx for Lustre CSI driver to allow for Dynamic Persistent Volume Claim (PVC) creation for shared filesystems.
 - Set up the Volcano Scheduler for PyTorch job submission, allowing for efficient task scheduling on Kubernetes.
 - Prepare the necessary etcd setup as a prerequisite for TorchX.
 - Create a test queue within Volcano to enable TorchX job submission to this specific queue.

### Prerequisites

Ensure that you have installed the following tools on your machine.

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### Deploy

Clone the repository

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

Navigate into one of the example directories and run `install.sh` script

```bash
cd data-on-eks/ai-ml/trainium/ && chmod +x install.sh
./install.sh
```

### Verify the resources

Verify the Amazon EKS Cluster

```bash
aws eks describe-cluster --name trainium
```

```bash
# Creates k8s config file to authenticate with EKS
aws eks --region us-west-2 update-kubeconfig --name trainium

kubectl get nodes # Output shows the EKS Managed Node group nodes

```

</CollapsibleContent>


### Distributed PyTorch Training on Trainium with TorchX and EKS




<CollapsibleContent header={<h2><span>Cleanup</span></h2>}>

This script will cleanup the environment using `-target` option to ensure all the resources are deleted in correct order.

```bash
cd data-on-eks/ai-ml/trainium/ && chmod +x cleanup.sh
./cleanup.sh
```

</CollapsibleContent>

:::caution
To avoid unwanted charges to your AWS account, delete all the AWS resources created during this deployment
:::
