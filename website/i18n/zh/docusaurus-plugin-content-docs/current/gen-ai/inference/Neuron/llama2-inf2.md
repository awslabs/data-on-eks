---
title: Inferentia2上的Llama-2
sidebar_position: 4
description: 在AWS Inferentia加速器上部署Llama-2模型以实现高效推理。
---
import CollapsibleContent from '../../../../../../../src/components/CollapsibleContent';

:::caution

**AI on EKS**内容**正在迁移**到一个新的仓库。
🔗 👉 [阅读完整的迁移公告 »](https://awslabs.github.io/data-on-eks/docs/migration/migration-announcement)

:::

:::warning
在EKS上部署ML模型需要访问GPU或Neuron实例。如果您的部署不起作用，通常是因为缺少对这些资源的访问。此外，一些部署模式依赖于Karpenter自动扩展和静态节点组；如果节点未初始化，请检查Karpenter或节点组的日志以解决问题。
:::

:::danger

注意：使用此Llama-2模型受Meta许可证的约束。
为了下载模型权重和分词器，请访问[网站](https://ai.meta.com/)并在请求访问前接受许可证。

:::

:::info

我们正在积极增强此蓝图，以纳入可观测性、日志记录和可扩展性方面的改进。

:::


# 使用Inferentia、Ray Serve和Gradio部署Llama-2-13b聊天模型
欢迎阅读这份关于使用[Ray Serve](https://docs.ray.io/en/latest/serve/index.html)在Amazon Elastic Kubernetes Service (EKS)上部署[Meta Llama-2-13b聊天](https://ai.meta.com/llama/#inside-the-model)模型的综合指南。
在本教程中，您不仅将学习如何利用Llama-2的强大功能，还将深入了解高效部署大型语言模型(LLM)的复杂性，特别是在[trn1/inf2](https://aws.amazon.com/machine-learning/neuron/)（由AWS Trainium和Inferentia提供支持）实例上，如`inf2.24xlarge`和`inf2.48xlarge`，
这些实例专为部署和扩展大型语言模型而优化。

### 什么是Llama-2？
Llama-2是一个在2万亿个文本和代码令牌上训练的预训练大型语言模型(LLM)。它是当今可用的最大和最强大的LLM之一。Llama-2可用于各种任务，包括自然语言处理、文本生成和翻译。

#### Llama-2-chat
Llama-2是一个经过严格训练过程的卓越语言模型。它首先使用公开可用的在线数据进行预训练。然后通过监督微调创建Llama-2-chat的初始版本。
之后，`Llama-2-chat`通过人类反馈强化学习(`RLHF`)进行迭代改进，包括拒绝采样和近端策略优化(`PPO`)等技术。
这个过程产生了一个高度能力和精细调整的语言模型，我们将指导您在**Amazon EKS**上使用**Ray Serve**有效地部署和利用它。

Llama-2有三种不同的模型大小：

- **Llama-2-70b：** 这是最大的Llama-2模型，拥有700亿参数。它是最强大的Llama-2模型，可用于最苛刻的任务。
- **Llama-2-13b：** 这是一个中等大小的Llama-2模型，拥有130亿参数。它在性能和效率之间取得了良好的平衡，可用于各种任务。
- **Llama-2-7b：** 这是最小的Llama-2模型，拥有70亿参数。它是最高效的Llama-2模型，可用于不需要最高性能水平的任务。

### **我应该使用哪种Llama-2模型大小？**
最适合您的Llama-2模型大小将取决于您的特定需求。并且实现最高性能并不总是最大的模型。建议评估您的需求，并在选择适当的Llama-2模型大小时考虑计算资源、响应时间和成本效益等因素。决策应基于对应用程序目标和约束的全面评估。
## Trn1/Inf2实例上的推理：释放Llama-2的全部潜力
**Llama-2**可以部署在各种硬件平台上，每个平台都有自己的一系列优势。然而，当涉及到最大化Llama-2的效率、可扩展性和成本效益时，[AWS Trn1/Inf2实例](https://aws.amazon.com/ec2/instance-types/inf2/)作为最佳选择脱颖而出。

**可扩展性和可用性**
部署像Llama-2这样的大型语言模型(`LLM`)的关键挑战之一是合适硬件的可扩展性和可用性。由于需求高，传统的`GPU`实例经常面临稀缺性，这使得有效配置和扩展资源变得具有挑战性。
相比之下，`Trn1/Inf2`实例，如`trn1.32xlarge`、`trn1n.32xlarge`、`inf2.24xlarge`和`inf2.48xlarge`，是专为生成式AI模型（包括LLM）的高性能深度学习(DL)训练和推理而构建的。它们提供了可扩展性和可用性，确保您可以根据需要部署和扩展`Llama-2`模型，而不会出现资源瓶颈或延迟。

**成本优化：**
在传统GPU实例上运行LLM可能成本高昂，特别是考虑到GPU的稀缺性和其竞争性定价。
**Trn1/Inf2**实例提供了一种经济高效的替代方案。通过提供针对AI和机器学习任务优化的专用硬件，Trn1/Inf2实例使您能够以较低的成本实现顶级性能。
这种成本优化使您能够高效分配预算，使LLM部署变得可访问和可持续。

**性能提升**
虽然Llama-2可以在GPU上实现高性能推理，但Neuron加速器将性能提升到了新的水平。Neuron加速器是专为机器学习工作负载而构建的，提供硬件加速，显著增强了Llama-2的推理速度。这转化为在Trn1/Inf2实例上部署Llama-2时更快的响应时间和改进的用户体验。

### 模型规格
该表提供了有关不同大小的Llama-2模型、它们的权重以及部署它们的硬件要求的信息。这些信息可用于设计部署任何大小的Llama-2模型所需的基础设施。例如，如果您想部署`Llama-2-13b-chat`模型，您将需要使用至少具有`26 GB`总加速器内存的实例类型。

| 模型           | 权重 | 字节 | 参数大小（十亿） | 总加速器内存（GB） | NeuronCore的加速器内存大小（GB） | 所需Neuron核心 | 所需Neuron加速器 | 实例类型   | tp_degree |
|-----------------|---------|-------|-----------------------------|------------------------------|---------------------------------------------|-----------------------|-----------------------------|-----------------|-----------|
| Meta/Llama-2-70b | float16 | 2     | 70                          | 140                          | 16                                          | 9                     | 5                           | inf2.48x        | 24        |
| Meta/Llama-2-13b | float16 | 2     | 13                          | 26                           | 16                                          | 2                     | 1                           | inf2.24x        | 12        |
| Meta/Llama-2-7b | float16 | 2     | 7                           | 14                           | 16                                          | 1                     | 1                           | inf2.24x        | 12        |

### 示例用例
一家公司想要部署一个Llama-2聊天机器人来提供客户支持。该公司拥有庞大的客户群，预计在高峰时段会收到大量聊天请求。公司需要设计一个能够处理大量请求并提供快速响应时间的基础设施。

该公司可以使用Inferentia2实例高效地扩展其Llama-2聊天机器人。Inferentia2实例是专门用于机器学习任务的硬件加速器。它们可以为机器学习工作负载提供高达20倍的性能和高达7倍的成本降低，相比于GPU。

该公司还可以使用Ray Serve水平扩展其Llama-2聊天机器人。Ray Serve是一个用于提供机器学习模型服务的分布式框架。它可以根据需求自动扩展或缩减您的模型。

为了扩展其Llama-2聊天机器人，该公司可以部署多个Inferentia2实例，并使用Ray Serve将流量分配到这些实例上。这将使公司能够处理大量请求并提供快速的响应时间。

## 解决方案架构
在本节中，我们将深入探讨我们的解决方案架构，该架构结合了Llama-2模型、[Ray Serve](https://docs.ray.io/en/latest/serve/index.html)和Amazon EKS上的[Inferentia2](https://aws.amazon.com/ec2/instance-types/inf2/)。

![Llama-2-inf2](../../../../../../../docs/gen-ai/inference/img/llama2-inf2.png)
## 部署解决方案
要开始在[Amazon EKS](https://aws.amazon.com/eks/)上部署`Llama-2-13b chat`，我们将涵盖必要的先决条件，并一步步引导您完成部署过程。
这包括设置基础设施、部署**Ray集群**和创建[Gradio](https://www.gradio.app/) WebUI应用程序。

<CollapsibleContent header={<h2><span>先决条件</span></h2>}>
在我们开始之前，请确保您已经准备好所有先决条件，以使部署过程顺利无忧。
确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### 部署

克隆仓库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到其中一个示例目录并运行`install.sh`脚本

**重要提示：** 确保在部署蓝图之前更新`variables.tf`文件中的区域。
此外，确认您的本地区域设置与指定区域匹配，以防止任何差异。
例如，将您的`export AWS_DEFAULT_REGION="<REGION>"`设置为所需区域：

```bash
cd data-on-eks/ai-ml/trainium-inferentia/ && chmod +x install.sh
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

</CollapsibleContent>

## 使用Llama-2-Chat模型部署Ray集群
一旦`Trainium on EKS`集群部署完成，您可以继续使用`kubectl`部署`ray-service-Llama-2.yaml`。

在此步骤中，我们将部署Ray Serve集群，该集群由一个使用Karpenter自动扩展在`x86 CPU`实例上运行的`Head Pod`以及由[Karpenter](https://karpenter.sh/)自动扩展在`Inf2.48xlarge`实例上运行的`Ray workers`组成。

让我们仔细看看此部署中使用的关键文件，并在继续部署之前了解它们的功能：

- **ray_serve_Llama-2.py:**
此脚本使用FastAPI、Ray Serve和基于PyTorch的Hugging Face Transformers创建一个高效的API，用于使用[NousResearch/Llama-2-13b-chat-hf](https://huggingface.co/NousResearch/Llama-2-13b-chat-hf)语言模型进行文本生成。
或者，用户可以灵活地切换到[meta-llama/Llama-2-13b-chat-hf](https://huggingface.co/meta-llama/Llama-2-13b-chat-hf)模型。该脚本建立了一个端点，接受输入句子并高效生成文本输出，受益于Neuron加速以增强性能。凭借其高度可配置性，用户可以微调模型参数以适应各种自然语言处理应用，包括聊天机器人和文本生成任务。

- **ray-service-Llama-2.yaml:**
这个Ray Serve YAML文件作为Kubernetes配置，用于部署Ray Serve服务，促进使用`Llama-2-13b-chat`模型进行高效的文本生成。
它定义了一个名为`Llama-2`的Kubernetes命名空间来隔离资源。在配置中，创建了名为`Llama-2-service`的`RayService`规范，并托管在`Llama-2`命名空间中。`RayService`规范利用Python脚本`ray_serve_Llama-2.py`（复制到同一文件夹中的Dockerfile中）创建Ray Serve服务。
此示例中使用的Docker镜像可在Amazon Elastic Container Registry (ECR)上公开获取，便于部署。
用户还可以修改Dockerfile以满足其特定需求，并将其推送到自己的ECR存储库，在YAML文件中引用它。

### 步骤1：部署Llama-2-Chat模型

**确保集群在本地配置**
```bash
aws eks --region us-west-2 update-kubeconfig --name trainium-inferentia
```

**部署RayServe集群**

```bash
cd data-on-eks/gen-ai/inference/llama2-13b-chat-rayserve-inf2
kubectl apply -f ray-service-llama2.yaml
```

通过运行以下命令验证部署

:::info

部署过程可能需要长达10分钟。头部Pod预计在2到3分钟内准备就绪，而Ray Serve工作节点pod可能需要长达10分钟用于镜像检索和从Huggingface部署模型。

:::

```bash
kubectl get all -n llama2
```

**输出：**

```text
NAME                                            READY   STATUS    RESTARTS   AGE
pod/llama2-raycluster-fcmtr-head-bf58d          1/1     Running   0          67m
pod/llama2-raycluster-fcmtr-worker-inf2-lgnb2   1/1     Running   0          5m30s

NAME                       TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                                         AGE
service/llama2             ClusterIP   172.20.118.243   <none>        10001/TCP,8000/TCP,8080/TCP,6379/TCP,8265/TCP   67m
service/llama2-head-svc    ClusterIP   172.20.168.94    <none>        8080/TCP,6379/TCP,8265/TCP,10001/TCP,8000/TCP   57m
service/llama2-serve-svc   ClusterIP   172.20.61.167    <none>        8000/TCP                                        57m

NAME                                        DESIRED WORKERS   AVAILABLE WORKERS   CPUS   MEMORY        GPUS   STATUS   AGE
raycluster.ray.io/llama2-raycluster-fcmtr   1                 1                   184    704565270Ki   0      ready    67m

NAME                       SERVICE STATUS   NUM SERVE ENDPOINTS
rayservice.ray.io/llama2   Running          2

```
```bash
kubectl get ingress -n llama2
```

**输出：**

```text
NAME     CLASS   HOSTS   ADDRESS                                                                         PORTS   AGE
llama2   nginx   *       k8s-ingressn-ingressn-aca7f16a80-1223456666.elb.us-west-2.amazonaws.com   80      69m
```

:::caution

此蓝图出于安全原因部署了一个内部负载均衡器，因此除非您在同一个vpc中，否则您可能无法从浏览器访问它。
您可以按照[这里](https://github.com/awslabs/data-on-eks/blob/5a2d1dfb39c89f3fd961beb350d6f1df07c2b31c/ai-ml/trainium-inferentia/helm-values/ingress-nginx-values.yaml#L8)的说明修改蓝图，使NLB公开。

或者，您可以使用端口转发来测试服务，而无需使用负载均衡器。

:::

现在，您可以使用下面的负载均衡器URL访问Ray仪表板，将`<NLB_DNS_NAME>`替换为您的NLB端点：

```text
http://\<NLB_DNS_NAME\>/dashboard/#/serve
```

如果您无法访问公共负载均衡器，可以使用端口转发并使用以下命令通过localhost浏览Ray仪表板：

```bash
kubectl port-forward service/llama2 8265:8265 -n llama2
```

**在浏览器中打开链接**：http://localhost:8265/

从此网页，您将能够监控模型部署的进度，如下图所示：

![RayDashboard](../../../../../../../docs/gen-ai/inference/img/rayserve-llama2-13b-dashboard.png)

### 步骤2：测试Llama-2-Chat模型
一旦您看到模型部署的状态处于`running`状态，您就可以开始使用Llama-2-chat。

**使用端口转发**

首先，使用端口转发在本地访问服务：

```bash
kubectl port-forward service/llama2-serve-svc 8000:8000 -n llama2
```

然后，您可以使用以下URL测试模型，在URL末尾添加查询：

```bash
http://localhost:8000/infer?sentence=what is data parallelism and tensor parallelism and the differences
```

您将在浏览器中看到类似这样的输出。

![llama2-13b-response](../../../../../../../docs/gen-ai/inference/img/llama2-13b-response.png)

**使用NLB**：

如果您更喜欢使用网络负载均衡器(NLB)，可以按照[这里](https://github.com/awslabs/data-on-eks/blob/5a2d1dfb39c89f3fd961beb350d6f1df07c2b31c/ai-ml/trainium-inferentia/helm-values/ingress-nginx-values.yaml#L8)的说明修改蓝图，使NLB公开。

然后，您可以使用以下URL，在URL末尾添加查询：

```text
http://\<NLB_DNS_NAME\>/serve/infer?sentence=what is data parallelism and tensor parallelisma and the differences
```

您将在浏览器中看到类似这样的输出：

![聊天输出](../../../../../../../docs/gen-ai/inference/img/llama-2-chat-ouput.png)

### 步骤3：部署Gradio WebUI应用

[Gradio](https://www.gradio.app/) Web UI用于与部署在使用inf2实例的EKS集群上的Llama2推理服务交互。
Gradio UI使用其服务名称和端口在内部与公开在端口`8000`上的Llama2服务(`llama2-serve-svc.llama2.svc.cluster.local:8000`)通信。

我们已经为Gradio应用创建了一个基础Docker(`gen-ai/inference/gradio-ui/Dockerfile-gradio-base`)镜像，可以与任何模型推理一起使用。
此镜像发布在[Public ECR](https://gallery.ecr.aws/data-on-eks/gradio-web-app-base)上。

#### 部署Gradio应用的步骤：

以下YAML脚本(`gen-ai/inference/llama2-13b-chat-rayserve-inf2/gradio-ui.yaml`)创建了一个专用命名空间、部署、服务和一个ConfigMap，您的模型客户端脚本放在其中。

要部署此内容，请执行：

```bash
cd data-on-eks/gen-ai/inference/llama2-13b-chat-rayserve-inf2/
kubectl apply -f gradio-ui.yaml
```
**验证步骤：**
运行以下命令验证部署、服务和ConfigMap：

```bash
kubectl get deployments -n gradio-llama2-inf2

kubectl get services -n gradio-llama2-inf2

kubectl get configmaps -n gradio-llama2-inf2
```

**端口转发服务：**

运行端口转发命令，以便您可以在本地访问Web UI：

```bash
kubectl port-forward service/gradio-service 7860:7860 -n gradio-llama2-inf2
```

#### 调用WebUI

打开您的网络浏览器并通过导航到以下URL访问Gradio WebUI：

在本地URL上运行：http://localhost:7860

您现在应该能够从本地机器与Gradio应用程序交互。

![gradio-llama2-13b-chat](../../../../../../../docs/gen-ai/inference/img/gradio-llama2-13b-chat.png)

## 结论
总之，您将成功在EKS上使用Ray Serve部署**Llama-2-13b chat**模型，并使用Gradio创建一个类似chatGPT的聊天Web UI。
这为自然语言处理和聊天机器人开发开辟了令人兴奋的可能性。

总结来说，在部署和扩展Llama-2方面，AWS Trn1/Inf2实例提供了令人信服的优势。
它们提供了运行大型语言模型所需的可扩展性、成本优化和性能提升，同时克服了与GPU稀缺性相关的挑战。
无论您是构建聊天机器人、自然语言处理应用程序还是任何其他由LLM驱动的解决方案，Trn1/Inf2实例都使您能够在AWS云上充分发挥Llama-2的潜力。

## 清理

最后，我们将提供在不再需要资源时清理和取消配置资源的说明。

**步骤1：** 删除Gradio应用和Llama2推理部署

```bash
cd data-on-eks/gen-ai/inference/llama2-13b-chat-rayserve-inf2
kubectl delete -f gradio-ui.yaml
kubectl delete -f ray-service-llama2.yaml
```

**步骤2：** 清理EKS集群
此脚本将使用`-target`选项清理环境，以确保所有资源按正确顺序删除。

```bash
cd data-on-eks/ai-ml/trainium-inferentia
./cleanup.sh
```
