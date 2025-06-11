---
title: Inferentia2上的Llama-3-8B
sidebar_position: 3
description: 在AWS Inferentia加速器上部署Llama-3模型以实现高效推理。
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


# 使用Inferentia、Ray Serve和Gradio部署Llama-3-8B Instruct模型

欢迎阅读这份关于使用[Ray Serve](https://docs.ray.io/en/latest/serve/index.html)在Amazon Elastic Kubernetes Service (EKS)上部署[Meta Llama-3-8B Instruct](https://ai.meta.com/llama/#inside-the-model)模型的综合指南。

在本教程中，您不仅将学习如何利用Llama-3的强大功能，还将深入了解高效部署大型语言模型(LLM)的复杂性，特别是在[trn1/inf2](https://aws.amazon.com/machine-learning/neuron/)（由AWS Trainium和Inferentia提供支持）实例上，如`inf2.24xlarge`和`inf2.48xlarge`，这些实例专为部署和扩展大型语言模型而优化。

### 什么是Llama-3-8B Instruct？

Meta开发并发布了Meta Llama 3系列大型语言模型(LLM)，这是一系列预训练和指令调整的生成文本模型，规模为8B和70B。Llama 3指令调整模型针对对话用例进行了优化，在常见行业基准测试中表现优于许多可用的开源聊天模型。此外，在开发这些模型时，我们非常注重优化有用性和安全性。

有关Llama3规模和模型架构的更多信息可以在[这里](https://huggingface.co/meta-llama/Meta-Llama-3-8B-Instruct)找到。

**可扩展性和可用性**

部署像Llama-3这样的大型语言模型(`LLM`)的关键挑战之一是合适硬件的可扩展性和可用性。由于需求高，传统的`GPU`实例经常面临稀缺性，这使得有效配置和扩展资源变得具有挑战性。

相比之下，`Trn1/Inf2`实例，如`trn1.32xlarge`、`trn1n.32xlarge`、`inf2.24xlarge`和`inf2.48xlarge`，是专为生成式AI模型（包括LLM）的高性能深度学习(DL)训练和推理而构建的。它们提供了可扩展性和可用性，确保您可以根据需要部署和扩展`Llama-3`模型，而不会出现资源瓶颈或延迟。

**成本优化**

在传统GPU实例上运行LLM可能成本高昂，特别是考虑到GPU的稀缺性和其竞争性定价。**Trn1/Inf2**实例提供了一种经济高效的替代方案。通过提供针对AI和机器学习任务优化的专用硬件，Trn1/Inf2实例使您能够以较低的成本实现顶级性能。这种成本优化使您能够高效分配预算，使LLM部署变得可访问和可持续。

**性能提升**

虽然Llama-3可以在GPU上实现高性能推理，但Neuron加速器将性能提升到了新的水平。Neuron加速器是专为机器学习工作负载而构建的，提供硬件加速，显著增强了Llama-3的推理速度。这转化为在Trn1/Inf2实例上部署Llama-3时更快的响应时间和改进的用户体验。
### 示例用例

一家公司想要部署一个Llama-3聊天机器人来提供客户支持。该公司拥有庞大的客户群，预计在高峰时段会收到大量聊天请求。公司需要设计一个能够处理大量请求并提供快速响应时间的基础设施。

该公司可以使用Inferentia2实例高效地扩展其Llama-3聊天机器人。Inferentia2实例是专门用于机器学习任务的硬件加速器。它们可以为机器学习工作负载提供高达20倍的性能和高达7倍的成本降低，相比于GPU。

该公司还可以使用Ray Serve水平扩展其Llama-3聊天机器人。Ray Serve是一个用于提供机器学习模型服务的分布式框架。它可以根据需求自动扩展或缩减您的模型。

为了扩展其Llama-3聊天机器人，该公司可以部署多个Inferentia2实例，并使用Ray Serve将流量分配到这些实例上。这将使公司能够处理大量请求并提供快速的响应时间。

## 解决方案架构

在本节中，我们将深入探讨我们的解决方案架构，该架构结合了Llama-3模型、[Ray Serve](https://docs.ray.io/en/latest/serve/index.html)和Amazon EKS上的[Inferentia2](https://aws.amazon.com/ec2/instance-types/inf2/)。

![Llama-3-inf2](../../../../../../../docs/gen-ai/inference/img/llama3.png)

## 部署解决方案

要开始在[Amazon EKS](https://aws.amazon.com/eks/)上部署`Llama-4-8b-instruct`，我们将涵盖必要的先决条件，并逐步指导您完成部署过程。

这包括设置基础设施、部署**Ray集群**和创建[Gradio](https://www.gradio.app/) WebUI应用程序。

<CollapsibleContent header={<h2><span>先决条件</span></h2>}>
在我们开始之前，请确保您已准备好所有先决条件，以使部署过程顺利无忧。
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

</CollapsibleContent>

## 使用Llama3模型部署Ray集群
一旦`Trainium on EKS`集群部署完成，您可以继续使用`kubectl`部署`ray-service-Llama-3.yaml`。

在此步骤中，我们将部署Ray Serve集群，该集群由一个使用Karpenter自动扩展的`x86 CPU`实例上的`Head Pod`以及由[Karpenter](https://karpenter.sh/)自动扩展的`Inf2.48xlarge`实例上的`Ray workers`组成。

让我们仔细看看此部署中使用的关键文件，并在继续部署之前了解它们的功能：

- **ray_serve_Llama-3.py:**

此脚本使用FastAPI、Ray Serve和基于PyTorch的Hugging Face Transformers创建一个高效的API，用于使用[meta-llama/Meta-Llama-3-8B-Instruct](https://huggingface.co/meta-llama/Meta-Llama-3-8B-Instruct)语言模型进行文本生成。

该脚本建立了一个端点，接受输入句子并高效生成文本输出，受益于Neuron加速以增强性能。凭借其高度可配置性，用户可以微调模型参数以适应各种自然语言处理应用，包括聊天机器人和文本生成任务。

- **ray-service-Llama-3.yaml:**

这个Ray Serve YAML文件作为Kubernetes配置，用于部署Ray Serve服务，促进使用`llama-3-8B-Instruct`模型进行高效的文本生成。

它定义了一个名为`llama3`的Kubernetes命名空间来隔离资源。在配置中，创建了名为`llama-3`的`RayService`规范，并托管在`llama3`命名空间中。`RayService`规范利用Python脚本`ray_serve_llama3.py`（复制到同一文件夹中的Dockerfile中）创建Ray Serve服务。

此示例中使用的Docker镜像可在Amazon Elastic Container Registry (ECR)上公开获取，便于部署。
用户还可以修改Dockerfile以满足其特定需求，并将其推送到自己的ECR存储库，在YAML文件中引用它。
### 部署Llama-3-Instruct模型

**确保集群在本地配置**
```bash
aws eks --region us-west-2 update-kubeconfig --name trainium-inferentia
```

**部署RayServe集群**

:::info

要部署llama3-8B-Instruct模型，必须将您的Hugging Face Hub令牌配置为环境变量。此令牌用于身份验证和访问模型。有关如何创建和管理Hugging Face令牌的指导，请访问[Hugging Face令牌管理](https://huggingface.co/docs/hub/security-tokens)。
:::


```bash
# 将Hugging Face Hub令牌设置为环境变量。应用ray-service-mistral.yaml文件时将替换此变量

export  HUGGING_FACE_HUB_TOKEN=<Your-Hugging-Face-Hub-Token-Value>

cd data-on-eks/gen-ai/inference/llama3-8b-rayserve-inf2
envsubst < ray-service-llama3.yaml| kubectl apply -f -
```

通过运行以下命令验证部署

:::info

部署过程可能需要长达10分钟。Head Pod预计在2到3分钟内准备就绪，而Ray Serve工作节点pod可能需要长达10分钟用于镜像检索和从Huggingface部署模型。

:::

```text
$ kubectl get all -n llama3

NAME                                                          READY   STATUS              RESTARTS   AGE
pod/llama3-raycluster-smqrl-head-4wlbb                        0/1     Running             0          77s
pod/service-raycluster-smqrl-worker-inf2-wjxqq                0/1     Running             0          77s

NAME                     TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)                                                                                       AGE
service/llama3           ClusterIP   172.20.246.48   <none>       8000:32138/TCP,52365:32653/TCP,8080:32604/TCP,6379:32739/TCP,8265:32288/TCP,10001:32419/TCP   78s

$ kubectl get ingress -n llama3

NAME             CLASS   HOSTS   ADDRESS                                                                         PORTS   AGE
llama3           nginx   *       k8s-ingressn-ingressn-randomid-randomid.elb.us-west-2.amazonaws.com             80      2m4s

```

现在，您可以从下面的负载均衡器URL访问Ray仪表板。

    http://\<NLB_DNS_NAME\>/dashboard/#/serve

如果您无法访问公共负载均衡器，可以使用端口转发并使用以下命令通过localhost浏览Ray仪表板：

```bash
kubectl port-forward svc/llama3 8265:8265 -n llama3

# 在浏览器中打开链接
http://localhost:8265/

```

从此网页，您将能够监控模型部署的进度，如下图所示：

![Ray仪表板](../../../../../../../docs/gen-ai/inference/img/ray-dashboard.png)

### 测试Llama3模型
一旦您看到模型部署的状态处于`running`状态，您就可以开始使用Llama-3-instruct。

您可以使用以下URL，在URL末尾添加查询。

    http://\<NLB_DNS_NAME\>/serve/infer?sentence=what is data parallelism and tensor parallelisma and the differences

您将在浏览器中看到类似这样的输出：

![聊天输出](../../../../../../../docs/gen-ai/inference/img/llama-2-chat-ouput.png)

## 部署Gradio WebUI应用
了解如何使用[Gradio](https://www.gradio.app/)创建一个用户友好的聊天界面，该界面与部署的模型无缝集成。

让我们在您的机器上本地部署Gradio应用程序，以与使用RayServe部署的LLama-3-Instruct模型交互。

:::info

Gradio应用程序与仅为演示创建的本地公开服务交互。或者，您可以在EKS上将Gradio应用程序部署为带有Ingress和负载均衡器的Pod，以便更广泛地访问。

:::

### 执行端口转发到llama3 Ray服务
首先，使用kubectl执行端口转发到Llama-3 Ray服务：

```bash
kubectl port-forward svc/llama2-service 8000:8000 -n llama3
```

## 部署Gradio WebUI应用
了解如何使用[Gradio](https://www.gradio.app/)创建一个用户友好的聊天界面，该界面与部署的模型无缝集成。

让我们继续将Gradio应用程序设置为在localhost上运行的Docker容器。此设置将使与使用RayServe部署的Stable Diffusion XL模型交互成为可能。

### 构建Gradio应用程序docker容器

首先，让我们为客户端应用程序构建docker容器。

```bash
cd data-on-eks/gen-ai/inference/gradio-ui
docker build --platform=linux/amd64 \
    -t gradio-app:llama \
    --build-arg GRADIO_APP="gradio-app-llama.py" \
    .
```

### 部署Gradio容器

使用docker在localhost上将Gradio应用程序部署为容器：

```bash
docker run --rm -it -p 7860:7860 -p 8000:8000 gradio-app:llama
```
:::info
如果您的机器上没有运行Docker Desktop，而是使用类似[finch](https://runfinch.com/)的工具，那么您将需要为容器内的自定义主机到IP映射添加额外的标志。

```
docker run --rm -it \
    --add-host ray-service:<workstation-ip> \
    -e "SERVICE_NAME=http://ray-service:8000" \
    -p 7860:7860 gradio-app:llama
```
:::

#### 调用WebUI

打开您的网络浏览器，通过导航到以下URL访问Gradio WebUI：

在本地URL上运行：http://localhost:7860

您现在应该能够从本地机器与Gradio应用程序交互。

![Gradio Llama-3 AI聊天](../../../../../../../docs/gen-ai/inference/img/llama3.png)
## 结论

总之，在部署和扩展Llama-3方面，AWS Trn1/Inf2实例提供了令人信服的优势。
它们提供了运行大型语言模型所需的可扩展性、成本优化和性能提升，同时克服了与GPU稀缺性相关的挑战。无论您是构建聊天机器人、自然语言处理应用程序还是任何其他由LLM驱动的解决方案，Trn1/Inf2实例都使您能够在AWS云上充分发挥Llama-3的潜力。

## 清理

最后，我们将提供在不再需要资源时清理和取消配置资源的说明。

**步骤1：** 删除Gradio容器

在运行`docker run`的localhost终端窗口上按`Ctrl-c`以终止运行Gradio应用程序的容器。可选择清理docker镜像

```bash
docker rmi gradio-app:llama
```
**步骤2：** 删除Ray集群

```bash
cd data-on-eks/gen-ai/inference/llama3-8b-instruct-rayserve-inf2
kubectl delete -f ray-service-llama3.yaml
```

**步骤3：** 清理EKS集群
此脚本将使用`-target`选项清理环境，以确保所有资源按正确顺序删除。

```bash
cd data-on-eks/ai-ml/trainium-inferentia/
./cleanup.sh
```
