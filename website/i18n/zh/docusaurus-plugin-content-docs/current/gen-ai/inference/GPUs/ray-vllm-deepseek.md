---
title: EKS上的DeepSeek-R1
sidebar_position: 1
---
import CollapsibleContent from '../../../../../../../src/components/CollapsibleContent';

:::caution

**EKS上的AI**内容**正在迁移**到一个新的仓库。
🔗 👉 [阅读完整的迁移公告 »](https://awslabs.github.io/data-on-eks/docs/migration/migration-announcement)

:::

# 使用Ray和vLLM在EKS上部署DeepSeek-R1

在本指南中，我们将探索使用[Ray](https://docs.ray.io/en/latest/serve/getting_started.html)和[vLLM](https://github.com/vllm-project/vllm)后端在[Amazon EKS](https://aws.amazon.com/eks/)上部署[DeepSeek-R1-Distill-Llama-8B](https://huggingface.co/deepseek-ai/DeepSeek-R1-Distill-Llama-8B)模型推理。

![alt text](../../../../../../../docs/gen-ai/inference/img/dseek0.png)

## 了解GPU内存需求

部署像`DeepSeek-R1-Distill-Llama`这样的8B参数模型需要仔细规划内存。每个模型参数通常消耗2字节（`BF16`精度），这意味着完整的模型权重需要大约`14.99 GiB`的GPU内存。以下是部署期间观察到的实际内存使用情况：

Ray部署的日志示例

```log
INFO model_runner.py:1115] Loading model weights took 14.99 GiB
INFO worker.py:266] vLLM instance can use total GPU memory (22.30 GiB) x utilization (0.90) = 20.07 GiB
INFO worker.py:266] Model weights: 14.99 GiB | Activation memory: 0.85 GiB | KV Cache: 4.17 GiB
```

G5实例提供单个`A10G` GPU，内存为`24 GiB`，非常适合每个实例运行一个大型LLM推理进程。对于此部署，我们使用`G5.4xlarge`，它有1个NVIDIA A10G GPU（24 GiB）、16个vCPU和64 GiB RAM。

使用vLLM，我们优化了内存利用率，使我们能够在防止内存不足(OOM)崩溃的同时最大化推理速度。


<CollapsibleContent header={<h2><span>部署EKS集群和附加组件</span></h2>}>

我们的技术栈包括：

- [Amazon EKS](https://aws.amazon.com/eks/) – 一个托管的Kubernetes服务，简化了在AWS上使用Kubernetes部署、管理和扩展容器化应用程序的过程。

- [Ray](https://docs.ray.io/en/latest/serve/getting_started.html) – 一个开源分布式计算框架，使机器学习推理工作负载的可扩展和高效执行成为可能。

- [vLLM](https://github.com/vllm-project/vllm) – 一个高吞吐量和内存高效的大型语言模型(LLM)推理和服务引擎，针对GPU执行进行了优化。
AWSLABS.GITHUB.IO

- [Karpenter](https://karpenter.sh/) – 一个开源Kubernetes集群自动缩放器，动态配置和管理计算资源，如G5实例，以提高应用程序可用性和集群效率


### 先决条件
在我们开始之前，请确保您已经准备好所有必要的先决条件，以使部署过程顺利进行。确保您已在计算机上安装了以下工具：

:::info

为了简化演示过程，我们假设使用具有管理权限的IAM角色，因为为每个可能创建各种AWS服务的蓝图创建最小IAM角色的复杂性。但是，对于生产部署，强烈建议创建只具有必要权限的IAM角色。使用[IAM Access Analyzer](https://aws.amazon.com/iam/access-analyzer/)等工具可以帮助确保最小权限方法。

:::

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [envsubst](https://pypi.org/project/envsubst/)

### 部署

克隆仓库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

**重要提示：**

**步骤1**：确保在部署蓝图之前更新`variables.tf`文件中的区域。
此外，确认您的本地区域设置与指定区域匹配，以防止任何差异。

例如，将您的`export AWS_DEFAULT_REGION="<REGION>"`设置为所需区域：


**步骤2**：运行安装脚本。

```bash
cd data-on-eks/ai-ml/jark-stack/terraform && chmod +x install.sh
```

```bash
./install.sh
```

### 验证资源

安装完成后，验证Amazon EKS集群。

创建k8s配置文件以与EKS进行身份验证。

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
验证Karpenter自动缩放器节点池

```bash
kubectl get nodepools
```

```text
NAME                NODECLASS
g5-gpu-karpenter    g5-gpu-karpenter
x86-cpu-karpenter   x86-cpu-karpenter
```

验证NVIDIA设备插件

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

验证[Kuberay Operator](https://github.com/ray-project/kuberay)，它用于创建Ray集群

```bash
kubectl get pods -n kuberay-operator
```

```text
NAME                                READY   STATUS    RESTARTS   AGE
kuberay-operator-7894df98dc-447pm   1/1     Running   0          9h
```

</CollapsibleContent>

## 使用RayServe和vLLM部署DeepSeek-R1-Distill-Llama-8B

随着EKS集群的部署和所有必要组件的就位，我们现在可以继续使用`RayServe`和`vLLM`部署`DeepSeek-R1-Distill-Llama-8B`。本指南概述了导出Hugging Face Hub令牌、创建Docker镜像（如果需要）和部署RayServe集群的步骤。

**步骤1：导出Hugging Face Hub令牌**

在部署模型之前，您需要通过Hugging Face进行身份验证以访问所需的模型文件。请按照以下步骤操作：

1. 创建Hugging Face账户（如果您还没有）。
2. 生成访问令牌：
 - 导航到Hugging Face设置 → 访问令牌。
 - 创建一个具有读取权限的新令牌。
 - 复制生成的令牌。

3. 在终端中将令牌导出为环境变量：

```bash
export HUGGING_FACE_HUB_TOKEN=$(echo -n "Your-Hugging-Face-Hub-Token-Value" | base64)
```

> 注意：令牌必须在用于Kubernetes密钥之前进行base64编码。


**步骤2：创建Docker镜像**

要高效部署模型，您需要一个包含Ray、vLLM和Hugging Face依赖项的Docker镜像。请按照以下步骤操作：

- 使用提供的Dockerfile：

```text
gen-ai/inference/vllm-ray-gpu-deepseek/Dockerfile
```

- 此Dockerfile基于Ray镜像，并包含vLLM和Hugging Face库。此部署不需要额外的包。

- 构建并将Docker镜像推送到Amazon ECR

**或者**

- 使用预构建镜像（用于PoC部署）：

如果您想跳过构建和推送自定义镜像，可以使用公共ECR镜像：

```public.ecr.aws/data-on-eks/ray-2.41.0-py310-cu118-vllm0.7.0```

> 注意：如果使用自定义镜像，请在RayServe YAML文件中将镜像引用替换为您的ECR镜像URI。


**步骤3：部署RayServe集群**

RayServe集群在YAML配置文件中定义，包括多个资源：
- 用于隔离部署的命名空间。
- 用于安全存储Hugging Face Hub令牌的密钥。
- 包含服务脚本（OpenAI兼容API接口）的ConfigMap。
- RayServe定义，包括：
  - 部署在x86节点上的Ray头部pod。
  - 部署在GPU实例（g5.4xlarge）上的Ray工作节点pod。

**部署步骤**

> 注意：确保`ray-vllm-deepseek.yml`中的image:字段正确设置为您的自定义ECR镜像URI或默认公共ECR镜像。

导航到包含RayServe配置的目录，并使用kubectl应用配置

```sh
cd gen-ai/inference/vllm-ray-gpu-deepseek/
envsubst < ray-vllm-deepseek.yml | kubectl apply -f -
```

**输出**

```text
namespace/rayserve-vllm created
secret/hf-token created
configmap/vllm-serve-script created
rayservice.ray.io/vllm created
```
**步骤4：监控部署**

要监控部署并检查pod的状态，请运行：

```bash
kubectl get pod -n rayserve-vllm
```

:::info

注意：首次部署时，镜像拉取过程可能需要长达8分钟。后续更新将利用本地缓存。这可以通过构建仅包含必要依赖项的精简镜像来优化。

:::


```text
NAME                                           READY   STATUS            RESTARTS   AGE
vllm-raycluster-7qwlm-head-vkqsc               2/2     Running           0          8m47s
vllm-raycluster-7qwlm-worker-gpu-group-vh2ng   0/1     PodInitializing   0          8m47s
```

此部署还创建了一个具有多个端口的DeepSeek-R1服务：

- `8265` - Ray仪表板
- `8000` - DeepSeek-R1模型端点


运行以下命令验证服务：

```bash
kubectl get svc -n rayserve-vllm

NAME             TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                                         AGE
vllm             ClusterIP   172.20.208.16    <none>        6379/TCP,8265/TCP,10001/TCP,8000/TCP,8080/TCP   48m
vllm-head-svc    ClusterIP   172.20.239.237   <none>        6379/TCP,8265/TCP,10001/TCP,8000/TCP,8080/TCP   37m
vllm-serve-svc   ClusterIP   172.20.196.195   <none>        8000/TCP                                        37m
```

要访问Ray仪表板，您可以将相关端口转发到本地计算机：

```bash
kubectl -n rayserve-vllm port-forward svc/vllm 8265:8265
```

然后，您可以在[http://localhost:8265](http://localhost:8265)访问Web UI，它显示了Ray生态系统中作业和角色的部署情况。

:::info

模型部署大约需要4分钟

:::

![alt text](../../../../../../../docs/gen-ai/inference/img/dseek1.png)

![alt text](../../../../../../../docs/gen-ai/inference/img/dseek2.png)

![alt text](../../../../../../../docs/gen-ai/inference/img/dseek3.png)


## 测试DeepSeek-R1模型

现在是时候测试DeepSeek-R1-Distill-Llama-8B聊天模型了。

首先，使用kubectl执行端口转发到`vllm-serve-svc`服务：

```bash
kubectl -n rayserve-vllm port-forward svc/vllm-serve-svc 8000:8000
```

**运行测试推理请求：**

```sh
curl -X POST http://localhost:8000/v1/chat/completions -H "Content-Type: application/json" -d '{
    "model": "deepseek-ai/DeepSeek-R1-Distill-Llama-8B",
    "messages": [{"role": "user", "content": "Explain about DeepSeek model?"}],
    "stream": false
}'
```

**响应：**

```
{"id":"chatcmpl-b86feed9-1482-4d1c-981d-085651d12813","object":"chat.completion","created":1739001265,"model":"deepseek-ai/DeepSeek-R1-Distill-Llama-8B","choices":[{"index":0,"message":{"role":"assistant","content":"<think>\n\n</think>\n\nDeepSeek is a powerful AI search engine developed by the Chinese Company DeepSeek Inc. It is designed to solve complex STEM (Science, Technology, Engineering, and Mathematics) problems through precise reasoning and efficient computation. The model works bymidtTeX, combining large-scale dataset and strong reasoning capabilities to provide accurate and reliable answers.\n\n### Key Features:\n1. **AI-powered Search**: DeepSeek uses advanced AI techniques to understand and analyze vast amounts of data, providing more accurate and relevant search results compared to traditional search engines.\n2. **Reasoning and Problem-solving**: The model is equipped with strong reasoning capabilities, enabling it to solve complex STEM problems, answer research-level questions, and assist in decision-making.\n3. **Customization**: DeepSeek can be tailored to specific domains or industries, allowing it to be adapted for various use cases such as academic research, business analysis, and technical problem-solving.\n4. **Efficiency**: The model is highly efficient, fast, and scalable, making it suitable for a wide range of applications and handling large-scale data processing tasks.\n5. **Domain Expertise**: It can be trained on domain-specific data and knowledge, making it highly specialized in particular fields like mathematics, programming, or engineering.\n\n### Applications:\n- **Education and Research**: Assisting students and researchers with complex STEM problems and research questions.\n- **Business Analysis**: aiding in market research, data analysis, and strategic decision-making.\n- **Technical Support**: solving technical issues and providing troubleshooting assistance.\n- **Custom Problem Solving**: addressing specific challenges in various fields by leveraging domain-specific knowledge.\n\nDeepSeek is a valuable tool for any individual or organizationengaged in STEM fields or requires advanced AI-powered search and reasoning capabilities.","tool_calls":[]},"logprobs":null,"finish_reason":"stop","stop_reason":null}],"usage":{"prompt_tokens":10,"total_tokens":359,"completion_tokens":349,"prompt_tokens_details":null},"prompt_logprobs":null}%
```
## 部署Open Web Ui

现在，让我们部署开源的Open WebUI，它提供了一个ChatGPT风格的聊天界面，用于与部署在EKS上的DeepSeek模型交互。Open WebUI将使用模型服务发送请求并接收响应。

**部署Open WebUI**

1. 验证Open WebUI的YAML文件`gen-ai/inference/vllm-ray-gpu-deepseek/open-webui.yaml`。这作为EKS中的容器部署，它与模型服务通信。
2. 应用Open WebUI部署：

```bash
cd gen-ai/inference/vllm-ray-gpu-deepseek/
kubectl apply -f open-webui.yaml
```

**输出：**

```text
namespace/openai-webui created
deployment.apps/open-webui created
service/open-webui created
```

**访问Open WebUI**

要打开Web UI，请端口转发Open WebUI服务：

```bash
kubectl -n open-webui port-forward svc/open-webui 8080:80
```

然后，打开浏览器并导航至：[http://localhost:8080](http://localhost:8080)

您将看到一个注册页面。使用您的姓名、电子邮件和密码注册。

![alt text](../../../../../../../docs/gen-ai/inference/img/dseek4.png)

![alt text](../../../../../../../docs/gen-ai/inference/img/dseek5.png)

![alt text](../../../../../../../docs/gen-ai/inference/img/dseek6.png)

![alt text](../../../../../../../docs/gen-ai/inference/img/dseek7.png)

![alt text](../../../../../../../docs/gen-ai/inference/img/dseek8.png)

提交请求后，您可以监控GPU和CPU使用率恢复正常：

![alt text](../../../../../../../docs/gen-ai/inference/img/dseek9.png)


## 关键要点

**1. 模型初始化和内存分配**
  - 一旦部署，模型会自动检测CUDA并初始化其执行环境。
  - GPU内存动态分配，90%的利用率保留给模型权重（14.99 GiB）、激活内存（0.85 GiB）和KV缓存（4.17 GiB）。
  - 在首次模型加载期间预期会有一些初始延迟，因为权重被获取并针对推理进行优化。

 **2. 推理执行和优化**
   - 模型支持多种任务，但默认为文本生成（generate）。
   - 启用了Flash Attention，减少了内存开销并提高了推理速度。
   - 应用了CUDA Graph Capture，允许更快的重复推理—但如果出现OOM问题，降低gpu_memory_utilization或启用eager执行可能有所帮助。

 **3. 令牌生成和性能指标**
  - 模型最初会显示提示吞吐量为0令牌/秒，因为它在等待输入。
  - 一旦推理开始，令牌生成吞吐量稳定在约29令牌/秒。
  - GPU KV缓存利用率从约12.5%开始，随着处理更多令牌而增加—确保随着时间的推移文本生成更加流畅。

**4. 系统资源利用**
  - 预期有8个CPU和8个CUDA块处理并行执行。
  - 推理并发限制为每个请求8192个令牌的4个请求，这意味着如果模型完全利用，同时请求可能会排队。
  - 如果遇到内存峰值，降低max_num_seqs将有助于减少GPU压力。

**5. 监控和可观测性**
  - 您可以在日志中跟踪平均提示吞吐量、生成速度和GPU KV缓存使用情况。
  - 如果推理速度变慢，请检查日志中的待处理或交换请求，这可能表明内存压力或调度延迟。
  - 默认情况下，实时可观测性（例如，跟踪请求延迟）是禁用的，但可以启用以进行更深入的监控。

**部署后预期什么？**

- 由于内存分析和CUDA图优化，模型将需要几分钟来初始化。
- 一旦运行，您应该看到稳定的吞吐量约为29令牌/秒，内存使用效率高。
- 如果性能下降，调整KV缓存大小，降低内存利用率，或启用eager执行以获得更好的稳定性。

## 清理

最后，我们将提供在不再需要资源时清理和取消配置资源的说明。

删除RayCluster

```bash
cd data-on-eks/gen-ai/inference/vllm-rayserve-gpu

kubectl delete -f open-webui.yaml

kubectl delete -f ray-vllm-deepseek.yml
```

```bash
cd data-on-eks/ai-ml/jark-stack/terraform/monitoring

kubectl delete -f serviceMonitor.yaml
kubectl delete -f podMonitor.yaml
```

销毁EKS集群和资源

```bash
export AWS_DEAFULT_REGION="DEPLOYED_EKS_CLUSTER_REGION>"

cd data-on-eks/ai-ml/jark-stack/terraform/ && chmod +x cleanup.sh
./cleanup.sh
```
