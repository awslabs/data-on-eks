---
title: Inferentia2上的Mistral-7B
sidebar_position: 2
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

注意：Mistral-7B-Instruct-v0.2是[Huggingface](https://huggingface.co/mistralai/Mistral-7B-Instruct-v0.2)仓库中的一个受限模型。要使用此模型，需要使用HuggingFace令牌。
要在HuggingFace中生成令牌，请使用您的HuggingFace账户登录，并在[设置](https://huggingface.co/settings/tokens)页面上点击`访问令牌`菜单项。

:::

# 使用Inferentia2、Ray Serve、Gradio部署Mistral-7B-Instruct-v0.2
此模式概述了在Amazon EKS上部署[Mistral-7B-Instruct-v0.2](https://huggingface.co/mistralai/Mistral-7B-Instruct-v0.2)模型，利用[AWS Inferentia2](https://aws.amazon.com/ec2/instance-types/inf2/)增强文本生成性能。[Ray Serve](https://docs.ray.io/en/latest/serve/index.html)确保Ray Worker节点的高效扩展，而[Karpenter](https://karpenter.sh/)动态管理AWS Inferentia2节点的配置。此设置在可扩展的云环境中优化高性能和经济高效的文本生成应用程序。

通过此模式，您将完成以下内容：

- 创建一个具有Karpenter管理的AWS Inferentia2节点池的[Amazon EKS](https://aws.amazon.com/eks/)集群，用于节点的动态配置。
- 使用[trainium-inferentia](https://github.com/awslabs/data-on-eks/tree/main/ai-ml/trainium-inferentia) Terraform蓝图安装[KubeRay Operator](https://github.com/ray-project/kuberay)和其他核心EKS附加组件。
- 使用RayServe部署`Mistral-7B-Instruct-v0.2`模型以实现高效扩展。

### 什么是Mistral-7B-Instruct-v0.2模型？

`mistralai/Mistral-7B-Instruct-v0.2`是`Mistral-7B-v0.2基础模型`的指令调整版本，它已经使用公开可用的对话数据集进行了微调。它旨在遵循指令并完成任务，使其适用于聊天机器人、虚拟助手和面向任务的对话系统等应用。它建立在`Mistral-7B-v0.2`基础模型之上，该模型有73亿参数，采用最先进的架构，包括分组查询注意力(GQA)以加快推理速度，以及字节回退BPE分词器以提高鲁棒性。

请参阅[模型卡片](https://replicate.com/mistralai/mistral-7b-instruct-v0.2/readme)了解更多详情。

## 部署解决方案
让我们在Amazon EKS上运行`Mistral-7B-Instruct-v0.2`模型！在本节中，我们将涵盖：

- **先决条件**：确保在开始之前安装所有必要的工具。
- **基础设施设置**：创建您的EKS集群并为部署做准备。
- **部署Ray集群**：您的图像生成管道的核心，提供可扩展性和效率。
- **构建Gradio Web UI**：创建一个用户友好的界面，与Mistral 7B模型无缝交互。
<CollapsibleContent header={<h2><span>先决条件</span></h2>}>
在我们开始之前，请确保您已经准备好所有先决条件，以使部署过程顺利无忧。
确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [envsubst](https://pypi.org/project/envsubst/)

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

# 输出显示EKS托管节点组节点
kubectl get nodes
```

</CollapsibleContent>

## 使用Mistral 7B模型部署Ray集群

一旦`trainium-inferentia` EKS集群部署完成，您可以继续使用`kubectl`从`/data-on-eks/gen-ai/inference/mistral-7b-rayserve-inf2/`路径部署`ray-service-mistral.yaml`。

在此步骤中，我们将部署Ray Serve集群，该集群由一个使用Karpenter自动扩展在`x86 CPU`实例上运行的`Head Pod`以及由[Karpenter](https://karpenter.sh/)自动扩展在`inf2.24xlarge`实例上运行的`Ray workers`组成。

让我们仔细看看此部署中使用的关键文件，并在继续部署之前了解它们的功能：
- **ray_serve_mistral.py:**
  此脚本设置了一个FastAPI应用程序，其中包含两个使用Ray Serve部署的主要组件，Ray Serve使得在AWS Neuron基础设施(Inf2)上进行可扩展模型服务成为可能：
  - **mistral-7b部署**：此类使用调度器初始化Mistral 7B模型，并将其移至Inf2节点进行处理。该脚本利用Transformers Neuron对分组查询注意力(GQA)模型的支持，用于此Mistral模型。`mistral-7b-instruct-v0.2`是一个基于聊天的模型。该脚本还通过在实际提示周围添加`[INST]`和`[/INST]`令牌来添加指令所需的前缀。
  - **APIIngress**：此FastAPI端点作为Mistral 7B模型的接口。它在`/infer`路径上公开了一个GET方法，该方法接受文本提示。它通过回复文本来响应提示。

- **ray-service-mistral.yaml:**
  此RayServe部署模式在Amazon EKS上设置了一个可扩展的服务，用于托管带有AWS Inferentia2支持的Mistral-7B-Instruct-v0.2模型。它创建了一个专用命名空间，并配置了一个具有自动扩展功能的RayService，以根据传入流量高效管理资源利用率。该部署确保在RayService保护伞下提供的模型可以自动调整副本，这取决于需求，每个副本需要2个神经元核心。此模式使用定制的容器镜像，旨在最大化性能，并通过确保预加载重型依赖项来最小化启动延迟。

### 部署Mistral-7B-Instruct-v0.2模型

确保集群在本地配置

```bash
aws eks --region us-west-2 update-kubeconfig --name trainium-inferentia
```

**部署RayServe集群**

:::info

要部署Mistral-7B-Instruct-v0.2模型，必须将您的Hugging Face Hub令牌配置为环境变量。此令牌用于身份验证和访问模型。有关如何创建和管理Hugging Face令牌的指导，请访问[Hugging Face令牌管理](https://huggingface.co/docs/hub/security-tokens)。

:::


```bash
# 将Hugging Face Hub令牌设置为环境变量。应用ray-service-mistral.yaml文件时将替换此变量

export HUGGING_FACE_HUB_TOKEN=$(echo -n "Your-Hugging-Face-Hub-Token-Value" | base64)

cd data-on-eks/gen-ai/inference/mistral-7b-rayserve-inf2
envsubst < ray-service-mistral.yaml| kubectl apply -f -
```
通过运行以下命令验证部署

:::info

部署过程可能需要长达10分钟。头部Pod预计在2到3分钟内准备就绪，而Ray Serve工作节点pod可能需要长达10分钟用于镜像检索和从Huggingface部署模型。

:::

此部署建立了一个在`x86`实例上运行的Ray头部pod和一个在`inf2.24xl`实例上运行的工作节点pod，如下所示。

```bash
kubectl get pods -n mistral

NAME                                                      READY   STATUS
service-raycluster-68tvp-worker-inf2-worker-group-2kckv   1/1     Running
mistral-service-raycluster-68tvp-head-dmfz5               2/2     Running
```

此部署还设置了一个配置了多个端口的mistral服务；端口`8265`指定用于Ray仪表板，端口`8000`用于Mistral模型端点。

```bash
kubectl get svc -n mistral

NAME                        TYPE       CLUSTER-IP       EXTERNAL-IP   PORT(S)
mistral-service             NodePort   172.20.118.238   <none>        10001:30998/TCP,8000:32437/TCP,52365:31487/TCP,8080:30351/TCP,6379:30392/TCP,8265:30904/TCP
mistral-service-head-svc    NodePort   172.20.245.131   <none>        6379:31478/TCP,8265:31393/TCP,10001:32627/TCP,8000:31251/TCP,52365:31492/TCP,8080:31471/TCP
mistral-service-serve-svc   NodePort   172.20.109.223   <none>        8000:31679/TCP
```

对于Ray仪表板，您可以单独端口转发这些端口，以使用localhost在本地访问Web UI。



```bash
kubectl -n mistral port-forward svc/mistral-service 8265:8265
```

通过`http://localhost:8265`访问Web UI。此界面显示了Ray生态系统中作业和角色的部署情况。

![RayServe部署进行中](../../../../../../../docs/gen-ai/inference/img/ray-dashboard-deploying-mistral-inf2.png)

一旦部署完成，控制器和代理状态应为`HEALTHY`，应用程序状态应为`RUNNING`

![RayServe部署完成](../../../../../../../docs/gen-ai/inference/img/ray-dashboard-deployed-mistral-inf2.png)


您可以使用Ray仪表板监控Serve部署和Ray集群部署，包括资源利用率。

![RayServe集群](../../../../../../../docs/gen-ai/inference/img/ray-serve-inf2-mistral-cluster.png)

## 部署Gradio WebUI应用

[Gradio](https://www.gradio.app/) Web UI用于与部署在使用inf2实例的EKS集群上的Mistral7b推理服务交互。
Gradio UI使用其服务名称和端口在内部与公开在端口`8000`上的mistral服务(`mistral-serve-svc.mistral.svc.cluster.local:8000`)通信。

我们已经为Gradio应用创建了一个基础Docker(`gen-ai/inference/gradio-ui/Dockerfile-gradio-base`)镜像，可以与任何模型推理一起使用。
此镜像发布在[Public ECR](https://gallery.ecr.aws/data-on-eks/gradio-web-app-base)上。

#### 部署Gradio应用的步骤：

以下YAML脚本(`gen-ai/inference/mistral-7b-rayserve-inf2/gradio-ui.yaml`)创建了一个专用命名空间、部署、服务和一个ConfigMap，您的模型客户端脚本放在其中。

要部署此内容，请执行：

```bash
cd data-on-eks/gen-ai/inference/mistral-7b-rayserve-inf2/
kubectl apply -f gradio-ui.yaml
```

**验证步骤：**
运行以下命令验证部署、服务和ConfigMap：

```bash
kubectl get deployments -n gradio-mistral7b-inf2

kubectl get services -n gradio-mistral7b-inf2

kubectl get configmaps -n gradio-mistral7b-inf2
```

**端口转发服务：**

运行端口转发命令，以便您可以在本地访问Web UI：

```bash
kubectl port-forward service/gradio-service 7860:7860 -n gradio-mistral7b-inf2
```
#### 调用WebUI

打开您的网络浏览器并通过导航到以下URL访问Gradio WebUI：

在本地URL上运行：http://localhost:7860

您现在应该能够从本地机器与Gradio应用程序交互。

![Gradio WebUI](../../../../../../../docs/gen-ai/inference/img/mistral-gradio.png)

#### 与Mistral模型交互

`Mistral-7B-Instruct-v0.2`模型可用于聊天应用（问答、对话）、文本生成、知识检索等目的。

以下截图提供了基于不同文本提示的模型响应示例。

![Gradio QA](../../../../../../../docs/gen-ai/inference/img/mistral-sample-prompt-1.png)

![Gradio Convo 1](../../../../../../../docs/gen-ai/inference/img/mistral-conv-1.png)

![Gradio Convo 2](../../../../../../../docs/gen-ai/inference/img/mistral-conv-2.png)

## 清理

最后，我们将提供在不再需要资源时清理和取消配置资源的说明。

**步骤1：** 删除Gradio应用和mistral推理部署

```bash
cd data-on-eks/gen-ai/inference/mistral-7b-rayserve-inf2
kubectl delete -f gradio-ui.yaml
kubectl delete -f ray-service-mistral.yaml
```

**步骤2：** 清理EKS集群
此脚本将使用`-target`选项清理环境，以确保所有资源按正确顺序删除。

```bash
cd data-on-eks/ai-ml/trainium-inferentia/
./cleanup.sh
```
