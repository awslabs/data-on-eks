---
title: NVIDIA Triton Server on vLLM
sidebar_position: 2
---
import CollapsibleContent from '../../../../../../../src/components/CollapsibleContent';

:::caution

**AI on EKS**内容**正在迁移**到一个新的仓库。
🔗 👉 [阅读完整的迁移公告 »](https://awslabs.github.io/data-on-eks/docs/migration/migration-announcement)

:::

:::warning
在EKS上部署ML模型需要访问GPU或Neuron实例。如果您的部署不起作用，通常是因为缺少对这些资源的访问。此外，一些部署模式依赖于Karpenter自动扩展和静态节点组；如果节点未初始化，请检查Karpenter或节点组的日志以解决问题。
:::

:::caution

使用[Meta-llama/Llama-2-7b-chat-hf](https://huggingface.co/meta-llama/Meta-Llama-3-8B)和[Mistralai/Mistral-7B-Instruct-v0.2](https://huggingface.co/mistralai/Mistral-7B-Instruct-v0.2)模型需要通过Hugging Face账户访问。

:::

# 使用NVIDIA Triton服务器和vLLM部署多个大型语言模型
在这个模式中，我们将探索如何使用[Triton推理服务器](https://github.com/triton-inference-server/server)和[vLLM](https://github.com/vllm-project/vllm)后端/引擎部署多个大型语言模型(LLM)。我们将使用两个特定模型演示这个过程：`mistralai/Mistral-7B-Instruct-v0.2`和`meta-llama/Llama-2-7b-chat-hf`。这些模型将托管在配备**4个GPU**的**g5.24xlarge**多GPU实例上，每个模型最多使用一个GPU。

NVIDIA Triton推理服务器与vLLM后端结合时，为部署多个大型语言模型(LLM)提供了强大的框架。用户应用程序通过REST API或gRPC与推理服务交互，这由NGINX和网络负载均衡器(NLB)管理，以有效分配传入请求到Triton K8s服务。Triton K8s服务是我们部署的核心，Triton服务器在这里处理推理请求。对于此部署，我们使用g5.24xlarge实例，每个实例配备4个GPU，运行多个模型，如Llama2-7b和Mistral7b。水平Pod自动缩放器(HPA)监控自定义指标并根据需求动态扩展Triton pod，确保高效处理不同负载。Prometheus和Grafana用于收集和可视化指标，提供性能洞察并帮助自动扩展决策。

![NVIDIA Triton服务器](../../../../../../../docs/gen-ai/inference/img/triton-architecture.png)

## 预期结果

当您按照描述部署所有内容时，您可以预期推理请求的快速响应时间。以下是使用`Llama-2-7b-chat-hf`和`Mistral-7B-Instruct-v0.2`模型运行`triton-client.py`脚本的示例输出：


<details>
<summary>点击展开比较结果</summary>

| **运行1: Llama2** | **运行2: Mistral7b** |
|-------------------|----------------------|
| python3 triton-client.py --model-name llama2 --input-prompts prompts.txt --results-file llama2_results.txt | python3 triton-client.py --model-name mistral7b --input-prompts prompts.txt --results-file mistral_results.txt |
| Loading inputs from `prompts.txt`... | Loading inputs from `prompts.txt`... |
| Model llama2 - Request 11: 0.00 ms | Model mistral7b - Request 3: 0.00 ms |
| Model llama2 - Request 15: 0.02 ms | Model mistral7b - Request 14: 0.00 ms |
| Model llama2 - Request 3: 0.00 ms | Model mistral7b - Request 11: 0.00 ms |
| Model llama2 - Request 8: 0.01 ms | Model mistral7b - Request 15: 0.00 ms |
| Model llama2 - Request 0: 0.01 ms | Model mistral7b - Request 5: 0.00 ms |
| Model llama2 - Request 9: 0.01 ms | Model mistral7b - Request 0: 0.01 ms |
| Model llama2 - Request 14: 0.01 ms | Model mistral7b - Request 7: 0.01 ms |
| Model llama2 - Request 16: 0.00 ms | Model mistral7b - Request 13: 0.00 ms |
| Model llama2 - Request 19: 0.02 ms | Model mistral7b - Request 9: 0.00 ms |
| Model llama2 - Request 4: 0.02 ms | Model mistral7b - Request 16: 0.01 ms |
| Model llama2 - Request 10: 0.02 ms | Model mistral7b - Request 18: 0.01 ms |
| Model llama2 - Request 6: 0.01 ms | Model mistral7b - Request 4: 0.01 ms |
| Model llama2 - Request 1: 0.02 ms | Model mistral7b - Request 8: 0.01 ms |
| Model llama2 - Request 7: 0.02 ms | Model mistral7b - Request 1: 0.01 ms |
| Model llama2 - Request 18: 0.01 ms | Model mistral7b - Request 6: 0.00 ms |
| Model llama2 - Request 12: 0.01 ms | Model mistral7b - Request 12: 0.00 ms |
| Model llama2 - Request 2: 0.01 ms | Model mistral7b - Request 17: 0.00 ms |
| Model llama2 - Request 17: 0.02 ms | Model mistral7b - Request 2: 0.01 ms |
| Model llama2 - Request 13: 0.01 ms | Model mistral7b - Request 19: 0.01 ms |
| Model llama2 - Request 5: 0.02 ms | Model mistral7b - Request 10: 0.02 ms |
| Storing results into `llama2_results.txt`... | Storing results into `mistral_results.txt`... |
| Total time for all requests: 0.00 seconds (0.18 milliseconds) | Total time for all requests: 0.00 seconds (0.11 milliseconds) |
| PASS: vLLM example | PASS: vLLM example |


</details>
# Triton服务器内部结构和后端集成

NVIDIA Triton推理服务器专为在各种模型类型和部署场景中实现高性能推理而设计。Triton的核心优势在于它支持各种后端，这些后端提供了有效处理不同类型模型和工作负载所需的灵活性和能力。

一旦请求到达Triton K8s服务，它就会被Triton服务器处理。服务器支持动态批处理，允许将多个推理请求分组在一起以优化处理。这在高吞吐量需求的场景中特别有用，因为它有助于减少延迟并提高整体性能。

然后，请求由调度队列管理，确保每个模型的推理请求以有序的方式处理。Triton服务器支持选择性和计算模型加载，这意味着它可以根据当前工作负载和资源可用性动态加载模型。这个特性对于在多模型部署中高效管理资源至关重要。

Triton推理能力的支柱是其各种后端，包括TensorRT-LLM和vLLM：

**[TensorRT-LLM](https://github.com/NVIDIA/TensorRT-LLM)**：TensorRT-LLM后端优化了NVIDIA GPU上的大型语言模型(LLM)推理。利用TensorRT的高性能功能，它加速了推理，提供低延迟和高吞吐量性能。TensorRT特别适合需要密集计算资源的深度学习模型，使其成为实时AI应用的理想选择。

**[vLLM](https://github.com/vllm-project/vllm)**：vLLM后端专门设计用于处理各种LLM工作负载。它提供了为大型模型量身定制的高效内存管理和执行管道。这个后端确保内存资源得到最佳使用，允许部署非常大的模型而不会遇到内存瓶颈。vLLM对于需要同时服务多个大型模型的应用至关重要，提供了一个强大且可扩展的解决方案。


![NVIDIA Triton服务器](../../../../../../../docs/gen-ai/inference/img/triton-internals.png)

### Mistralai/Mistral-7B-Instruct-v0.2
Mistralai/Mistral-7B-Instruct-v0.2是一个最先进的大型语言模型，旨在提供高质量、有指导性的响应。它在多样化的数据集上训练，擅长理解和生成各种主题的类人文本。其功能使其适用于需要详细解释、复杂查询和自然语言理解的应用。

### Meta-llama/Llama-2-7b-chat-hf
Meta-llama/Llama-2-7b-chat-hf是由Meta开发的先进对话AI模型。它针对聊天应用进行了优化，提供连贯且与上下文相关的响应。凭借其在广泛对话数据集上的强大训练，该模型擅长维持引人入胜且动态的对话，使其成为客户服务机器人、交互式代理和其他基于聊天的应用的理想选择。

## 部署解决方案
要开始在[Amazon EKS](https://aws.amazon.com/eks/)上部署`mistralai/Mistral-7B-Instruct-v0.2`和`meta-llama/Llama-2-7b-chat-hf`，我们将涵盖必要的先决条件，并一步步引导您完成部署过程。此过程包括设置基础设施、部署NVIDIA Triton推理服务器，以及创建向Triton服务器发送gRPC请求进行推理的Triton客户端Python应用程序。

:::danger

重要提示：在配备多个GPU的`g5.24xlarge`实例上部署可能会很昂贵。确保您仔细监控和管理您的使用情况，以避免意外成本。考虑设置预算警报和使用限制来跟踪您的支出。

:::

<CollapsibleContent header={<h2><span>先决条件</span></h2>}>
在我们开始之前，请确保您已经准备好所有必要的先决条件，以使部署过程顺利进行。确保您已在计算机上安装了以下工具：

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### 部署

克隆仓库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到其中一个示例目录并运行`install.sh`脚本

**重要提示：**

**步骤1**：确保在部署蓝图之前更新`variables.tf`文件中的区域。
此外，确认您的本地区域设置与指定区域匹配，以防止任何差异。

例如，将您的`export AWS_DEFAULT_REGION="<REGION>"`设置为所需区域：

**步骤2**：要继续，请确保您使用Huggingface账户访问这两个模型：

![mistral7b-hg.png](../../../../../../../docs/gen-ai/inference/img/mistral7b-hg.png)

![llma27b-hg.png](../../../../../../../docs/gen-ai/inference/img/llma27b-hg.png)

**步骤3**：接下来，使用您的Huggingface账户令牌设置环境变量TF_VAR_huggingface_token：
  `export TF_VAR_huggingface_token=<your Huggingface token>`。

**步骤4**：运行安装脚本。

```bash
cd data-on-eks/ai-ml/nvidia-triton-server/ && chmod +x install.sh
./install.sh
```

### 验证资源

**步骤5**：安装完成后，验证Amazon EKS集群

```bash
# 创建k8s配置文件以与EKS进行身份验证
aws eks --region us-west-2 update-kubeconfig --name nvidia-triton-server

kubectl get nodes # 输出显示EKS工作节点
```

您应该看到此安装部署的三个节点：两个`m5.xlarge`和一个`g5.24xlarge`。

```text
ip-100-64-190-174.us-west-2.compute.internal   Ready    <none>   11d     v1.29.3-eks-ae9a62a
ip-100-64-59-224.us-west-2.compute.internal    Ready    <none>   8m26s   v1.29.3-eks-ae9a62a
ip-100-64-59-227.us-west-2.compute.internal    Ready    <none>   11d     v1.29.3-eks-ae9a62a
```

</CollapsibleContent>


### 使用vLLM后端的NVIDIA Triton服务器

此蓝图使用[Triton helm图表](https://github.com/aws-ia/terraform-aws-eks-data-addons/tree/main/helm-charts/nvidia-triton-server)在Amazon EKS上安装和配置Triton服务器。部署使用蓝图中的以下Terraform代码进行配置。

<details>
<summary>点击展开部署代码</summary>
```hcl
module "triton_server_vllm" {
  depends_on = [module.eks_blueprints_addons.kube_prometheus_stack]
  source     = "aws-ia/eks-data-addons/aws"
  version    = "~> 1.32.0" # ensure to update this to the latest/desired version

  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_nvidia_triton_server = false

  nvidia_triton_server_helm_config = {
    version   = "1.0.0"
    timeout   = 120
    wait      = false
    namespace = kubernetes_namespace_v1.triton.metadata[0].name
    values = [
      <<-EOT
      replicaCount: 1
      image:
        repository: nvcr.io/nvidia/tritonserver
        tag: "24.06-vllm-python-py3"
      serviceAccount:
        create: false
        name: ${kubernetes_service_account_v1.triton.metadata[0].name}
      modelRepositoryPath: s3://${module.s3_bucket.s3_bucket_id}/model_repository
      environment:
        - name: model_name
          value: ${local.default_model_name}
        - name: "LD_PRELOAD"
          value: ""
        - name: "TRANSFORMERS_CACHE"
          value: "/home/triton-server/.cache"
        - name: "shm-size"
          value: "5g"
        - name: "NCCL_IGNORE_DISABLED_P2P"
          value: "1"
        - name: tensor_parallel_size
          value: "1"
        - name: gpu_memory_utilization
          value: "0.9"
        - name: dtype
          value: "auto"
      secretEnvironment:
        - name: "HUGGING_FACE_TOKEN"
          secretName: ${kubernetes_secret_v1.huggingface_token.metadata[0].name}
          key: "HF_TOKEN"
      resources:
        limits:
          cpu: 6
          memory: 25Gi
          nvidia.com/gpu: 4
        requests:
          cpu: 6
          memory: 25Gi
          nvidia.com/gpu: 4
      nodeSelector:
        NodeGroupType: g5-gpu-karpenter
        type: karpenter

      tolerations:
        - key: "nvidia.com/gpu"
          operator: "Exists"
          effect: "NoSchedule"
      EOT
    ]
  }
}

```
</details>


**注意：** 用于Triton服务器的容器镜像是`nvcr.io/nvidia/tritonserver:24.02-vllm-python-py3`，并启用了vLLM后端。您可以在[NGC目录](https://catalog.ngc.nvidia.com/orgs/nvidia/containers/tritonserver/tags)中选择适当的标签。

**模型仓库**：
Triton推理服务器从服务器启动时指定的一个或多个模型仓库提供模型。Triton可以访问本地可访问的文件路径和云存储位置（如Amazon S3）中的模型。

组成模型仓库的目录和文件必须遵循所需的布局。仓库布局应按如下结构：
<details>
<summary>点击展开模型目录层次结构</summary>
```text
<model-repository-path>/
  <model-name>/
    [config.pbtxt]
    [<output-labels-file> ...]
    <version>/
      <model-definition-file>
    <version>/
      <model-definition-file>

  <model-name>/
    [config.pbtxt]
    [<output-labels-file> ...]
    <version>/
      <model-definition-file>
    <version>/
      <model-definition-file>
    ...


-------------
示例:
-------------
model-repository/
  mistral-7b/
    config.pbtxt
    1/
      model.py
  llama-2/
    config.pbtxt
    1/
      model.py
```
</details>


对于启用vLLM的Triton模型，model_repository可以在`gen-ai/inference/vllm-nvidia-triton-server-gpu/model_repository`位置找到。在部署期间，蓝图创建一个S3存储桶并将本地`model_repository`内容同步到S3存储桶。

**model.py**：此脚本使用vLLM库作为Triton后端框架，通过加载模型配置和配置vLLM引擎来初始化`TritonPythonModel`类。使用`huggingface_hub`库的登录函数建立对hugging face仓库的访问以获取模型访问权限。然后它启动一个asyncio事件循环来异步处理接收到的请求。该脚本有几个函数，用于处理推理请求，向vLLM后端发出请求并返回响应。

**config.pbtxt**：这是一个模型配置文件，指定了以下参数：

- 名称 - 模型的名称必须与包含模型的模型仓库目录的`name`匹配。
- max_batch_size - `max_batch_size`值表示模型支持的最大批处理大小，用于Triton可以利用的批处理类型
- 输入和输出 - 每个模型输入和输出必须指定名称、数据类型和形状。输入形状表示模型预期的输入张量的形状，以及Triton在推理请求中的形状。输出形状表示模型产生的输出张量的形状，以及Triton在响应推理请求时返回的形状。输入和输出形状由`max_batch_size`和`input dims`或`output dims`指定的维度组合指定。

### 验证部署

要验证Triton推理服务器已成功部署，请运行以下命令：

```bash
kubectl get all -n triton-vllm
```

下面的输出显示有一个pod运行Triton服务器，该服务器托管两个模型。
有一个服务用于与模型交互，以及一个用于Triton服务器的ReplicaSet。
部署将根据自定义指标和HPA对象进行水平扩展。

```text
NAME                                                               READY   STATUS    RESTARTS   AGE
pod/nvidia-triton-server-triton-inference-server-c49bd559d-szlpf   1/1     Running   0          13m

NAME                                                           TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
service/nvidia-triton-server-triton-inference-server           ClusterIP   172.20.193.97   <none>        8000/TCP,8001/TCP,8002/TCP   13m
service/nvidia-triton-server-triton-inference-server-metrics   ClusterIP   172.20.5.247    <none>        8080/TCP                     13m

NAME                                                           READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/nvidia-triton-server-triton-inference-server   1/1     1            1           13m

NAME                                                                     DESIRED   CURRENT   READY   AGE
replicaset.apps/nvidia-triton-server-triton-inference-server-c49bd559d   1         1         1       13m

NAME                                                                               REFERENCE                                                 TARGETS                        MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/nvidia-triton-server-triton-inference-server   Deployment/nvidia-triton-server-triton-inference-server   <unknown>/80%, <unknown>/80%   1         5         1          13m

```

此输出表明Triton服务器pod正在运行，服务已正确设置，并且部署按预期运行。水平Pod自动缩放器也处于活动状态，确保pod数量根据指定的指标进行扩展。

### 测试Llama-2-7b聊天和Mistral-7b聊天模型
是时候测试Llama-2-7b聊天和Mistral-7b聊天模型了。我们将使用相同的提示运行以下命令，以验证两个模型生成的输出。

首先，使用kubectl执行端口转发到Triton-inference-server服务：

```bash
kubectl -n triton-vllm port-forward svc/nvidia-triton-server-triton-inference-server 8001:8001
```

接下来，使用相同的提示为每个模型运行Triton客户端：

```bash
cd data-on-eks/gen-ai/inference/vllm-nvidia-triton-server-gpu/triton-client
python3 -m venv .venv
source .venv/bin/activate
pip install tritonclient[all]
python3 triton-client.py --model-name mistral7b --input-prompts prompts.txt --results-file mistral_results.txt
```

您将看到类似以下的输出：

```text
python3 triton-client.py --model-name mistral7b --input-prompts prompts.txt --results-file mistral_results.txt
Loading inputs from `prompts.txt`...
Model mistral7b - Request 3: 0.00 ms
Model mistral7b - Request 14: 0.00 ms
Model mistral7b - Request 11: 0.00 ms
Model mistral7b - Request 15: 0.00 ms
Model mistral7b - Request 5: 0.00 ms
Model mistral7b - Request 0: 0.01 ms
Model mistral7b - Request 7: 0.01 ms
Model mistral7b - Request 13: 0.00 ms
Model mistral7b - Request 9: 0.00 ms
Model mistral7b - Request 16: 0.01 ms
Model mistral7b - Request 18: 0.01 ms
Model mistral7b - Request 4: 0.01 ms
Model mistral7b - Request 8: 0.01 ms
Model mistral7b - Request 1: 0.01 ms
Model mistral7b - Request 6: 0.00 ms
Model mistral7b - Request 12: 0.00 ms
Model mistral7b - Request 17: 0.00 ms
Model mistral7b - Request 2: 0.01 ms
Model mistral7b - Request 19: 0.01 ms
Model mistral7b - Request 10: 0.02 ms
Storing results into `mistral_results.txt`...
Total time for all requests: 0.00 seconds (0.11 milliseconds)
PASS: vLLM example
```

`mistral_results.txt`的输出应该如下所示：
<details>
<summary>点击展开Mistral结果部分输出</summary>
```text
<s>[INST]<<SYS>>
Keep short answers of no more than 100 sentences.
<</SYS>>

What are the key differences between traditional machine learning models and very large language models (vLLM)?
[/INST] Traditional machine learning models (MLMs) are trained on specific datasets and features to learn patterns and make predictions based on that data. They require labeled data for training and are limited by the size and diversity of the training data. MLMs can be effective for solving structured problems, such as image recognition or speech recognition.

Very Large Language Models (vLLMs), on the other hand, are trained on vast amounts of text data using deep learning techniques. They learn to generate human-like text based on the input they receive. vLLMs can understand and generate text in a more contextually aware and nuanced way than MLMs. They can also perform a wider range of tasks, such as text summarization, translation, and question answering. However, vLLMs can be more computationally expensive and require large amounts of data and power to train. They also have the potential to generate inaccurate or biased responses if not properly managed.

=========

<s>[INST]<<SYS>>
Keep short answers of no more than 100 sentences.
<</SYS>>

Can you explain how TensorRT optimizes LLM inference on NVIDIA hardware?
[/INST] TensorRT is a deep learning inference optimization tool from NVIDIA. It utilizes dynamic and static analysis to optimize deep learning models for inference on NVIDIA GPUs. For Maximum Likelihood Modeling (LLM) inference, TensorRT applies the following optimizations:

1. Model Optimization: TensorRT converts the LLM model into an optimized format, such as INT8 or FP16, which reduces memory usage and increases inference speed.

2. Engine Generation: TensorRT generates a custom engine for the optimized model, which includes kernel optimizations for specific NVIDIA GPUs.

3. Memory Optimization: TensorRT minimizes memory usage by using data layout optimizations, memory pooling, and other techniques.

4. Execution Optimization: TensorRT optimizes the execution of the engine on the GPU by scheduling and managing thread execution, reducing latency and increasing throughput.

5. I/O Optimization: TensorRT optimizes input and output data transfer between the host and the GPU, reducing the time spent on data transfer and increasing overall inference speed.

6. Dynamic Batching: TensorRT dynamically batches input data to maximize GPU utilization and reduce latency.

7. Multi-Streaming: TensorRT supports multi-streaming, allowing multiple inference requests to be processed concurrently, increasing overall throughput.

8. Profiling and Monitoring: TensorRT provides profiling and monitoring tools to help developers identify performance bottlenecks and optimize their models further.

Overall, TensorRT optimizes LLM inference on NVIDIA hardware by applying a combination of model, engine, memory, execution, I/O, dynamic batching, multi-streaming, and profiling optimizations.
```
</details>


现在，尝试使用相同的提示在Llama-2-7b-chat模型上运行推理，并观察名为`llama2_results.txt`的新文件下的输出。

```bash
python3 triton-client.py --model-name llama2 --input-prompts prompts.txt --results-file llama2_results.txt
```

输出应该如下所示：

```text
python3 triton-client.py --model-name llama2 --input-prompts prompts.txt --results-file llama2_results.txt
Loading inputs from `prompts.txt`...
Model llama2 - Request 11: 0.00 ms
Model llama2 - Request 15: 0.02 ms
Model llama2 - Request 3: 0.00 ms
Model llama2 - Request 8: 0.03 ms
Model llama2 - Request 5: 0.02 ms
Model llama2 - Request 0: 0.00 ms
Model llama2 - Request 14: 0.00 ms
Model llama2 - Request 16: 0.01 ms
Model llama2 - Request 19: 0.02 ms
Model llama2 - Request 4: 0.01 ms
Model llama2 - Request 1: 0.01 ms
Model llama2 - Request 10: 0.01 ms
Model llama2 - Request 9: 0.01 ms
Model llama2 - Request 7: 0.01 ms
Model llama2 - Request 18: 0.01 ms
Model llama2 - Request 12: 0.00 ms
Model llama2 - Request 2: 0.00 ms
Model llama2 - Request 6: 0.00 ms
Model llama2 - Request 17: 0.01 ms
Model llama2 - Request 13: 0.01 ms
Storing results into `llama2_results.txt`...
Total time for all requests: 0.00 seconds (0.18 milliseconds)
PASS: vLLM example
```

## 可观测性

### 使用AWS CloudWatch和Neuron Monitor进行可观测性

此蓝图部署了CloudWatch可观测性代理作为托管附加组件，为容器化工作负载提供全面监控。它包括容器洞察，用于跟踪关键性能指标，如CPU和内存利用率。此外，该蓝图使用NVIDIA的DCGM插件集成了GPU指标，这对于监控高性能GPU工作负载至关重要。对于在AWS Inferentia或Trainium上运行的机器学习模型，添加了[Neuron Monitor插件](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/tools/neuron-sys-tools/neuron-monitor-user-guide.html#neuron-monitor-user-guide)来捕获和报告Neuron特定指标。

所有指标，包括容器洞察、GPU性能和Neuron指标，都发送到Amazon CloudWatch，您可以在那里实时监控和分析它们。部署完成后，您应该能够直接从CloudWatch控制台访问这些指标，使您能够有效地管理和优化工作负载。

除了部署CloudWatch EKS附加组件外，我们还部署了Kube Prometheus堆栈，它提供Prometheus服务器和Grafana部署，用于监控和可观测性。

首先，让我们验证Kube Prometheus堆栈部署的服务：

```bash
kubectl get svc -n monitoring
```

您应该看到类似这样的输出：

```text
kubectl get svc -n monitoring
NAME                                             TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
kube-prometheus-stack-grafana                    ClusterIP   172.20.252.10    <none>        80/TCP              11d
kube-prometheus-stack-kube-state-metrics         ClusterIP   172.20.34.181    <none>        8080/TCP            11d
kube-prometheus-stack-operator                   ClusterIP   172.20.186.93    <none>        443/TCP             11d
kube-prometheus-stack-prometheus                 ClusterIP   172.20.147.64    <none>        9090/TCP,8080/TCP   11d
kube-prometheus-stack-prometheus-node-exporter   ClusterIP   172.20.171.165   <none>        9100/TCP            11d
prometheus-operated                              ClusterIP   None             <none>        9090/TCP            11d
```

要公开NVIDIA Triton服务器指标，我们在端口`8080`上部署了一个指标服务(`nvidia-triton-server-triton-inference-server-metrics`)。通过运行以下命令进行验证

```bash
kubectl get svc -n triton-vllm
```

输出应该是：

```text
kubectl get svc -n triton-vllm
NAME                                                   TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
nvidia-triton-server-triton-inference-server           ClusterIP   172.20.193.97   <none>        8000/TCP,8001/TCP,8002/TCP   34m
nvidia-triton-server-triton-inference-server-metrics   ClusterIP   172.20.5.247    <none>        8080/TCP                     34m
```
这确认了NVIDIA Triton服务器指标正在被Prometheus服务器抓取。您可以使用Grafana仪表板可视化这些指标。

在下面的Grafana仪表板中，您可以看到几个重要指标：

- **平均GPU功率使用**：这个仪表显示了GPU的当前功率使用情况，这对于监控推理任务的效率和性能至关重要。
- **计算时间（毫秒）**：这个条形图显示了计算推理请求所需的时间，有助于识别任何延迟问题。
- **累计推理请求**：这个图表显示了随时间处理的推理请求总数，提供了工作负载和性能趋势的洞察。
- **队列时间（毫秒）**：这个折线图表示请求在被处理前在队列中花费的时间，突出了系统中潜在的瓶颈。

![NVIDIA Triton服务器](../../../../../../../docs/gen-ai/inference/img/triton-observability.png)

要创建新的Grafana仪表板来监控这些指标，请按照以下步骤操作：

```bash
- 端口转发Grafana服务：
kubectl port-forward svc/kube-prometheus-stack-grafana 8080:80 -n monitoring

- Grafana管理员用户
admin

- 从Terraform输出获取密钥名称
terraform output grafana_secret_name

- 获取管理员用户密码
aws secretsmanager get-secret-value --secret-id <grafana_secret_name_output> --region $AWS_REGION --query "SecretString" --output text
```

**登录Grafana：**

- 打开您的网络浏览器并导航至[http://localhost:8080](http://localhost:8080)。
- 使用用户名`admin`和从AWS Secrets Manager检索的密码登录。

**导入开源Grafana仪表板：**
- 登录后，点击左侧边栏上的"+"图标，选择"导入"。
- 输入以下URL以导入仪表板JSON：[Triton服务器Grafana仪表板](https://github.com/triton-inference-server/server/blob/main/deploy/k8s-onprem/dashboard.json)
- 按照提示完成导入过程。

您现在应该可以在新的Grafana仪表板上看到显示的指标，使您能够监控NVIDIA Triton推理服务器部署的性能和健康状况。

![triton-grafana-dash2](../../../../../../../docs/gen-ai/inference/img/triton-grafana-dash2.png)


## 结论
在Amazon EKS上使用NVIDIA Triton推理服务器和vLLM后端部署和管理多个大型语言模型为现代AI应用提供了一个强大且可扩展的解决方案。通过遵循此蓝图，您已经设置了必要的基础设施，部署了Triton服务器，并使用Kube Prometheus堆栈和Grafana配置了强大的可观测性。

## 清理

最后，我们将提供在不再需要资源时清理和取消配置资源的说明。

**清理EKS集群：**
此脚本将使用`-target`选项清理环境，以确保所有资源按正确顺序删除。

```bash
export AWS_DEAFULT_REGION="DEPLOYED_EKS_CLUSTER_REGION>"
cd data-on-eks/ai-ml/nvidia-triton-server/ && chmod +x cleanup.sh
./cleanup.sh
```
