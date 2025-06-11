---
title: Inferentia2上的Llama-3-8B与vLLM
sidebar_position: 1
description: 使用Ray和vLLM在AWS Inferentia2上部署Meta-Llama-3-8B-Instruct模型以获得优化的推理性能。
---
import CollapsibleContent from '../../../../../../../src/components/CollapsibleContent';

:::caution

**EKS上的AI**内容**正在迁移**到一个新的仓库。
🔗 👉 [阅读完整的迁移公告 »](https://awslabs.github.io/data-on-eks/docs/migration/migration-announcement)

:::

:::warning
在EKS上部署ML模型需要访问GPU或Neuron实例。如果您的部署不起作用，通常是因为缺少对这些资源的访问。此外，一些部署模式依赖于Karpenter自动扩展和静态节点组；如果节点未初始化，请检查Karpenter或节点组的日志以解决问题。
:::


:::danger

注意：使用此Llama-3 Instruct模型受Meta许可证的约束。
为了下载模型权重和分词器，请访问[网站](https://huggingface.co/meta-llama/Meta-Llama-3-8B)并在请求访问前接受许可证。

:::

:::info

我们正在积极增强此蓝图，以纳入可观测性、日志记录和可扩展性方面的改进。
:::


# 在AWS Neuron上使用RayServe和vLLM部署LLM

欢迎阅读这份关于使用[Ray Serve](https://docs.ray.io/en/latest/serve/index.html)和AWS Neuron在Amazon Elastic Kubernetes Service (EKS)上部署LLM的综合指南。

### 什么是AWS Neuron？

在本教程中，您将利用[AWS Neuron](https://aws.amazon.com/machine-learning/neuron/)，这是一个强大的SDK，可优化AWS Inferentia和Trainium加速器上的深度学习性能。Neuron与PyTorch和TensorFlow等框架无缝集成，提供了一个全面的工具包，用于在专门的EC2实例（如Inf1、Inf2、Trn1和Trn1n）上开发、分析和部署高性能机器学习模型。

### 什么是vLLM？

[vLLM](https://docs.vllm.ai/en/latest/)是一个高性能的LLM推理和服务库，旨在最大化吞吐量并最小化延迟。其核心是[PagedAttention](https://docs.vllm.ai/en/latest/dev/kernel/paged_attention.html)，这是一种创新的注意力算法，显著提高了内存效率，允许GPU资源的最佳利用。这个开源解决方案通过其Python API和OpenAI兼容服务器提供无缝集成，使开发人员能够以前所未有的效率在生产环境中部署和扩展Llama 3等大型语言模型。

### 什么是RayServe？

Ray Serve是一个建立在Ray之上的可扩展模型服务库，旨在部署具有框架无关部署、模型组合和内置扩展等功能的机器学习模型和AI应用程序。您还将遇到RayService，这是KubeRay项目的一部分的Kubernetes自定义资源，用于在Kubernetes集群上部署和管理Ray Serve应用程序。

### 什么是Llama-3-8B Instruct？

Meta开发并发布了Meta Llama 3系列大型语言模型(LLM)，这是一系列预训练和指令调整的生成文本模型，规模为8B和70B。Llama 3指令调整模型针对对话用例进行了优化，在常见行业基准测试中表现优于许多可用的开源聊天模型。此外，在开发这些模型时，我们非常注重优化有用性和安全性。

有关Llama3规模和模型架构的更多信息可以在[这里](https://huggingface.co/meta-llama/Meta-Llama-3-8B-Instruct)找到。

### 为什么选择AWS加速器？

**可扩展性和可用性**

部署像Llama-3这样的大型语言模型(`LLM`)的关键挑战之一是合适硬件的可扩展性和可用性。由于需求高，传统的`GPU`实例经常面临稀缺性，这使得有效配置和扩展资源变得具有挑战性。

相比之下，`Trn1/Inf2`实例，如`trn1.32xlarge`、`trn1n.32xlarge`、`inf2.24xlarge`和`inf2.48xlarge`，是专为生成式AI模型（包括LLM）的高性能深度学习(DL)训练和推理而构建的。它们提供了可扩展性和可用性，确保您可以根据需要部署和扩展`Llama-3`模型，而不会出现资源瓶颈或延迟。
**成本优化**

在传统GPU实例上运行LLM可能成本高昂，特别是考虑到GPU的稀缺性和其竞争性定价。**Trn1/Inf2**实例提供了一种经济高效的替代方案。通过提供针对AI和机器学习任务优化的专用硬件，Trn1/Inf2实例使您能够以较低的成本实现顶级性能。这种成本优化使您能够高效分配预算，使LLM部署变得可访问和可持续。

**性能提升**

虽然Llama-3可以在GPU上实现高性能推理，但Neuron加速器将性能提升到了新的水平。Neuron加速器是专为机器学习工作负载而构建的，提供硬件加速，显著增强了Llama-3的推理速度。这转化为在Trn1/Inf2实例上部署Llama-3时更快的响应时间和改进的用户体验。

## 解决方案架构

在本节中，我们将深入探讨我们的解决方案架构，该架构结合了Llama-3模型、[Ray Serve](https://docs.ray.io/en/latest/serve/index.html)和Amazon EKS上的[Inferentia2](https://aws.amazon.com/ec2/instance-types/inf2/)。

![Llama-3-inf2](../../../../../../../docs/gen-ai/inference/img/ray-vllm-inf2.png)

## 部署解决方案

要开始在[Amazon EKS](https://aws.amazon.com/eks/)上部署`Llama-3-8B-instruct`，我们将涵盖必要的先决条件，并一步步引导您完成部署过程。

这包括使用AWS Inferentia实例设置基础设施和部署**Ray集群**。

<CollapsibleContent header={<h2><span>先决条件</span></h2>}>
在我们开始之前，请确保您已经准备好所有先决条件，以使部署过程顺利无忧。
确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### 部署

克隆仓库：

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到以下目录并运行`install.sh`脚本：

**重要提示：** 确保在部署蓝图之前更新`variables.tf`文件中的区域。
此外，确认您的本地区域设置与指定区域匹配，以防止任何差异。
例如，将您的`export AWS_DEFAULT_REGION="<REGION>"`设置为所需区域。

```bash
cd data-on-eks/ai-ml/trainium-inferentia/
./install.sh
```

### 验证资源

验证Amazon EKS集群

```bash
aws eks --region us-west-2 describe-cluster --name trainium-inferentia
```

```bash
# 创建k8s配置文件以与EKS进行身份验证
aws eks --region us-west-2 update-kubeconfig --name trainium-inferentia

kubectl get nodes # 输出显示EKS托管节点组节点
```
验证Karpenter自动缩放器节点池

```bash
kubectl get nodepools
```

```text
NAME              NODECLASS
default           default
inferentia-inf2   inferentia-inf2
trainium-trn1     trainium-trn1
```

### 验证Neuron插件

Neuron设备插件将Neuron核心和设备作为资源公开给kubernetes。验证蓝图安装的插件状态。

```bash
kubectl get ds neuron-device-plugin --namespace kube-system
```
```bash
NAME                   DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
neuron-device-plugin   1         1         1       1            1           <none>          15d
```

### 验证Neuron调度器

Neuron调度器扩展对于调度需要多个Neuron核心或设备资源的pod是必需的。验证蓝图安装的调度器状态。

```bash
kubectl get pods -n kube-system | grep my-scheduler
```
```text
my-scheduler-c6fc957d9-hzrf7  1/1     Running   0  2d1h
```
</CollapsibleContent>
## 使用Llama3模型部署Ray集群

在本教程中，我们利用KubeRay操作符，它通过自定义资源定义扩展Kubernetes，用于Ray特定的构造，如RayCluster、RayJob和RayService。操作符监视与这些资源相关的用户事件，自动创建必要的Kubernetes工件以形成Ray集群，并持续监控集群状态以确保所需配置与实际状态匹配。它处理生命周期管理，包括设置、工作节点组的动态扩展和拆卸，抽象出在Kubernetes上管理Ray应用程序的复杂性。

每个Ray集群由一个头节点pod和一系列工作节点pod组成，具有可选的自动扩展支持，根据工作负载需求调整集群大小。KubeRay支持异构计算节点（包括GPU）和在同一Kubernetes集群中运行具有不同Ray版本的多个Ray集群。此外，KubeRay可以与AWS Inferentia加速器集成，使大型语言模型（如Llama 3）能够在专门的硬件上高效部署，可能提高机器学习推理任务的性能和成本效益。

在部署了具有所有必要组件的EKS集群后，我们现在可以继续使用`RayServe`和`vLLM`在AWS加速器上部署`NousResearch/Meta-Llama-3-8B-Instruct`的步骤。

**步骤1：** 要部署RayService集群，导航到包含`vllm-rayserve-deployment.yaml`文件的目录，并在终端中执行`kubectl apply`命令。
这将应用RayService配置并在您的EKS设置上部署集群。

```bash
cd data-on-eks/gen-ai/inference/vllm-rayserve-inf2

kubectl apply -f vllm-rayserve-deployment.yaml
```
**可选配置**

默认情况下，将配置一个`inf2.8xlarge`实例。如果您想使用`inf2.48xlarge`，请修改文件`vllm-rayserve-deployment.yaml`，更改`worker`容器下的`resources`部分。

```bash
limits:
    cpu: "30"
    memory: "110G"
    aws.amazon.com/neuron: "1"
requests:
    cpu: "30"
    memory: "110G"
    aws.amazon.com/neuron: "1"
```
更改为以下内容：

```bash
limits:
    cpu: "90"
    memory: "360G"
    aws.amazon.com/neuron: "12"
requests:
    cpu: "90"
    memory: "360G"
    aws.amazon.com/neuron: "12"
```

**步骤2：** 通过运行以下命令验证部署

要确保部署已成功完成，请运行以下命令：

:::info

部署过程可能需要长达**10分钟**。头部Pod预计在5到6分钟内准备就绪，而Ray Serve工作节点pod可能需要长达10分钟用于镜像检索和从Huggingface部署模型。

:::

根据RayServe配置，您将有一个在`x86`实例上运行的Ray头部pod和一个在`inf2`实例上运行的工作节点pod。您可以修改RayServe YAML文件以运行多个副本；但是，请注意，每个额外的副本可能会创建新的实例。

```bash
kubectl get pods -n vllm
```

```text
NAME                                                      READY   STATUS    RESTARTS   AGE
lm-llama3-inf2-raycluster-ksh7w-worker-inf2-group-dcs5n   1/1     Running   0          2d4h
vllm-llama3-inf2-raycluster-ksh7w-head-4ck8f              2/2     Running   0          2d4h
```

此部署还配置了一个具有多个端口的服务。端口**8265**指定用于Ray仪表板，端口**8000**用于vLLM推理服务器端点。

运行以下命令验证服务：

```bash
kubectl get svc -n vllm

NAME                         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                                         AGE
vllm                         ClusterIP   172.20.23.54    <none>        8080/TCP,6379/TCP,8265/TCP,10001/TCP,8000/TCP   2d4h
vllm-llama3-inf2-head-svc    ClusterIP   172.20.18.130   <none>        6379/TCP,8265/TCP,10001/TCP,8000/TCP,8080/TCP   2d4h
vllm-llama3-inf2-serve-svc   ClusterIP   172.20.153.10   <none>        8000/TCP                                        2d4h
```
要访问Ray仪表板，您可以将相关端口转发到本地计算机：

```bash
kubectl -n vllm port-forward svc/vllm 8265:8265
```

然后，您可以在[http://localhost:8265](http://localhost:8265)访问Web UI，它显示了Ray生态系统中作业和角色的部署情况。

![RayServe部署](../../../../../../../docs/gen-ai/inference/img/ray-dashboard-vllm-llama3-inf2.png)

一旦部署完成，控制器和代理状态应为`HEALTHY`，应用程序状态应为`RUNNING`

![RayServe部署日志](../../../../../../../docs/gen-ai/inference/img/ray-logs-vllm-llama3-inf2.png)

### 测试Llama3模型

现在是时候测试`Meta-Llama-3-8B-Instruct`聊天模型了。我们将使用Python客户端脚本向RayServe推理端点发送提示，并验证模型生成的输出。

首先，使用kubectl执行端口转发到`vllm-llama3-inf2-serve-svc`服务：

```bash
kubectl -n vllm port-forward svc/vllm-llama3-inf2-serve-svc 8000:8000
```

`openai-client.py`使用HTTP POST方法向推理端点发送提示列表，用于文本完成和问答，目标是vllm服务器。

要在虚拟环境中运行Python客户端应用程序，请按照以下步骤操作：

```bash
cd data-on-eks/gen-ai/inference/vllm-rayserve-inf2
python3 -m venv .venv
source .venv/bin/activate
pip3 install openai
python3 openai-client.py
```

您将在终端中看到类似以下的输出：

<details>
<summary>点击展开Python客户端终端输出</summary>

```text
Example 1 - Simple chat completion:
Handling connection for 8000
The capital of India is New Delhi.


Example 2 - Chat completion with different parameters:
The twin suns of Tatooine set slowly in the horizon, casting a warm orange glow over the bustling spaceport of Anchorhead. Amidst the hustle and bustle, a young farm boy named Anakin Skywalker sat atop a dusty speeder, his eyes fixed on the horizon as he dreamed of adventure beyond the desert planet.

As the suns dipped below the dunes, Anakin's uncle, Owen Lars, called out to him from the doorway of their humble moisture farm. "Anakin, it's time to head back! Your aunt and I have prepared a special dinner in your honor."

But Anakin was torn. He had received a strange message from an unknown sender, hinting at a great destiny waiting for him. Against his uncle's warnings, Anakin decided to investigate further, sneaking away into the night to follow the mysterious clues.

As he rode his speeder through the desert, the darkness seemed to grow thicker, and the silence was broken only by the distant


Example 3 - Streaming chat completion:
I'd be happy to help you with that. Here we go:

1...

(Pause)

2...

(Pause)

3...

(Pause)

4...

(Pause)

5...

(Pause)

6...

(Pause)

7...

(Pause)

8...

(Pause)

9...

(Pause)

10!

Let me know if you have any other requests!
```
</details>

## 可观测性

### 使用AWS CloudWatch和Neuron Monitor进行可观测性

此蓝图部署了CloudWatch可观测性代理作为托管附加组件，为容器化工作负载提供全面监控。它包括容器洞察，用于跟踪关键性能指标，如CPU和内存利用率。此外，该附加组件利用[Neuron Monitor插件](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/tools/neuron-sys-tools/neuron-monitor-user-guide.html#neuron-monitor-user-guide)来捕获和报告Neuron特定指标。

所有指标，包括容器洞察和Neuron指标，如Neuron核心利用率、NeuronCore内存使用情况，都发送到Amazon CloudWatch，您可以在那里实时监控和分析它们。部署完成后，您应该能够直接从CloudWatch控制台访问这些指标，使您能够有效地管理和优化工作负载。

![CloudWatch-neuron-monitor](../../../../../../../docs/gen-ai/inference/img/neuron-monitor-cwci.png)
## Open WebUI部署


:::info

[Open WebUI](https://github.com/open-webui/open-webui)仅与使用OpenAI API服务器和Ollama工作的模型兼容。

:::

**1. 部署WebUI**

通过运行以下命令部署[Open WebUI](https://github.com/open-webui/open-webui)：

```sh
kubectl apply -f openai-webui-deployment.yaml
```

**2. 端口转发以访问WebUI**

**注意** 如果您已经在运行端口转发以使用python客户端测试推理，请按`ctrl+c`中断该操作。

使用kubectl端口转发在本地访问WebUI：

```sh
kubectl port-forward svc/open-webui 8081:80 -n openai-webui
```

**3. 访问WebUI**

打开您的浏览器并访问http://localhost:8081

**4. 注册**

使用您的姓名、电子邮件和虚拟密码注册。

**5. 开始新的聊天**

点击新建聊天并从下拉菜单中选择模型，如下面的截图所示：

![alt text](../../../../../../../docs/gen-ai/inference/img/openweb-ui-ray-vllm-inf2-1.png)

**6. 输入测试提示**

输入您的提示，您将看到流式结果，如下所示：

![alt text](../../../../../../../docs/gen-ai/inference/img/openweb-ui-ray-vllm-inf2-2.png)

## 使用LLMPerf工具进行性能基准测试

[LLMPerf](https://github.com/ray-project/llmperf/blob/main/README.md)是一个开源工具，旨在对大型语言模型(LLM)的性能进行基准测试。

LLMPerf工具通过端口8000使用上面设置的端口转发连接到vllm服务，使用命令`kubectl -n vllm port-forward svc/vllm-llama3-inf2-serve-svc 8000:8000`。

在您的终端中执行以下命令。

克隆LLMPerf仓库：

```bash
git clone https://github.com/ray-project/llmperf.git
cd llmperf
pip install -e .
pip install pandas
pip install ray
```

使用以下命令创建`vllm_benchmark.sh`文件：

```bash
cat << 'EOF' > vllm_benchmark.sh
#!/bin/bash
model=${1:-NousResearch/Meta-Llama-3-8B-Instruct}
vu=${2:-1}
export OPENAI_API_KEY=EMPTY
export OPENAI_API_BASE="http://localhost:8000/v1"
export TOKENIZERS_PARALLELISM=true
#if you have more vllm servers, append the below line to the above
#;http://localhost:8001/v1;http://localhost:8002/v1"
max_requests=$(expr ${vu} \* 8 )
date_str=$(date '+%Y-%m-%d-%H-%M-%S')
python ./token_benchmark_ray.py \
       --model ${model} \
       --mean-input-tokens 512 \
       --stddev-input-tokens 20 \
       --mean-output-tokens 245 \
       --stddev-output-tokens 20 \
       --max-num-completed-requests ${max_requests} \
       --timeout 7200 \
       --num-concurrent-requests ${vu} \
       --results-dir "vllm_bench_results/${date_str}" \
       --llm-api openai \
       --additional-sampling-params '{}'
EOF
```

`--mean-input-tokens`：指定输入提示中的平均令牌数

`--stddev-input-tokens`：指定输入令牌长度的变异性，以创建更真实的测试环境

`--mean-output-tokens`：指定模型输出中预期的平均令牌数，以模拟真实的响应长度

`--stddev-output-tokens`：指定输出令牌长度的变异性，引入响应大小的多样性

`--max-num-completed-requests`：设置要处理的最大请求数

`--num-concurrent-requests`：指定同时请求的数量，以模拟并行工作负载
下面的命令执行基准测试脚本，指定模型为`NousResearch/Meta-Llama-3-8B-Instruct`，并将虚拟用户数设置为2。这导致基准测试使用2个并发请求测试模型的性能，计算要处理的最大请求数为16。

执行以下命令：

```bash
./vllm_benchmark.sh NousResearch/Meta-Llama-3-8B-Instruct 2
```

您应该看到类似以下的输出：

```bash
./vllm_benchmark.sh NousResearch/Meta-Llama-3-8B-Instruct 2
None of PyTorch, TensorFlow >= 2.0, or Flax have been found. Models won't be available and only tokenizers, configuration and file/data utilities can be used.
You are using the default legacy behaviour of the <class 'transformers.models.llama.tokenization_llama_fast.LlamaTokenizerFast'>. This is expected, and simply means that the `legacy` (previous) behavior will be used so nothing changes for you. If you want to use the new behaviour, set `legacy=False`. This should only be set if you understand what it means, and thoroughly read the reason why this was added as explained in https://github.com/huggingface/transformers/pull/24565 - if you loaded a llama tokenizer from a GGUF file you can ignore this message.
2024-09-03 09:54:45,976	INFO worker.py:1783 -- Started a local Ray instance.
  0%|                                                                                                                                                                                                                                                    | 0/16 [00:00<?, ?it/s]Handling connection for 8000
Handling connection for 8000
 12%|█████████████████████████████▌                                                                                                                                                                                                              | 2/16 [00:17<02:00,  8.58s/it]Handling connection for 8000
Handling connection for 8000
 25%|███████████████████████████████████████████████████████████                                                                                                                                                                                 | 4/16 [00:33<01:38,  8.20s/it]Handling connection for 8000
Handling connection for 8000
 38%|████████████████████████████████████████████████████████████████████████████████████████▌                                                                                                                                                   | 6/16 [00:47<01:17,  7.75s/it]Handling connection for 8000
Handling connection for 8000
 50%|██████████████████████████████████████████████████████████████████████████████████████████████████████████████████████                                                                                                                      | 8/16 [01:00<00:58,  7.36s/it]Handling connection for 8000
Handling connection for 8000
 62%|██████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████▉                                                                                        | 10/16 [01:15<00:43,  7.31s/it]Handling connection for 8000
Handling connection for 8000
 75%|████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████▎                                                          | 12/16 [01:29<00:28,  7.20s/it]Handling connection for 8000
Handling connection for 8000
 88%|█████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████▋                             | 14/16 [01:45<00:15,  7.52s/it]Handling connection for 8000
Handling connection for 8000
100%|███████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████| 16/16 [02:01<00:00,  7.58s/it]
\Results for token benchmark for NousResearch/Meta-Llama-3-8B-Instruct queried with the openai api.

inter_token_latency_s
    p25 = 0.051964785839225695
    p50 = 0.053331799814278796
    p75 = 0.05520852723583741
    p90 = 0.05562424625711179
    p95 = 0.05629651696856784
    p99 = 0.057518213120178636
    mean = 0.053548951905597324
    min = 0.0499955879607504
    max = 0.05782363715808134
    stddev = 0.002070751885022901
ttft_s
    p25 = 1.5284210312238429
    p50 = 1.7579061459982768
    p75 = 1.8209733433031943
    p90 = 1.842437624989543
    p95 = 1.852818323241081
    p99 = 1.8528624982456676
    mean = 1.5821313202395686
    min = 0.928935999982059
    max = 1.8528735419968143
    stddev = 0.37523908630204694
end_to_end_latency_s
    p25 = 13.74749460403109
    p50 = 14.441407957987394
    p75 = 15.53337344751344
    p90 = 16.104882833489683
    p95 = 16.366086292022374
    p99 = 16.395070491998922
    mean = 14.528114874927269
    min = 10.75658329098951
    max = 16.40231654199306
    stddev = 1.4182672949824733
request_output_throughput_token_per_s
    p25 = 18.111220396798153
    p50 = 18.703139371912407
    p75 = 19.243016652511997
    p90 = 19.37836414194298
    p95 = 19.571455249271224
    p99 = 19.915057038539217
    mean = 18.682678715983627
    min = 17.198769813363445
    max = 20.000957485856215
    stddev = 0.725563381521316
number_input_tokens
    p25 = 502.5
    p50 = 509.5
    p75 = 516.5
    p90 = 546.5
    p95 = 569.25
    p99 = 574.65
    mean = 515.25
    min = 485
    max = 576
    stddev = 24.054105678657024
number_output_tokens
    p25 = 259.75
    p50 = 279.5
    p75 = 291.75
    p90 = 297.0
    p95 = 300.5
    p99 = 301.7
    mean = 271.625
    min = 185
    max = 302
    stddev = 29.257192847799555
Number Of Errored Requests: 0
Overall Output Throughput: 35.827933968528434
Number Of Completed Requests: 16
Completed Requests Per Minute: 7.914131755588426
```

您可以尝试使用多个并发请求生成基准测试结果，以了解性能如何随着并发请求数量的增加而变化：

```
./vllm_benchmark.sh NousResearch/Meta-Llama-3-8B-Instruct 2
./vllm_benchmark.sh NousResearch/Meta-Llama-3-8B-Instruct 4
./vllm_benchmark.sh NousResearch/Meta-Llama-3-8B-Instruct 8
./vllm_benchmark.sh NousResearch/Meta-Llama-3-8B-Instruct 16
.
.
```

### 性能基准测试指标

您可以在`llmperf`目录下的`vllm_bench_results`目录中找到基准测试脚本的结果。结果存储在遵循日期时间命名约定的文件夹中。每次执行基准测试脚本时都会创建新文件夹。

您会发现，基准测试脚本的每次执行的结果包含以下格式的2个文件：

`NousResearch-Meta-Llama-3-8B-Instruct_512_245_summary_32.json` - 包含所有请求/响应对的性能指标摘要。

`NousResearch-Meta-Llama-3-8B-Instruct_512_245_individual_responses.json` - 包含每个请求/响应对的性能指标。

这些文件中的每一个都包含以下性能基准测试指标：

```results_inter_token_latency_s_*```：也称为令牌生成延迟(TPOT)。令牌间延迟指的是大型语言模型(LLM)在解码或生成阶段生成连续输出令牌之间的平均经过时间

```results_ttft_s_*```：生成第一个令牌所需的时间(TTFT)

```results_end_to_end_s_*```：端到端延迟 - 从用户提交输入提示到LLM生成完整输出响应的总时间

```results_request_output_throughput_token_per_s_*```：大型语言模型(LLM)在所有用户请求或查询中每秒生成的输出令牌数

```results_number_input_tokens_*```：请求中的输入令牌数（输入长度）

```results_number_output_tokens_*```：请求中的输出令牌数（输出长度）
## 结论

总之，在部署和扩展Llama-3方面，AWS Trn1/Inf2实例提供了令人信服的优势。
它们提供了运行大型语言模型所需的可扩展性、成本优化和性能提升，同时克服了与GPU稀缺性相关的挑战。无论您是构建聊天机器人、自然语言处理应用程序还是任何其他由LLM驱动的解决方案，Trn1/Inf2实例都使您能够在AWS云上充分发挥Llama-3的潜力。

## 清理

最后，我们将提供在不再需要资源时清理和取消配置资源的说明。

删除RayCluster

```bash
cd data-on-eks/gen-ai/inference/vllm-rayserve-inf2

kubectl delete -f vllm-rayserve-deployment.yaml
```

销毁EKS集群和资源

```bash
cd data-on-eks/ai-ml/trainium-inferentia/

./cleanup.sh
```
