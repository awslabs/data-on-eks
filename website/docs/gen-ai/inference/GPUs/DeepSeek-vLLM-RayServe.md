---
title: DeepSeek LLM with RayServe and vLLM
sidebar_position: 1
---
import CollapsibleContent from '../../../../src/components/CollapsibleContent';

:::warning
Deployment of ML models on EKS requires access to GPUs or Neuron instances. If your deployment isn't working, it’s often due to missing access to these resources. Also, some deployment patterns rely on Karpenter autoscaling and static node groups; if nodes aren't initializing, check the logs for Karpenter or Node groups to resolve the issue.
:::

# Deploying DeepSeek LLM with RayServe and vLLM

This guide will walk you through deploying the DeepSeek-R1-Distill-Llama-8B model using RayServe and vLLM on Amazon EKS.

<CollapsibleContent header={<h2><span>Deploying the Solution</span></h2>}>

We are utilizing Terraform Infrastructure as Code (IaC) templates to deploy an Amazon EKS cluster, and we dynamically scale GPU nodes using Karpenter when the model is deployed using RayServe YAML configurations.

To get started with deploying mistralai/Mistral-7B-Instruct-v0.2 on Amazon EKS, this guide will cover the necessary prerequisites and walk you through the deployment process step by step. This process includes setting up the infrastructure, deploying the Ray cluster, and creating the client Python application that sends HTTP requests to the RayServe endpoint for inferencing.


:::danger

Important: Deploying on `g5.8xlarge` instances can be expensive. Ensure you carefully monitor and manage your usage to avoid unexpected costs. Consider setting budget alerts and usage limits to keep track of your expenditures.

:::

### Prerequisites
Before we begin, ensure you have all the necessary prerequisites in place to make the deployment process smooth. Make sure you have installed the following tools on your machine:

:::info

