---
sidebar_position: 4
sidebar_label: AIBrix on EKS
---
import CollapsibleContent from '../../../src/components/CollapsibleContent';


# AIBrix

AIBrix is an open-source initiative designed to provide essential building blocks to construct scalable GenAI inference infrastructure. AIBrix delivers a cloud-native solution optimized for deploying, managing, and scaling large language model (LLM) inference, tailored specifically to enterprise needs.
![Alt text](https://aibrix.readthedocs.io/latest/_images/aibrix-architecture-v1.jpeg)

### Features
* LLM Gateway and Routing: Efficiently manage and direct traffic across multiple models and replicas.
* High-Density LoRA Management: Streamlined support for lightweight, low-rank adaptations of models.
* Distributed Inference: Scalable architecture to handle large workloads across multiple nodes.
* LLM App-Tailored Autoscaler: Dynamically scale inference resources based on real-time demand.
* Unified AI Runtime: A versatile sidecar enabling metric standardization, model downloading, and management.
* Heterogeneous-GPU Inference: Cost-effective SLO-driven LLM inference using heterogeneous GPUs.
* GPU Hardware Failure Detection: Proactive detection of GPU hardware issues.


<CollapsibleContent header={<h2><span>Deploying the Solution</span></h2>}>

:::warning
Before deploying this blueprint, it is important to be cognizant of the costs associated with the utilization of GPU Instances.
:::

This example deploys the following resources

- Creates a new sample VPC, 2 Private Subnets and 2 Public Subnets
- Creates Internet gateway for Public Subnets and NAT Gateway for Private Subnets
- Creates EKS Cluster Control plane with public endpoint (for demo reasons only) with core managed node group.
- Karpenter deployed as cluster scaler with following nodepools
  - g5-gpu-karpenter (for  nvidia gpus)
  - inferentia-inf2 (for  inferentia accelerators)
  - trainium-trn1 (for  trainium accelerators)
  - x86-cpu-karpenter (for  x86 cpus)


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
cd data-on-eks/ai-ml/aibrix/ && chmod +x install.sh
./install.sh
cd ..
```

### Verify the resources

Verify the Amazon EKS Cluster created

```bash
aws eks describe-cluster --name aibrix-stack
```

```bash

# Creates k8s config file to authenticate with EKS
aws eks --region us-west-2 update-kubeconfig --name aibrix-stack
```
```bash
kubectl get nodes # Output shows the EKS Managed Node group nodes

```

</CollapsibleContent>


### Installing AIBrix

Please run the below commands to install AIBrix


```bash
kubectl create -f https://github.com/vllm-project/aibrix/releases/download/v0.2.0/aibrix-dependency-v0.2.0.yaml
kubectl create -f https://github.com/vllm-project/aibrix/releases/download/v0.2.0/aibrix-core-v0.2.0.yaml
```

Wait for few minutes and run

``` bash
kubectl get pods -n aibrix-system
```

Wait till all the pods are in Running status.

#### Running a model on AiBrix system

We will now run Deepseek-Distill-llama-8b model using AIBrix on EKS.

Please run the below command. if you want to run the model on inferentia accelerator, please use deepseek-distill-neuron.yaml file for the below command.

```bash
kubectl apply -f examples/deepseek-distill.yaml
```

This will deploy the model on deepseek-aibrix namespace. Wait for few minutes and run

```bash
kubectl get pods -n deepseek-aibrix
```
 Wait for the pod to be in running state.

#### Accessing the model using gateway

Gateway is designed to serve LLM requests and provides features such as dynamic model & lora adapter discovery, user configuration for request count & token usage budgeting, streaming and advanced routing strategies such as prefix-cache aware, heterogeneous GPU hardware.
To access the model using Gateway, Please run the below command

```bash
kubectl -n envoy-gateway-system port-forward service/envoy-aibrix-system-aibrix-eg-903790dc 8888:80 &
```

Once the port-forward is running, you can test the model by sending a request to the Gateway.

```bash
ENDPOINT="localhost:8888"
curl -v http://${ENDPOINT}/v1/completions \
    -H "Content-Type: application/json" \
    -d '{
        "model": "deepseek-r1-distill-llama-8b",
        "prompt": "San Francisco is a",
        "max_tokens": 128,
        "temperature": 0
    }'
```

#### Accessing the model using gradio ui

You can also access the model using gradio ui. Please run the below command to deploy the gradio ui.

```bash
kubectl apply -f examples/gradio-ui.yaml
```

Once the gradio ui is deployed, you can port-forward the service to access the ui.

```bash
kubectl port-forward service/gradio-service 7860:7860 -n gradio-aibrix
```

Once the port-forward is running, you can access the ui by opening http://localhost:7860 in your browser.


<CollapsibleContent header={<h2><span>Cleanup</span></h2>}>

This script will cleanup the environment using `-target` option to ensure all the resources are deleted in correct order.

```bash
cd data-on-eks/ai-ml/aibrix/terraform && chmod +x cleanup.sh
./cleanup.sh
```

</CollapsibleContent>

:::caution
To avoid unwanted charges to your AWS account, delete all the AWS resources created during this deployment
:::

</CollapsibleContent>
