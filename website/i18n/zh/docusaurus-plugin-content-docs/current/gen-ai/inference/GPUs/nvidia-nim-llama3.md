---
title: Amazon EKS上的NVIDIA NIM LLM
sidebar_position: 4
---
import CollapsibleContent from '../../../../../../../src/components/CollapsibleContent';

:::caution

**EKS上的AI**内容**正在迁移**到一个新的仓库。
🔗 👉 [阅读完整的迁移公告 »](https://awslabs.github.io/data-on-eks/docs/migration/migration-announcement)

:::

:::warning
在EKS上部署ML模型需要访问GPU或Neuron实例。如果您的部署不起作用，通常是因为缺少对这些资源的访问。此外，一些部署模式依赖于Karpenter自动扩展和静态节点组；如果节点未初始化，请检查Karpenter或节点组的日志以解决问题。
:::

:::warning

注意：在实施NVIDIA NIM之前，请注意它是[NVIDIA AI Enterprise](https://www.nvidia.com/en-us/data-center/products/ai-enterprise/)的一部分，这可能会为生产使用引入潜在的成本和许可。

对于评估，NVIDIA还提供90天的免费评估许可，让您试用NVIDIA AI Enterprise，您可以使用公司电子邮件[注册](https://enterpriseproductregistration.nvidia.com/?LicType=EVAL&ProductFamily=NVAIEnterprise)。
:::

:::info

我们正在积极增强此蓝图，以纳入可观测性、日志记录和可扩展性方面的改进。
:::

# Amazon EKS上的NVIDIA NIM LLM部署

## 什么是NVIDIA NIM？

NVIDIA NIM使IT和DevOps团队能够在自己管理的环境中轻松自托管大型语言模型(LLM)，同时仍然为开发人员提供行业标准API，使他们能够构建强大的副驾驶、聊天机器人和AI助手，从而转变他们的业务。利用NVIDIA的尖端GPU加速和可扩展部署，NIM提供了具有无与伦比性能的推理最快路径。

## 为什么选择NIM？

NIM抽象了模型推理内部结构，如执行引擎和运行时操作。无论是使用TRT-LLM、vLLM还是其他，它们也是可用的最高性能选项。

NIM以每个模型/模型系列为基础打包为容器镜像。每个NIM容器都带有一个模型，如`meta/llama3-8b-instruct`。这些容器包括一个可以在任何具有足够GPU内存的NVIDIA GPU上运行的运行时，但某些模型/GPU组合经过了优化。NIM自动从NVIDIA NGC目录下载模型，如果可用，则利用本地文件系统缓存。

## Amazon EKS上此部署模式的概述

此模式结合了NVIDIA NIM、Amazon Elastic Kubernetes Service (EKS)和各种AWS服务的功能，提供高性能和成本优化的模型服务基础设施。

1. NVIDIA NIM容器镜像：NVIDIA NIM提供了一种简化的方法，可以在容器化环境中托管Llama3等LLM模型。这使客户能够利用他们的私有模型，同时确保与现有基础设施的无缝集成。我们将提供NIM部署的详细设置步骤。

2. Karpenter用于实例级扩展：Karpenter是一个开源节点配置项目，能够在实例级别快速高效地扩展Amazon EKS集群。这确保了模型服务基础设施能够适应动态工作负载需求，优化资源利用率和成本效益。

3. 竞价实例：考虑到LLM是无状态的，客户可以利用竞价实例显著降低成本。

4. Amazon Elastic File System (EFS)：Amazon EFS为Amazon EKS提供可扩展、弹性的文件存储。它允许多个pod同时访问同一文件系统，非常适合在集群中存储和共享模型工件、数据集和其他持久数据。EFS会随着您添加和删除文件自动增长和缩小，无需容量规划和管理。

5. 带有EKS蓝图的Terraform：为了简化此解决方案的部署和管理，我们利用Terraform和EKS蓝图。这种基础设施即代码的方法实现了整个堆栈的自动配置，确保一致性、可重复性和高效的资源管理。

通过结合这些组件，我们提出的解决方案提供了一个强大且经济高效的模型服务基础设施，专为大型语言模型量身定制。借助NVIDIA NIM的无缝集成、Amazon EKS与Karpenter的可扩展性，客户可以在最小化基础设施成本的同时实现高性能。

![EKS上的NIM架构](../../../../../../../docs/gen-ai/inference/img/nim-on-eks-arch.png)
## 部署解决方案

### 先决条件

在开始使用NVIDIA NIM之前，请确保您具备以下条件：

<details>
<summary>点击展开NVIDIA NIM账户设置详情</summary>

**NVIDIA AI Enterprise账户**

- 注册NVIDIA AI Enterprise账户。如果您没有，可以使用此[链接](https://enterpriseproductregistration.nvidia.com/?LicType=EVAL&ProductFamily=NVAIEnterprise)注册试用账户。

**NGC API密钥**

1. 登录您的NVIDIA AI Enterprise账户
2. 导航到NGC (NVIDIA GPU Cloud) [门户](https://org.ngc.nvidia.com/)
3. 生成个人API密钥：
    - 进入您的账户设置或直接导航至：https://org.ngc.nvidia.com/setup/personal-keys
    - 点击"Generate Personal Key"
    - 确保从"Services Included"下拉菜单中至少选择了"NGC Catalog"
    - 复制并安全存储您的API密钥，密钥应该有一个前缀为`nvapi-`

    ![NGC API密钥](../../../../../../../docs/gen-ai/inference/img/nim-ngc-api-key.png)

**验证NGC API密钥并测试镜像拉取**

要确保您的API密钥有效并正常工作：
1. 将您的NGC API密钥设置为环境变量：
```bash
export NGC_API_KEY=<your_api_key_here>
```

2. 使用NVIDIA容器注册表验证Docker：

```bash
echo "$NGC_API_KEY" | docker login nvcr.io --username '$oauthtoken' --password-stdin
```

3. 测试从NGC拉取镜像：
```bash
docker pull nvcr.io/nim/meta/llama3-8b-instruct:latest
```
您不必等待它完成，只需确保API密钥有效可以拉取镜像。
</details>

运行本教程需要以下条件
- 具有管理员同等权限的活跃AWS账户
- [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
- [kubectl](https://Kubernetes.io/docs/tasks/tools/)
- [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)

### 部署

克隆仓库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

**1. 配置NGC API密钥**

从[NVIDIA](https://docs.nvidia.com/ai-enterprise/deployment-guide-spark-rapids-accelerator/0.1.0/appendix-ngc.html)检索您的NGC API密钥并将其设置为环境变量：

```bash
export TF_VAR_ngc_api_key=<replace-with-your-NGC-API-KEY>
```

**2. 安装**

重要提示：在部署蓝图之前，请确保更新variables.tf文件中的区域。此外，确认您的本地区域设置与指定区域匹配，以防止任何差异。例如，将您的`export AWS_DEFAULT_REGION="<REGION>"`设置为所需区域：

运行安装脚本：

:::info


此模式部署了一个名为`nvcr.io/nim/meta/llama3-8b-instruct`的模型。您可以修改`variables.tf`文件中的`nim_models`变量来添加更多模型。使用此模式可以同时部署多个模型。
:::

:::caution

在通过这些变量启用额外模型之前，请确保为每个模型指定了足够的GPU。此外，验证您的AWS账户是否有权访问足够的GPU。
此模式使用Karpenter来扩展GPU节点，默认限制为G5实例。如果需要，您可以修改Karpenter节点池以包括其他实例，如p4和p5。

:::


```bash
cd data-on-eks/ai-ml/nvidia-triton-server
export TF_VAR_enable_nvidia_nim=true
export TF_VAR_enable_nvidia_triton_server=false
./install.sh
```

此过程将花费大约20分钟完成。

**3. 验证安装**

安装完成后，您可以从输出中找到configure_kubectl命令。运行以下命令配置EKS集群访问

```bash
# 创建k8s配置文件以与EKS进行身份验证
aws eks --region us-west-2 update-kubeconfig --name nvidia-triton-server
```

检查已部署的pod状态

```bash
kubectl get all -n nim
```

您应该看到类似以下的输出：
<details>
<summary>点击展开部署详情</summary>

```text
NAME                               READY   STATUS    RESTARTS   AGE
pod/nim-llm-llama3-8b-instruct-0   1/1     Running   0          4h2m

NAME                                     TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
service/nim-llm-llama3-8b-instruct       ClusterIP   172.20.5.230   <none>        8000/TCP   4h2m
service/nim-llm-llama3-8b-instruct-sts   ClusterIP   None           <none>        8000/TCP   4h2m

NAME                                          READY   AGE
statefulset.apps/nim-llm-llama3-8b-instruct   1/1     4h2m

NAME                                                             REFERENCE                                TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/nim-llm-llama3-8b-instruct   StatefulSet/nim-llm-llama3-8b-instruct   2/5       1         5         1          4h2m
```
</details>

`llama3-8b-instruct`模型以StatefulSet的形式部署在`nim`命名空间中。由于它正在运行，Karpenter配置了一个GPU
检查Karpenter配置的节点。

```bash
kubectl get node -l type=karpenter -L node.kubernetes.io/instance-type
```

```text
NAME                                         STATUS   ROLES    AGE     VERSION               INSTANCE-TYPE
ip-100-64-77-39.us-west-2.compute.internal   Ready    <none>   4m46s   v1.30.0-eks-036c24b   g5.2xlarge
```

**4. 验证已部署的模型**

一旦`nim`命名空间中的所有pod都准备就绪，状态为`1/1`，使用以下命令验证它是否已准备好提供流量。要验证，使用kubectl通过端口转发公开模型服务服务。

```bash
kubectl port-forward -n nim service/nim-llm-llama3-8b-instruct 8000
```

然后，您可以使用简单的HTTP请求和curl命令调用已部署的模型。

```bash
curl -X 'POST' \
  "http://localhost:8000/v1/completions" \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
      "model": "meta/llama3-8b-instruct",
      "prompt": "Once upon a time",
      "max_tokens": 64
      }'
```

您将看到类似以下的输出

```json
{
  "id": "cmpl-63a0b66aeda1440c8b6ca1ce3583b173",
  "object": "text_completion",
  "created": 1719742336,
  "model": "meta/llama3-8b-instruct",
  "choices": [
    {
      "index": 0,
      "text": ", there was a young man named Jack who lived in a small village at the foot of a vast and ancient forest. Jack was a curious and adventurous soul, always eager to explore the world beyond his village. One day, he decided to venture into the forest, hoping to discover its secrets.\nAs he wandered deeper into",
      "logprobs": null,
      "finish_reason": "length",
      "stop_reason": null
    }
  ],
  "usage": {
    "prompt_tokens": 5,
    "total_tokens": 69,
    "completion_tokens": 64
  }
}
```
### 测试使用NIM部署的Llama3模型
是时候测试刚刚部署的Llama3了。首先为测试设置一个简单的环境。

```bash
cd data-on-eks/gen-ai/inference/nvidia-nim/nim-client
python3 -m venv .venv
source .venv/bin/activate
pip install openai
```

我们在prompts.txt中准备了一些提示，它包含20个提示。您可以使用这些提示运行以下命令来验证生成的输出。

```bash
python3 client.py --input-prompts prompts.txt --results-file results.txt
```

您将看到类似以下的输出：

```text
Loading inputs from `prompts.txt`...
Model meta/llama3-8b-instruct - Request 14: 4.68s (4678.46ms)
Model meta/llama3-8b-instruct - Request 10: 6.43s (6434.32ms)
Model meta/llama3-8b-instruct - Request 3: 7.82s (7824.33ms)
Model meta/llama3-8b-instruct - Request 1: 8.54s (8540.69ms)
Model meta/llama3-8b-instruct - Request 5: 8.81s (8807.52ms)
Model meta/llama3-8b-instruct - Request 12: 8.95s (8945.85ms)
Model meta/llama3-8b-instruct - Request 18: 9.77s (9774.75ms)
Model meta/llama3-8b-instruct - Request 16: 9.99s (9994.51ms)
Model meta/llama3-8b-instruct - Request 6: 10.26s (10263.60ms)
Model meta/llama3-8b-instruct - Request 0: 10.27s (10274.35ms)
Model meta/llama3-8b-instruct - Request 4: 10.65s (10654.39ms)
Model meta/llama3-8b-instruct - Request 17: 10.75s (10746.08ms)
Model meta/llama3-8b-instruct - Request 11: 10.86s (10859.91ms)
Model meta/llama3-8b-instruct - Request 15: 10.86s (10857.15ms)
Model meta/llama3-8b-instruct - Request 8: 11.07s (11068.78ms)
Model meta/llama3-8b-instruct - Request 2: 12.11s (12105.07ms)
Model meta/llama3-8b-instruct - Request 19: 12.64s (12636.42ms)
Model meta/llama3-8b-instruct - Request 9: 13.37s (13370.75ms)
Model meta/llama3-8b-instruct - Request 13: 13.57s (13571.28ms)
Model meta/llama3-8b-instruct - Request 7: 14.90s (14901.51ms)
Storing results into `results.txt`...
Accumulated time for all requests: 206.31 seconds (206309.73 milliseconds)
PASS: NVIDIA NIM example
Actual execution time used with concurrency 20 is: 14.92 seconds (14.92 milliseconds)
```

`results.txt`的输出应该如下所示

<details>
<summary>点击展开部分输出</summary>

```text
传统机器学习模型和超大型语言模型(vLLM)之间的主要区别是：

1. **规模**：vLLM非常庞大，拥有数十亿参数，而传统模型通常只有数百万参数。
2. **训练数据**：vLLM在大量文本数据上训练，通常来源于互联网，而传统模型则在较小的、精心策划的数据集上训练。
3. **架构**：vLLM通常使用transformer架构，专为文本等顺序数据设计，而传统模型可能使用前馈网络或循环神经网络。
4. **训练目标**：vLLM通常使用掩码语言建模或下一句预测任务进行训练，而传统模型可能使用分类、回归或聚类目标。
5. **评估指标**：vLLM通常使用困惑度、准确性或流畅度等指标进行评估，而传统模型可能使用准确率、精确度或召回率等指标。
6. **可解释性**：由于其庞大的规模和复杂的架构，vLLM通常较难解释，而传统模型由于规模较小和架构较简单，可能更容易解释。

这些差异使vLLM在语言翻译、文本生成和对话AI等任务中表现出色，而传统模型更适合图像分类或回归等任务。

=========

TensorRT (Triton Runtime)通过以下方式优化NVIDIA硬件上的LLM (大型语言模型)推理：

1. **模型剪枝**：移除不必要的权重和连接，以减少模型大小和计算需求。
2. **量化**：将浮点模型转换为低精度整数格式（如INT8），以减少内存带宽并提高性能。
3. **内核融合**：将多个内核启动合并为单个启动，以减少开销并提高并行性。
4. **优化的Tensor Cores**：利用NVIDIA的Tensor Cores进行矩阵乘法，提供显著的性能提升。
5. **批处理**：同时处理多个输入批次以提高吞吐量。
6. **混合精度**：使用浮点和整数精度的组合，平衡准确性和性能。
7. **图优化**：重新排序和重组计算图，以最小化内存访问并优化数据传输。

通过应用这些优化，TensorRT可以显著加速NVIDIA硬件上的LLM推理，实现更快的推理时间和改进的性能。

=========
```
</details>

## Open WebUI部署

:::info

[Open WebUI](https://github.com/open-webui/open-webui)仅与使用OpenAI API服务器和Ollama工作的模型兼容。

:::

**1. 部署WebUI**

通过运行以下命令部署[Open WebUI](https://github.com/open-webui/open-webui)：

```sh
kubectl apply -f data-on-eks/gen-ai/inference/nvidia-nim/openai-webui-deployment.yaml
```

**2. 端口转发以访问WebUI**

使用kubectl端口转发在本地访问WebUI：

```sh
kubectl port-forward svc/open-webui 8081:80 -n openai-webui
```

**3. 访问WebUI**

打开浏览器并访问http://localhost:8081

**4. 注册**

使用您的姓名、电子邮件和虚拟密码注册。

**5. 开始新的聊天**

点击新建聊天并从下拉菜单中选择模型，如下面的截图所示：

![alt text](../../../../../../../docs/gen-ai/inference/img/openweb-ui-nim-1.png)

**6. 输入测试提示**

输入您的提示，您将看到流式结果，如下所示：

![alt text](../../../../../../../docs/gen-ai/inference/img/openweb-ui-nim-2.png)
## 使用NVIDIA GenAI-Perf工具进行性能测试

[GenAI-Perf](https://docs.nvidia.com/deeplearning/triton-inference-server/user-guide/docs/client/src/c%2B%2B/perf_analyzer/genai-perf/README.html)是一个命令行工具，用于测量通过推理服务器提供的生成式AI模型的吞吐量和延迟。

GenAI-Perf可以作为标准工具与部署了推理服务器的其他模型进行基准测试。但此工具需要GPU。为了简化操作，我们为您提供了一个预配置的清单`genaiperf-deploy.yaml`来运行该工具。

```bash
cd data-on-eks/gen-ai/inference/nvidia-nim
kubectl apply -f genaiperf-deploy.yaml
```

一旦pod准备就绪，状态为`1/1`，可以执行进入pod。

```bash
export POD_NAME=$(kubectl get po -l app=tritonserver -ojsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD_NAME -- bash
```

对已部署的NIM Llama3模型运行测试

```bash
genai-perf \
  -m meta/llama3-8b-instruct \
  --service-kind openai \
  --endpoint v1/completions \
  --endpoint-type completions \
  --num-prompts 100 \
  --random-seed 123 \
  --synthetic-input-tokens-mean 200 \
  --synthetic-input-tokens-stddev 0 \
  --output-tokens-mean 100 \
  --output-tokens-stddev 0 \
  --tokenizer hf-internal-testing/llama-tokenizer \
  --concurrency 10 \
  --measurement-interval 4000 \
  --profile-export-file my_profile_export.json \
  --url nim-llm-llama3-8b-instruct.nim:8000
```

您应该看到类似以下的输出

```bash
2024-07-11 03:32 [INFO] genai_perf.parser:166 - Model name 'meta/llama3-8b-instruct' cannot be used to create artifact directory. Instead, 'meta_llama3-8b-instruct' will be used.
2024-07-11 03:32 [INFO] genai_perf.wrapper:137 - Running Perf Analyzer : 'perf_analyzer -m meta/llama3-8b-instruct --async --input-data artifacts/meta_llama3-8b-instruct-openai-completions-concurrency10/llm_inputs.json --endpoint v1/completions --service-kind openai -u nim-llm.nim:8000 --measurement-interval 4000 --stability-percentage 999 --profile-export-file artifacts/meta_llama3-8b-instruct-openai-completions-concurrency10/my_profile_export.json -i http --concurrency-range 10'
                                                      LLM Metrics
┏━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┓
┃            Statistic ┃           avg ┃           min ┃           max ┃           p99 ┃           p90 ┃           p75 ┃
┡━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━┩
│ Request latency (ns) │ 3,934,624,446 │ 3,897,758,114 │ 3,936,987,882 │ 3,936,860,185 │ 3,936,429,317 │ 3,936,333,682 │
│     Num output token │           112 │           105 │           119 │           119 │           117 │           115 │
│      Num input token │           200 │           200 │           200 │           200 │           200 │           200 │
└──────────────────────┴───────────────┴───────────────┴───────────────┴───────────────┴───────────────┴───────────────┘
Output token throughput (per sec): 284.64
Request throughput (per sec): 2.54
```
您应该能够看到genai-perf收集的[指标](https://docs.nvidia.com/deeplearning/triton-inference-server/user-guide/docs/client/src/c%2B%2B/perf_analyzer/genai-perf/README.html#metrics)，包括请求延迟、输出令牌吞吐量、请求吞吐量。

要了解命令行选项，请参阅[此文档](https://docs.nvidia.com/deeplearning/triton-inference-server/user-guide/docs/client/src/c%2B%2B/perf_analyzer/genai-perf/README.html#command-line-options)。

## 可观测性

作为此蓝图的一部分，我们还部署了Kube Prometheus堆栈，它提供Prometheus服务器和Grafana部署，用于监控和可观测性。

首先，让我们验证Kube Prometheus堆栈部署的服务：

```bash
kubectl get svc -n monitoring
```

您应该看到类似这样的输出：

```text
NAME                                             TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
kube-prometheus-stack-grafana                    ClusterIP   172.20.225.77    <none>        80/TCP              10m
kube-prometheus-stack-kube-state-metrics         ClusterIP   172.20.237.248   <none>        8080/TCP            10m
kube-prometheus-stack-operator                   ClusterIP   172.20.118.163   <none>        443/TCP             10m
kube-prometheus-stack-prometheus                 ClusterIP   172.20.132.214   <none>        9090/TCP,8080/TCP   10m
kube-prometheus-stack-prometheus-node-exporter   ClusterIP   172.20.213.178   <none>        9100/TCP            10m
prometheus-adapter                               ClusterIP   172.20.171.163   <none>        443/TCP             10m
prometheus-operated                              ClusterIP   None             <none>        9090/TCP            10m
```

NVIDIA NIM LLM服务通过`nim-llm-llama3-8b-instruct`服务的端口`8000`上的`/metrics`端点公开指标。通过运行以下命令进行验证

```bash
kubectl get svc -n nim
kubectl port-forward -n nim svc/nim-llm-llama3-8b-instruct 8000

curl localhost:8000/metrics # 在另一个终端中运行此命令
```

### Grafana仪表板

我们提供了一个预配置的Grafana仪表板，以更好地可视化NIM状态。在下面的Grafana仪表板中，它包含几个重要指标：

- **首个令牌时间(TTFT)**：从初始推理请求到模型返回第一个令牌之间的延迟。
- **令牌间延迟(ITL)**：第一个令牌之后每个令牌之间的延迟。
- **总吞吐量**：NIM每秒生成的令牌总数。

您可以从此[文档](https://docs.nvidia.com/nim/large-language-models/latest/observability.html)中找到更多指标描述。

![NVIDIA LLM服务器](../../../../../../../docs/gen-ai/inference/img/nim-dashboard.png)

您可以监控首个令牌时间、令牌间延迟、KV缓存利用率等指标。

![NVIDIA NIM指标](../../../../../../../docs/gen-ai/inference/img/nim-dashboard-2.png)

要查看Grafana仪表板以监控这些指标，请按照以下步骤操作：

<details>
<summary>点击展开详情</summary>

**1. 检索Grafana密码。**

密码保存在AWS Secret Manager中。以下Terraform命令将显示密钥名称。

```bash
terraform output grafana_secret_name
```

然后使用输出的密钥名称运行以下命令，

```bash
aws secretsmanager get-secret-value --secret-id <grafana_secret_name_output> --region $AWS_REGION --query "SecretString" --output text
```

**2. 公开Grafana服务**

使用端口转发公开Grafana服务。

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
```

**3. 登录Grafana：**

- 打开网络浏览器并导航至[http://localhost:3000](http://localhost:3000)。
- 使用用户名`admin`和从AWS Secrets Manager检索的密码登录。

**4. 打开NIM监控仪表板：**

- 登录后，点击左侧边栏上的"Dashboards"并搜索"nim"
- 您可以从列表中找到仪表板`NVIDIA NIM Monitoring`
- 点击并进入仪表板。

现在您应该可以看到Grafana仪表板上显示的指标，使您能够监控NVIDIA NIM服务部署的性能。
</details>

:::info
在撰写本指南时，NVIDIA还提供了一个示例Grafana仪表板。您可以从[这里](https://docs.nvidia.com/nim/large-language-models/latest/observability.html#grafana)查看。
:::

## 清理

要删除此部署创建的所有资源，请运行：

```bash
./cleanup.sh
```