To simplify the demo process, we assume the use of an IAM role with administrative privileges due to the complexity of creating minimal IAM roles for each blueprint that may create various AWS services. However, for production deployments, it is strongly advised to create an IAM role with only the necessary permissions. Employing tools such as [IAM Access Analyzer](https://aws.amazon.com/iam/access-analyzer/) can assist in ensuring a least-privilege approach.

:::

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [envsubst](https://pypi.org/project/envsubst/)

### Deploy

Clone the repository

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

**Important Note:**

**Step1**: Ensure that you update the region in the `variables.tf` file before deploying the blueprint.
Additionally, confirm that your local region setting matches the specified region to prevent any discrepancies.

For example, set your `export AWS_DEFAULT_REGION="<REGION>"` to the desired region:


**Step2**: Run the installation script.

```bash
cd data-on-eks/ai-ml/jark-stack/terraform && chmod +x install.sh
```

```bash
./install.sh
```

### Verify the resources

Once the installation finishes, verify the Amazon EKS Cluster.

Creates k8s config file to authenticate with EKS.

```bash
aws eks --region us-west-2 update-kubeconfig --name jark-stack
```

```bash
kubectl get nodes
```

```text
NAME                                           STATUS   ROLES    AGE    VERSION
ip-100-64-118-130.us-west-2.compute.internal   Ready    <none>   3h9m   v1.30.0-eks-036c24b
ip-100-64-127-174.us-west-2.compute.internal   Ready    <none>   9h     v1.30.0-eks-036c24b
ip-100-64-132-168.us-west-2.compute.internal   Ready    <none>   9h     v1.30.0-eks-036c24b
```

Verify the Karpenter autosclaer Nodepools

```bash
kubectl get nodepools
```

```text
NAME                NODECLASS
g5-gpu-karpenter    g5-gpu-karpenter
x86-cpu-karpenter   x86-cpu-karpenter
```

Verify the NVIDIA Device plugin

```bash
kubectl get pods -n nvidia-device-plugin
```
```text
NAME                                                              READY   STATUS    RESTARTS   AGE
nvidia-device-plugin-gpu-feature-discovery-b4clk                  1/1     Running   0          3h13m
nvidia-device-plugin-node-feature-discovery-master-568b49722ldt   1/1     Running   0          9h
nvidia-device-plugin-node-feature-discovery-worker-clk9b          1/1     Running   0          3h13m
nvidia-device-plugin-node-feature-discovery-worker-cwg28          1/1     Running   0          9h
nvidia-device-plugin-node-feature-discovery-worker-ng52l          1/1     Running   0          9h
nvidia-device-plugin-p56jj                                        1/1     Running   0          3h13m
```

Verify Kuberay Operator which is used to create Ray Clusters

```bash
kubectl get pods -n kuberay-operator
```

```text
NAME                                READY   STATUS    RESTARTS   AGE
kuberay-operator-7894df98dc-447pm   1/1     Running   0          9h
```

</CollapsibleContent>


## Step-by-Step Deployment

### 1. Create ECR Repository

First, create an ECR repository to store your custom container image:

```bash
aws ecr create-repository \
    --repository-name vllm-rayserve \
    --image-scanning-configuration scanOnPush=true \
    --region <your-region>
```

### 2. Go to Directory

```bash
cd data-on-eks/gen-ai/inference/vllm-rayserve-gpu
```

### 3. Update Dockerfile

Edit the Dockerfile and update the following lines:

```dockerfile
# Update base image
FROM rayproject/ray:2.41.0-py310-cu118 AS base

# Update library versions
RUN pip install vllm==0.7.0 huggingface_hub==0.27.1
```

### 4. Modify vllm_serve.py

Edit vllm_serve.py and remove the route prefix:

```python
# Before:
# @serve.deployment(num_replicas=1, route_prefix="/vllm")

# After:
@serve.deployment(num_replicas=1)
```

### 5. Build and Push Container Image

```bash
# Get ECR login credentials
aws ecr get-login-password --region <your-region> | docker login --username AWS --password-stdin <your-account-id>.dkr.ecr.<your-region>.amazonaws.com

# Build the image
docker build -t vllm-rayserve .

# Tag the image
docker tag vllm-rayserve:latest <your-account-id>.dkr.ecr.<your-region>.amazonaws.com/vllm-rayserve:latest

# Push to ECR
docker push <your-account-id>.dkr.ecr.<your-region>.amazonaws.com/vllm-rayserve:latest
```

### 6. Update ray-service-vllm.yaml

Edit ray-service-vllm.yaml with the following changes:

```yaml
# Update model configuration
spec:
  rayStartParams:
    env:
      - name: MODEL_ID
        value: "deepseek-ai/DeepSeek-R1-Distill-Llama-8B"
      - name: MAX_MODEL_LEN
        value: "8192"

# Update container image in both head and worker sections
containers:
  - image: <your-account-id>.dkr.ecr.<your-region>.amazonaws.com/vllm-rayserve:latest
```

### 7. Deploy the Updated Configuration

```bash
kubectl apply -f ray-service-vllm.yaml
```

### 8. Verify Deployment

```bash
# Check pods status
kubectl get pods -n rayserve-vllm

# Check services
kubectl get svc -n rayserve-vllm
```

## Testing the DeepSeek Model

The testing process remains similar to the original deployment, but now using the DeepSeek model:

```bash
# Port forward the service
kubectl -n rayserve-vllm port-forward svc/vllm-serve-svc 8000:8000

# Run the test client
python3 client.py
```

:::note
The DeepSeek-R1-Distill-Llama-8B model may have different performance characteristics and memory requirements compared to Mistral. Ensure your cluster has adequate resources.
:::

## Resource Requirements

- Minimum GPU: NVIDIA GPU with at least 16GB VRAM
- Recommended instance type: g5.2xlarge or better
- Minimum memory: 32GB RAM

## Monitoring and Observability

The monitoring setup remains the same as the original deployment, using Prometheus and Grafana. The metrics will now reflect the DeepSeek model's performance.

## Cleanup

To remove the deployment:

```bash
# Delete the Ray service
kubectl delete -f ray-service-vllm.yaml

# Delete the ECR repository if no longer needed
aws ecr delete-repository \
    --repository-name vllm-rayserve \
    --force \
    --region <your-region>
```

:::warning
Make sure to monitor GPU utilization and memory usage when first deploying the DeepSeek model, as it may have different resource requirements than Mistral.
:::

This adaptation maintains the core functionality while updating the necessary components for the DeepSeek model. The main differences are in the model configuration and resource requirements, while the deployment structure remains largely the same.
