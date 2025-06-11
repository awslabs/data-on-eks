---
title: Inferentia2上的Stable Diffusion
sidebar_position: 5
---
import CollapsibleContent from '../../../../../../../src/components/CollapsibleContent';

:::caution

**AI on EKS**内容**正在迁移**到一个新的仓库。
🔗 👉 [阅读完整的迁移公告 »](https://awslabs.github.io/data-on-eks/docs/migration/migration-announcement)

:::

:::warning
在EKS上部署ML模型需要访问GPU或Neuron实例。如果您的部署不起作用，通常是因为缺少对这些资源的访问。此外，一些部署模式依赖于Karpenter自动扩展和静态节点组；如果节点未初始化，请检查Karpenter或节点组的日志以解决问题。
:::

:::info

此示例蓝图在EKS集群中作为工作节点运行的Inferentia2实例上部署`stable-diffusion-xl-base-1-0`模型。该模型使用`RayServe`提供服务。

:::

# 使用Inferentia、Ray Serve和Gradio部署Stable Diffusion XL Base模型
欢迎阅读这份关于使用[Ray Serve](https://docs.ray.io/en/latest/serve/index.html)在Amazon Elastic Kubernetes Service (EKS)上部署[Stable Diffusion XL Base](https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0)模型的综合指南。
在本教程中，您不仅将学习如何利用Stable Diffusion模型的强大功能，还将深入了解高效部署大型语言模型(LLM)的复杂性，特别是在[trn1/inf2](https://aws.amazon.com/machine-learning/neuron/)（由AWS Trainium和Inferentia提供支持）实例上，如`inf2.24xlarge`和`inf2.48xlarge`，
这些实例专为部署和扩展大型语言模型而优化。

### 什么是Stable Diffusion？
Stable Diffusion是一个文本到图像模型，可以在几秒钟内创建令人惊叹的艺术作品。它是当今可用的最大和最强大的LLM之一。它主要用于根据文本描述生成详细图像，尽管它也可以应用于其他任务，如修复、扩展和在文本提示指导下生成图像到图像的转换。

#### Stable Diffusion XL(SDXL)
SDXL是一个用于文本到图像合成的潜在扩散模型。与之前版本的Stable Diffusion相比，SDXL使用管道进行潜在扩散和噪声减少。SDXL还通过使用更大的UNet改善了生成图像的质量，相比之前的Stable Diffusion模型。模型参数的增加主要是由于更多的注意力块和更大的交叉注意力上下文，因为SDXL使用了第二个文本编码器。

SDXL设计有多种新颖的条件方案，并在多种纵横比上进行了训练。它还使用了一个精炼模型，该模型使用事后图像到图像技术来提高由SDXL生成的样本的视觉保真度。

这个过程产生了一个高度能力和精细调整的语言模型，我们将指导您在**Amazon EKS**上使用**Ray Serve**有效地部署和利用它。

## Trn1/Inf2实例上的推理：释放Stable Diffusion LLM的全部潜力
**Stable Diffusion XL**可以部署在各种硬件平台上，每个平台都有自己的一系列优势。然而，当涉及到最大化Stable Diffusion模型的效率、可扩展性和成本效益时，[AWS Trn1/Inf2实例](https://aws.amazon.com/ec2/instance-types/inf2/)作为最佳选择脱颖而出。

**可扩展性和可用性**
部署像StableDiffusion XL这样的大型语言模型(`LLM`)的关键挑战之一是合适硬件的可扩展性和可用性。由于需求高，传统的`GPU`实例经常面临稀缺性，这使得有效配置和扩展资源变得具有挑战性。
相比之下，`Trn1/Inf2`实例，如`trn1.32xlarge`、`trn1n.32xlarge`、`inf2.24xlarge`和`inf2.48xlarge`，是专为生成式AI模型（包括LLM）的高性能深度学习(DL)训练和推理而构建的。它们提供了可扩展性和可用性，确保您可以根据需要部署和扩展`Stable-diffusion-xl`模型，而不会出现资源瓶颈或延迟。
**成本优化：**
在传统GPU实例上运行LLM可能成本高昂，特别是考虑到GPU的稀缺性和其竞争性定价。
**Trn1/Inf2**实例提供了一种经济高效的替代方案。通过提供针对AI和机器学习任务优化的专用硬件，Trn1/Inf2实例使您能够以较低的成本实现顶级性能。
这种成本优化使您能够高效分配预算，使LLM部署变得可访问和可持续。

**性能提升**
虽然Stable-Diffusion-xl可以在GPU上实现高性能推理，但Neuron加速器将性能提升到了新的水平。Neuron加速器是专为机器学习工作负载而构建的，提供硬件加速，显著增强了Stable-diffusion的推理速度。这转化为在Trn1/Inf2实例上部署Stable-Diffusion-xl时更快的响应时间和改进的用户体验。

### 示例用例
一家数字艺术公司想要部署由Stable-diffusion-xl驱动的图像生成器，以帮助根据提示生成可能的艺术作品。使用一系列文本提示，用户可以创建各种风格的艺术品、图形和标志。图像生成器可用于预测或微调艺术作品，并可在产品迭代周期中节省大量时间。公司拥有庞大的客户群，希望模型在高负载下可扩展。公司需要设计一个能够处理大量请求并提供快速响应时间的基础设施。

该公司可以使用Inferentia2实例高效地扩展其Stable diffusion图像生成器。Inferentia2实例是专门用于机器学习任务的硬件加速器。它们可以为机器学习工作负载提供高达20倍的性能和高达7倍的成本降低，相比于GPU。

该公司还可以使用Ray Serve水平扩展其Stable diffusion图像生成器。Ray Serve是一个用于提供机器学习模型服务的分布式框架。它可以根据需求自动扩展或缩减您的模型。

为了扩展其Stable diffusion图像生成器，该公司可以部署多个Inferentia2实例，并使用Ray Serve将流量分配到这些实例上。这将使公司能够处理大量请求并提供快速的响应时间。

## 解决方案架构
在本节中，我们将深入探讨我们的解决方案架构，该架构结合了Stable diffusion xl模型、[Ray Serve](https://docs.ray.io/en/latest/serve/index.html)和Amazon EKS上的[Inferentia2](https://aws.amazon.com/ec2/instance-types/inf2/)。

![Sdxl-inf2](../../../../../../../docs/gen-ai/inference/img/excali-draw-sdxl-inf2.png)

## 部署解决方案
要开始在[Amazon EKS](https://aws.amazon.com/eks/)上部署`stable-diffusion-xl-base-1-0`，我们将涵盖必要的先决条件，并一步步引导您完成部署过程。
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

## 使用Stable Diffusion XL模型部署Ray集群

一旦`Trainium on EKS`集群部署完成，您可以继续使用`kubectl`部署`ray-service-stablediffusion.yaml`。

在此步骤中，我们将部署Ray Serve集群，该集群由一个使用Karpenter自动扩展在`x86 CPU`实例上运行的`Head Pod`以及由[Karpenter](https://karpenter.sh/)自动扩展在`Inf2.48xlarge`实例上运行的`Ray workers`组成。

让我们仔细看看此部署中使用的关键文件，并在继续部署之前了解它们的功能：

- **ray_serve_stablediffusion.py:**
此脚本使用FastAPI、Ray Serve和[Hugging Face Optimum Neuron](https://github.com/huggingface/optimum-neuron)工具库创建一个高效的文本到图像生成器，使用[Neuronx模型stable-diffusion-xl-base-1.0](https://huggingface.co/aws-neuron/stable-diffusion-xl-base-1-0-1024x1024)语言模型。

对于此示例蓝图，我们使用的是预编译模型，该模型已编译为在AWS Neuron上运行。您可以使用任何您选择的stable diffusion模型，并在对其进行推理之前将其编译为在AWS Neuron上运行。

- **ray-service-stablediffusion.yaml:**
这个Ray Serve YAML文件作为Kubernetes配置，用于部署Ray Serve服务，促进使用`stable-diffusion-xl-base-1.0`模型进行高效的文本生成。
它定义了一个名为`stablediffusion`的Kubernetes命名空间来隔离资源。在配置中，创建了名为`stablediffusion-service`的`RayService`规范，并托管在`stablediffusion`命名空间中。`RayService`规范利用Python脚本`ray_serve_stablediffusion.py`（复制到同一文件夹中的Dockerfile中）创建Ray Serve服务。
此示例中使用的Docker镜像可在Amazon Elastic Container Registry (ECR)上公开获取，便于部署。
用户还可以修改Dockerfile以满足其特定需求，并将其推送到自己的ECR存储库，在YAML文件中引用它。

### 部署Stable-Diffusion-xl-base-1-0模型

**确保集群在本地配置**
```bash
aws eks --region us-west-2 update-kubeconfig --name trainium-inferentia
```

**部署RayServe集群**

```bash
cd data-on-eks/gen-ai/inference/stable-diffusion-xl-base-rayserve-inf2
kubectl apply -f ray-service-stablediffusion.yaml
```

通过运行以下命令验证部署

:::info

部署过程可能需要长达10分钟。头部Pod预计在2到3分钟内准备就绪，而Ray Serve工作节点pod可能需要长达10分钟用于镜像检索和从Huggingface部署模型。

:::

```text
$ kubectl get po -n stablediffusion -w

NAME                                                      READY   STATUS     RESTARTS   AGE
service-raycluster-gc7gb-worker-inf2-worker-group-k2kf2   0/1     Init:0/1   0          7s
stablediffusion-service-raycluster-gc7gb-head-6fqvv       1/1     Running    0          7s

service-raycluster-gc7gb-worker-inf2-worker-group-k2kf2   0/1     PodInitializing   0          9s
service-raycluster-gc7gb-worker-inf2-worker-group-k2kf2   1/1     Running           0          10s
stablediffusion-service-raycluster-gc7gb-head-6fqvv       1/1     Running           0          53s
service-raycluster-gc7gb-worker-inf2-worker-group-k2kf2   1/1     Running           0          53s
```
还检查创建的服务和入口资源

```text
kubectl get svc -n stablediffusion

NAME                                TYPE       CLUSTER-IP       EXTERNAL-IP   PORT(S)                                                                                       AGE
stablediffusion-service             NodePort   172.20.175.61    <none>        6379:32190/TCP,8265:32375/TCP,10001:32117/TCP,8000:30770/TCP,52365:30334/TCP,8080:30094/TCP   16h
stablediffusion-service-head-svc    NodePort   172.20.193.225   <none>        6379:32228/TCP,8265:30215/TCP,10001:30767/TCP,8000:31482/TCP,52365:30170/TCP,8080:31584/TCP   16h
stablediffusion-service-serve-svc   NodePort   172.20.15.224    <none>        8000:30982/TCP                                                                                16h


$ kubectl get ingress -n stablediffusion

NAME                      CLASS   HOSTS   ADDRESS                                                                         PORTS   AGE
stablediffusion-ingress   nginx   *       k8s-ingressn-ingressn-7f3f4b475b-1b8966c0b8f4d3da.elb.us-west-2.amazonaws.com   80      16h
```

现在，您可以从下面的负载均衡器URL访问Ray仪表板。

    http://\<NLB_DNS_NAME\>/dashboard/#/serve

如果您无法访问公共负载均衡器，可以使用端口转发并使用以下命令通过localhost浏览Ray仪表板：

```bash
kubectl port-forward svc/stablediffusion-service 8265:8265 -n stablediffusion

# 在浏览器中打开链接
http://localhost:8265/

```

从此网页，您将能够监控模型部署的进度，如下图所示：

![Ray仪表板](../../../../../../../docs/gen-ai/inference/img/ray-dashboard-sdxl.png)

### 测试Stable Diffusion XL模型

一旦您验证了Stable Diffusion模型部署状态已在Ray仪表板中切换为`running`状态，您就可以开始利用该模型了。这种状态变化表明Stable Diffusion模型现在已完全功能，并准备好处理基于文本描述的图像生成请求。

您可以使用以下URL，在URL末尾添加查询。

    http://\<NLB_DNS_NAME\>/serve/imagine?prompt=an astronaut is dancing on green grass, sunlit

您将在浏览器中看到类似这样的输出：

![提示输出](../../../../../../../docs/gen-ai/inference/img/stable-diffusion-xl-prompt_3.png)

## 部署Gradio WebUI应用
了解如何使用[Gradio](https://www.gradio.app/)创建一个用户友好的聊天界面，该界面与部署的模型无缝集成。

让我们继续将Gradio应用程序设置为在localhost上运行的Docker容器。此设置将使与使用RayServe部署的Stable Diffusion XL模型交互成为可能。

### 构建Gradio应用程序docker容器

首先，让我们为客户端应用程序构建docker容器。

```bash
cd data-on-eks/gen-ai/inference/gradio-ui
docker build --platform=linux/amd64 \
    -t gradio-app:sd \
    --build-arg GRADIO_APP="gradio-app-stable-diffusion.py" \
    .
```

### 部署Gradio容器

使用docker在localhost上部署Gradio应用程序作为容器：

```bash
docker run --rm -it -p 7860:7860 -p 8000:8000 gradio-app:sd
```
:::info
如果您的机器上没有运行Docker Desktop，而是使用类似[finch](https://runfinch.com/)的工具，那么您将需要额外的标志，用于容器内的自定义主机到IP映射。

```
docker run --rm -it \
    --add-host ray-service:<workstation-ip> \
    -e "SERVICE_NAME=http://ray-service:8000" \
    -p 7860:7860 gradio-app:sd
```
:::


#### 调用WebUI

打开您的网络浏览器并通过导航到以下URL访问Gradio WebUI：

在本地URL上运行：http://localhost:7860

您现在应该能够从本地机器与Gradio应用程序交互。

![Gradio输出](../../../../../../../docs/gen-ai/inference/img/stable-diffusion-xl-gradio.png)

## 结论

总之，您将成功在EKS上使用Ray Serve部署**Stable-diffusion-xl-base**模型，并使用Gradio创建一个基于提示的Web UI。
这为自然语言处理和基于提示的图像生成器和图像预测器开发开辟了令人兴奋的可能性。

总结来说，在部署和扩展Stable diffusion模型方面，AWS Trn1/Inf2实例提供了令人信服的优势。
它们提供了运行大型语言模型所需的可扩展性、成本优化和性能提升，同时克服了与GPU稀缺性相关的挑战。
无论您是构建文本到图像生成器、图像到图像生成器还是任何其他由LLM驱动的解决方案，Trn1/Inf2实例都使您能够在AWS云上充分发挥Stable Diffusion LLM的潜力。

## 清理
最后，我们将提供在不再需要资源时清理和取消配置资源的说明。

**步骤1：** 删除Gradio容器

在运行`docker run`的localhost终端窗口上按`Ctrl-c`以终止运行Gradio应用程序的容器。可选择清理docker镜像

```bash
docker rmi gradio-app:sd
```
**步骤2：** 删除Ray集群

```bash
cd data-on-eks/gen-ai/inference/stable-diffusion-xl-base-rayserve-inf2
kubectl delete -f ray-service-stablediffusion.yaml
```

**步骤3：** 清理EKS集群
此脚本将使用`-target`选项清理环境，以确保所有资源按正确顺序删除。

```bash
cd data-on-eks/ai-ml/trainium-inferentia/
./cleanup.sh
```
