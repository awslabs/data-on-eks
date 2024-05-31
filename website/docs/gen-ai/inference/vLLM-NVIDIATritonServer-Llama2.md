---
title: NVIDIA Triton Server with vLLM
sidebar_position: 5
---
import CollapsibleContent from '../../../src/components/CollapsibleContent';

:::danger

Note: Use of this Llama-2 model and other Llama family models (like Llama3) is governed by the Meta license.
In order to download the model weights and tokenizer, please visit the [website](https://ai.meta.com/) and accept the license before requesting access.

Llama-2 model is a gated model in [Huggingface](https://huggingface.co/meta-llama/Llama-2-7b-chat-hf) repository.
In order to use this model, you'll need to be granted access to the [HuggingFace meta-llama repsitory](https://huggingface.co/meta-llama/Llama-2-7b-chat-hf). Please fill out the contact information form available in the repository page. You will be granted access once your information is reviewed.

Also note, that one needs to use a HuggingFace Token to use this blueprint.

To generate a token in HuggingFace, log in using your HuggingFace account and click on `Access Tokens` menu item on the [Settings](https://huggingface.co/settings/tokens) page.

:::

# Deploying Multiple Large Language Models with NVIDIA Triton Server and vLLM
This guide presents a blueprint for multi-model deployment using the Triton Inference Server and the vLLM backend/engine. 
By following this pattern, you can deploy multiple models simultaneously. 
We demonstrate this using two models: mistralai/Mistral-7B-Instruct-v0.2 and meta-llama/Llama-2-7b-chat-hf. 
These models will be hosted on a multi-GPU instance (`g5.12xlarge` with 4 GPUs), with each model utilizing up to 1 GPU. 
Triton can create multiple replica pods within the same node or across multiple nodes. Autoscaling is managed using HPA and custom metrics, scaling Triton pods based on throughput or requests for each model.

![NVIDIA Triton Server](img/nvidia-triton-vllm.png)

### Mistralai/Mistral-7B-Instruct-v0.2
Mistralai/Mistral-7B-Instruct-v0.2 is a state-of-the-art large language model designed to provide high-quality, instructive responses. Trained on a diverse dataset, it excels in understanding and generating human-like text across a variety of topics. Its capabilities make it suitable for applications requiring detailed explanations, complex queries, and natural language understanding.

### Meta-llama/Llama-2-7b-chat-hf
Meta-llama/Llama-2-7b-chat-hf is an advanced conversational AI model developed by Meta. It is optimized for chat applications, delivering coherent and contextually relevant responses. With its robust training on extensive dialogue datasets, this model excels in maintaining engaging and dynamic conversations, making it ideal for customer service bots, interactive agents, and other chat-based applications.

## Deploying the Solution
To get started with deploying `Llama-2-7b chat` on [Amazon EKS](https://aws.amazon.com/eks/), we will cover the necessary prerequisites and guide you through the deployment process step by step.
This includes setting up the infrastructure, deploying **NVIDIA Triton Server**, and creating the Triton client python app that sends GRPC requests to Triton server for inferencing.

<CollapsibleContent header={<h2><span>Prerequisites</span></h2>}>
Before we begin, ensure you have all the prerequisites in place to make the deployment process smooth and hassle-free.
nsure that you have installed the following tools on your machine.

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)



### Deploy

Clone the repository

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

Navigate into one of the example directories and run `install.sh` script

**Important Note:**

- Ensure that you update the region in the `variables.tf` file before deploying the blueprint.
Additionally, confirm that your local region setting matches the specified region to prevent any discrepancies.
For example, set your `export AWS_DEFAULT_REGION="<REGION>"` to the desired region:

- To proceed, ensure you have access to both models using your Huggingface account:

![mistral7b-hg.png](img/mistral7b-hg.png)

![llma27b-hg.png](img/llma27b-hg.png)

- Next, set the environment variable TF_VAR_huggingface_token with your Huggingface account token:
  `export TF_VAR_huggingface_token=<your Huggingface token>`.

Run the installation script.

```bash
cd data-on-eks/ai-ml/nvidia-triton-server/ && chmod +x install.sh
./install.sh
```

### Verify the resources

Once the installation finishes, verify the Amazon EKS Cluster

```bash
aws eks --region us-west-2 update-kubeconfig --name nvidia-triton-server
```

```bash
# Creates k8s config file to authenticate with EKS
aws eks --region us-west-2 update-kubeconfig --name nvidia-triton-server

kubectl get nodes # Output shows the EKS worker nodes
```

</CollapsibleContent>

## What is NVIDIA Triton Server

[NVIDIA Triton Inference Server](https://github.com/triton-inference-server/server) is an open-source inference serving software that simplifies the deployment and execution of AI models at scale across various hardware platforms, including GPUs, CPUs, and cloud/edge devices. Triton enables teams to deploy any AI model from multiple deep learning and machine learning frameworks, including TensorRT, TensorFlow, PyTorch, ONNX, OpenVINO, Python, RAPIDS FIL, and more. Triton supports inference across cloud, data center, edge and embedded devices on NVIDIA GPUs, x86 and ARM CPU, or AWS Inferentia. Triton Inference Server delivers optimized performance for many query types, including real time, batched, ensembles and audio/video streaming.

Major features of Triton include:

- Supports multiple Machine Leaning and Deeap Learning backends like Tensor-RT, vLLM, ONNX Runtime, OpenVINO, PyTorch and others. A Triton backend is the implementation that executes a model. A backend can be a wrapper around a deep-learning framework, like PyTorch, TensorFlow, TensorRT or ONNX Runtime. Or a backend can be custom C/C++ logic performing any operation (for example, image pre-processing).
- Supports concurrent model execution by allowing multiple models and/or multiple instances of the same model to execute in parallel on the same system.
- Dynamic batching is a feature of Triton that allows inference requests to be combined by the server, so that a batch is created dynamically.
- Provides both HTTP/REST and GRPC endpoints for Triton clients to communicate with Triton server.


## What is vLLM
[vLLM](https://docs.vllm.ai/en/latest/index.html) is a high-performance open source library tailored for fast LLM serving, emphasizing state-of-the-art serving throughput and efficient management of attention.

- Memory efficiency and high throughput are at the core of vLLM, thanks to its innovative PagedAttention mechanism. This approach optimizes memory allocation and allows for non-contiguous KV cache, translating into higher batch sizes and cost-effective serving.
- It supports fast model execution with CUDA/HIP graph.
- Enables high-throughput serving with various decoding algorithms, including parallel sampling, beam search, and more.

For more information on vLLM, read [vLLM blog](https://blog.vllm.ai/2023/06/20/vllm.html)

## Deploying NVIDIA Triton Server with vLLM Backend

This blueprint uses [Triton helm chart](https://github.com/aws-ia/terraform-aws-eks-data-addons/tree/main/helm-charts/nvidia-triton-server) to install and configure the Trinton server on Amazon EKS.

**Note:** The container image that's being used for Triton server is `nvcr.io/nvidia/tritonserver:24.02-vllm-python-py3` and is vLLM backend enabled.

You can choose appropriate tags in the [NGC Catalog](https://catalog.ngc.nvidia.com/orgs/nvidia/containers/tritonserver/tags).

The Triton helm configuration includes:

- Environment variables to specify `model_name`, `TRANSFORMERS_CACHE`, `tensor_parallel_size` and other parameters.
- Passes the `HUGGING_FACE_TOKEN` env as a kubernetes base64 encoded Secret to the Triton container.
- NodeSelector and Tolerations for GPU(g5) Nodes created by Karpenter.

**Model Repository**

The Triton Inference Server serves models from one or more model repositories that are specified when the server is stated. Triton can access models from one or more locally accessible file paths, and from Cloud Storage locations like Amazon S3.

The directories and files that compose a model repository must follow a required layout. The repository layout should follow the below structure

```
<model-repository-path>/
  <model-name>/
    [config.pbtxt]
    [<output-labels-file> ...]
    <version>/
      <model-definition-file>
    <version>/
      <model-definition-file>
    ...
  <model-name>/
    [config.pbtxt]
    [<output-labels-file> ...]
    <version>/
      <model-definition-file>
    <version>/
      <model-definition-file>
    ...
  ...
```

For vLLM enabled Triton model, the model_repository can be found at `gen-ai/inference/vllm-nvidia-triton-server-llama2-gpu/model_reposiotry` location.

During the deployment, the blueprint creates an S3 bucket and syncs the local `model_repository` contents to the S3 bucket.

- **model.py:**
  This script uses vLLM library as Triton backend framework and initializes a `TritonPythonModel` class by loading the model configuration and configuring vLLM engine. The `huggingface_hub` library's login function is used to establish access to the hugging face repository for model access. It then starts an asyncio event loop to process the received requests asynchronously. The script has several functions that processes the inference requests, issues the requests to vLLM backend and return the response.

- **config.pbtxt:**
This is a model configuration file that specifies parameters such as
  - Name - The name of the model must match the `name` of the model repository directory containing the model.
  - max_batch_size - The `max_batch_size` value indicates the maximum batch size that the model supports for the type of batching that can be exploited by Triton
  - Inputs and Outputs - Each model input and output must specify a name, datatype, and shape. An input shape indicates the shape of an input tensor expected by the model and by Triton in inference requests. An output shape indicates the shape of an output tensor produced by the model and returned by Triton in response to an inference request. Input and output shapes are specified by a combination of `max_batch_size` and the dimensions specified by `input dims` or `output dims`.

### Verify Deployment

**Ensure the cluster is configured locally**
```bash
aws eks --region us-west-2 update-kubeconfig --name nvidia-triton-server
```

Verify the deployment by running the following commands

```text
$ kubectl -n triton-vllm get all

NAME                                                                READY   STATUS    RESTARTS   AGE
pod/nvidia-triton-server-triton-inference-server-66b6546977-bb77w   1/1     Running   0          88m
pod/nvidia-triton-server-triton-inference-server-66b6546977-rjcxq   1/1     Running   0          88m

NAME                                                           TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)                      AGE
service/nvidia-triton-server-triton-inference-server           ClusterIP   172.20.86.24   <none>        8000/TCP,8001/TCP,8002/TCP   179m
service/nvidia-triton-server-triton-inference-server-metrics   ClusterIP   172.20.89.80   <none>        8080/TCP                     179m

NAME                                                           READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/nvidia-triton-server-triton-inference-server   2/2     2            2           179m

NAME                                                                      DESIRED   CURRENT   READY   AGE
replicaset.apps/nvidia-triton-server-triton-inference-server-66b6546977   2         2         2       179m

NAME                                                                               REFERENCE                                                 TARGETS                        MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/nvidia-triton-server-triton-inference-server   Deployment/nvidia-triton-server-triton-inference-server   <unknown>/80%, <unknown>/80%   1         5         2          179m

```

### To Test the Llama-2-Chat Model
Once you see the status of the model deployment is in `running` state then you can start using Llama-2-chat.

First, execute a port forward to the Triton-inference-server Service using kubectl:

```bash
kubectl -n triton-vllm port-forward svc/nvidia-triton-server-triton-inference-server 8001:8001
```

Next, Create a Python virtual environment by going to the Triton client location.

```bash
cd gen-ai/inference/vllm-nvidia-triton-server-llama2-gpu/triton-client
python3 -m venv .venv
source .venv/bin/activate
```

Install all the `tritonclient` dependencies with pip

```bash
pip install tritonclient[all]
```

Populate the 'prompts.txt' file with multiple prompts. Please snure that each prompt is on a new line.

The `triton-client.py` is a python application that demonstrates asynchronous communication with th Triton Inference Server using the tritonclient library. It sends the requests to the Triton server using `grpc` protocol.

Run the Triton client app using the following command:


```bash
python3 triton-client.py
```

You should see output similar to the following:

```text
Loading inputs from `prompts.txt`...
Storing results into `results.txt`...
PASS: vLLM example
```

The inference results are stored in `results.txt` file in the same directory.

A sample result looks like

```text

"Can you explain how TensorRT optimizes LLM inference on NVIDIA hardware?"
[/INST]  TensorRT is an open-source software library developed by NVIDIA for high-performance, low-latency, and efficient deployment of deep learning models on NVIDIA GPUs. When it comes to optimizing large language models (LLMs) for inference on NVIDIA hardware, TensorRT provides several key optimizations:

1. Model Optimization: TensorRT supports a wide range of deep learning frameworks, including TensorFlow, PyTorch, and Caffe. It optimizes the LLM model for inference on NVIDIA GPUs by reducing memory bandwidth and computational requirements.
2. Data Parallelism: TensorRT enables data parallelism by dividing the input data into smaller chunks and processing them in parallel across multiple GPUs. This significantly reduces the inference time for LLMs.
3. Model Pruning: TensorRT supports model pruning, which involves removing unimportant weights from the LLM model. This reduces the computational requirements and memory usage, resulting in faster inference times.
4. Quantization: TensorRT supports quantization, which involves converting the LLM model's weights and activations from floating-point numbers to integers. This reduces the memory usage and computational requirements, resulting in faster inference times.
5. Kernel Optimization: TensorRT optimizes the inference kernels for LLMs by exploiting the parallelism in the GPU architecture. This includes loop fusion, constant folding, and dead code elimination.
6. Memory Optimization: TensorRT optimizes the memory usage for LLM inference by using techniques such as model compression, tensor tiling, and memory pooling.
7. Profiling and Optimization: TensorRT provides tools for profiling and optimizing the LLM inference performance on NVIDIA hardware. This includes tools for identifying performance bottlenecks and optimizing the model, kernel, and memory usage.

By leveraging these optimizations, TensorRT can significantly improve the inference performance of LLMs on NVIDIA hardware, making it an ideal choice for deploying LLMs in applications such as natural language processing, computer vision, and autonomous driving.

=========
```

## Conclusion

In conclusion, you will have successfully deployed the **Llama-2-7b chat** model on EKS that can serve fast Inference leveraging Triton server with vLLM backend.

Integrating vLLM with Triton Inference Server offers high performance inference serving and unmatched scalability while enabling multi-model support and flexible model management.



## Cleanup

Finally, we'll provide instructions for cleaning up and deprovisioning the resources when they are no longer needed.

**Cleanup the EKS Cluster:**
This script will cleanup the environment using `-target` option to ensure all the resources are deleted in correct order.

```bash
export AWS_DEAFULT_REGION="DEPLOYED_EKS_CLUSTER_REGION>"
cd data-on-eks/ai-ml/nvidia-triton-server/ && chmod +x cleanup.sh
./cleanup.sh
```
