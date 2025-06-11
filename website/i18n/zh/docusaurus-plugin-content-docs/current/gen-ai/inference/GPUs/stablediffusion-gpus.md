---
title: Stable Diffusion on GPU
sidebar_position: 3
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

我们正在积极增强此蓝图，以纳入可观测性和日志记录方面的改进。

:::


# 使用GPU、Ray Serve和Gradio部署Stable Diffusion v2
此模式演示了如何在Amazon EKS上部署[Stable Diffusion V2](https://huggingface.co/stabilityai/stable-diffusion-2-1)模型，使用[GPU](https://aws.amazon.com/ec2/instance-types/g4/)进行加速图像生成。[Ray Serve](https://docs.ray.io/en/latest/serve/index.html)提供了跨多个GPU节点的高效扩展，而[Karpenter](https://karpenter.sh/)动态管理节点配置。

通过此模式，您将完成以下内容：

- 创建一个Amazon EKS集群，带有Karpenter管理的GPU节点池，用于节点的动态扩展。
- 使用[jark-stack](https://github.com/awslabs/data-on-eks/tree/main/ai-ml/jark-stack/terraform) Terraform蓝图安装KubeRay operator和其他核心EKS附加组件。
- 使用RayServe部署Stable Diffusion模型，以高效地跨GPU资源进行扩展

### 什么是Stable Diffusion？
Stable Diffusion是一种前沿的文本到图像模型，可以根据文本描述生成令人惊叹、详细的图像。它是艺术家、设计师和任何想要通过图像生成释放想象力的人的强大工具。这个模型的突出之处在于它在图像生成过程中提供了高度的创意控制和灵活性。

## 部署解决方案
让我们在Amazon EKS上运行Stable Diffusion v2-1！在本节中，我们将涵盖：

- **先决条件**：确保您已准备好一切。
- **基础设施设置**：创建您的EKS集群并为部署做准备。
- **部署Ray集群**：您的图像生成管道的核心，提供可扩展性和效率。
- **构建Gradio Web UI**：一个用户友好的界面，用于与Stable Diffusion交互。
<CollapsibleContent header={<h2><span>先决条件</span></h2>}>
在我们开始之前，请确保您已经准备好所有先决条件，以使部署过程顺利无忧。
确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### （可选）通过在Bottlerocket OS中预加载容器镜像减少冷启动时间

要加速Ray工作节点上的镜像检索部署，请参阅[使用Karpenter和EBS快照将容器镜像预加载到Bottlerocket数据卷中](../../../../../../../docs/bestpractices/intro.md)

定义`TF_VAR_bottlerocket_data_disk_snpashot_id`以使Karpenter能够配置带有EBS快照的Bottlerocket工作节点，以减少容器启动的冷启动时间。这可能会节省10分钟（取决于镜像大小）用于从Amazon ECR下载和提取容器镜像。

```
export TF_VAR_bottlerocket_data_disk_snpashot_id=snap-0c6d965cf431785ed
```
### 部署

克隆仓库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```


```
cd data-on-eks/ai-ml/jark-stack/ && chmod +x install.sh
./install.sh
```

导航到其中一个示例目录并运行`install.sh`脚本

**重要提示：** 确保在部署蓝图之前更新`variables.tf`文件中的区域。
此外，确认您的本地区域设置与指定区域匹配，以防止任何差异。
例如，将您的`export AWS_DEFAULT_REGION="<REGION>"`设置为所需区域：

```bash
cd data-on-eks/ai-ml/jark-stack/ && chmod +x install.sh
./install.sh
```

### 验证资源

验证Amazon EKS集群

```bash
aws eks --region us-west-2 describe-cluster --name jark-stack
```

```bash
# 创建k8s配置文件以与EKS进行身份验证
aws eks --region us-west-2 update-kubeconfig --name jark-stack

# 输出显示EKS托管节点组节点
kubectl get nodes
```

</CollapsibleContent>

## 使用Stable Diffusion模型部署Ray集群

一旦`jark-stack`集群部署完成，您可以继续使用`kubectl`从`/data-on-eks/gen-ai/inference/stable-diffusion-rayserve-gpu/`路径部署`ray-service-stablediffusion.yaml`。

在此步骤中，我们将部署Ray Serve集群，该集群由一个使用Karpenter自动扩展在`x86 CPU`实例上运行的`Head Pod`以及由[Karpenter](https://karpenter.sh/)自动扩展在`g5.2xlarge`实例上运行的`Ray workers`组成。

让我们仔细看看此部署中使用的关键文件，并在继续部署之前了解它们的功能：
- **ray_serve_sd.py:**
  此脚本设置了一个FastAPI应用程序，其中包含两个使用Ray Serve部署的主要组件，Ray Serve使得在配备GPU的基础设施上进行可扩展模型服务成为可能：
  - **StableDiffusionV2部署**：此类使用调度器初始化Stable Diffusion V2模型，并将其移至GPU进行处理。它包括基于文本提示生成图像的功能，图像大小可通过输入参数自定义。
  - **APIIngress**：此FastAPI端点作为Stable Diffusion模型的接口。它在`/imagine`路径上公开了一个GET方法，该方法接受文本提示和可选的图像大小。它使用Stable Diffusion模型生成图像，并将其作为PNG文件返回。

- **ray-service-stablediffusion.yaml:**
  此RayServe部署模式在Amazon EKS上设置了一个可扩展的服务，用于托管带有GPU支持的Stable Diffusion模型。它创建了一个专用命名空间，并配置了一个具有自动扩展功能的RayService，以根据传入流量高效管理资源利用率。该部署确保在RayService保护伞下提供的模型可以根据需求自动在1到4个副本之间调整，每个副本需要一个GPU。此模式使用定制的容器镜像，旨在最大化性能，并通过确保预加载重型依赖项来最小化启动延迟。

### 部署Stable Diffusion V2模型

确保集群在本地配置

```bash
aws eks --region us-west-2 update-kubeconfig --name jark-stack
```

**部署RayServe集群**

```bash
cd data-on-eks/gen-ai/inference/stable-diffusion-rayserve-gpu
kubectl apply -f ray-service-stablediffusion.yaml
```

通过运行以下命令验证部署

:::info

如果您没有将容器镜像预加载到数据卷中，部署过程可能需要长达10到12分钟。头部Pod预计在2到3分钟内准备就绪，而Ray Serve工作节点pod可能需要长达10分钟用于镜像检索和从Huggingface部署模型。

:::

此部署建立了一个在x86实例上运行的Ray头部pod和一个在GPU G5实例上运行的工作节点pod，如下所示。

```bash
kubectl get pods -n stablediffusion

NAME                                                      READY   STATUS
rservice-raycluster-hb4l4-worker-gpu-worker-group-z8gdw   1/1     Running
stablediffusion-service-raycluster-hb4l4-head-4kfzz       2/2     Running
```

如果您已将容器镜像预加载到数据卷中，您可以在`kubectl describe pod -n stablediffusion`的输出中找到显示`Container image "public.ecr.aws/data-on-eks/ray2.11.0-py310-gpu-stablediffusion:latest" already present on machine`的消息。
```
kubectl describe pod -n stablediffusion

...
Events:
  Type     Reason            Age                From               Message
  ----     ------            ----               ----               -------
  Warning  FailedScheduling  41m                default-scheduler  0/8 nodes are available: 1 Insufficient cpu, 3 Insufficient memory, 8 Insufficient nvidia.com/gpu. preemption: 0/8 nodes are available: 8 No preemption victims found for incoming pod.
  Normal   Nominated         41m                karpenter          Pod should schedule on: nodeclaim/gpu-ljvhl
  Normal   Scheduled         40m                default-scheduler  Successfully assigned stablediffusion/stablediffusion-raycluster-ms6pl-worker-gpu-85d22 to ip-100-64-136-72.us-west-2.compute.internal
  Normal   Pulled            40m                kubelet            Container image "public.ecr.aws/data-on-eks/ray2.11.0-py310-gpu-stablediffusion:latest" already present on machine
  Normal   Created           40m                kubelet            Created container wait-gcs-ready
  Normal   Started           40m                kubelet            Started container wait-gcs-ready
  Normal   Pulled            39m                kubelet            Container image "public.ecr.aws/data-on-eks/ray2.11.0-py310-gpu-stablediffusion:latest" already present on machine
  Normal   Created           39m                kubelet            Created container worker
  Normal   Started           38m                kubelet            Started container worker
  ```

此部署还设置了一个配置了多个端口的stablediffusion服务；端口`8265`指定用于Ray仪表板，端口`8000`用于Stable Diffusion模型端点。

```bash
kubectl get svc -n stablediffusion
NAME                                TYPE       CLUSTER-IP       EXTERNAL-IP   PORT(S)
stablediffusion-service             NodePort   172.20.223.142   <none>        8080:30213/TCP,6379:30386/TCP,8265:30857/TCP,10001:30666/TCP,8000:31194/TCP
stablediffusion-service-head-svc    NodePort   172.20.215.100   <none>        8265:30170/TCP,10001:31246/TCP,8000:30376/TCP,8080:32646/TCP,6379:31846/TCP
stablediffusion-service-serve-svc   NodePort   172.20.153.125   <none>        8000:31459/TCP
```

对于Ray仪表板，您可以单独端口转发这些端口，以使用localhost在本地访问Web UI。

```bash
kubectl port-forward svc/stablediffusion-service 8266:8265 -n stablediffusion
```

通过`http://localhost:8265`访问Web UI。此界面显示了Ray生态系统中作业和角色的部署情况。

![RayServe部署](../../../../../../../docs/gen-ai/inference/img/ray-serve-gpu-sd.png)

提供的截图将显示Serve部署和Ray集群部署，提供设置和操作状态的可视化概览。

![RayServe集群](../../../../../../../docs/gen-ai/inference/img/ray-serve-gpu-sd-cluster.png)

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

打开您的网络浏览器，通过导航到以下URL访问Gradio WebUI：

在本地URL上运行：http://localhost:7860

您现在应该能够从本地机器与Gradio应用程序交互。

![Gradio输出](../../../../../../../docs/gen-ai/inference/img/gradio-app-gpu.png)
### Ray自动扩展
`ray-serve-stablediffusion.yaml`文件中详述的Ray自动扩展配置利用了Ray在Kubernetes上的功能，根据计算需求动态扩展应用程序。

1. **传入流量**：对您的stable-diffusion部署的传入请求触发Ray Serve监控现有副本上的负载。
2. **基于指标的扩展**：Ray Serve跟踪每个副本的正在进行的请求的平均数量。此配置将`target_num_ongoing_requests_per_replica`设置为1。如果此指标超过阈值，则表示需要更多副本。
3. **副本创建（节点内）**：如果节点有足够的GPU容量，Ray Serve将尝试在现有节点内添加新副本。您的部署每个副本请求1个GPU（`ray_actor_options: num_gpus: 1`）。
4. **节点扩展（Karpenter）**：如果节点无法容纳额外的副本（例如，每个节点只有一个GPU），Ray将向Kubernetes发出信号，表明它需要更多资源。Karpenter观察来自Kubernetes的待处理pod请求，并配置新的g5 GPU节点以满足资源需求。
5. **副本创建（跨节点）**：一旦新节点准备就绪，Ray Serve在新配置的节点上调度额外的副本。

**模拟自动扩展：**
1. **生成负载**：创建脚本或使用负载测试工具向您的stable diffusion服务发送大量图像生成请求。
2. **观察（Ray仪表板）**：通过端口转发或公共NLB（如果已配置）访问Ray仪表板，网址为http://your-cluster/dashboard。观察这些指标如何变化：
        您的部署的副本数量。
        Ray集群中的节点数量。
3. **观察（Kubernetes）**：使用`kubectl get pods -n stablediffusion`查看新pod的创建。使用`kubectl get nodes`观察由Karpenter配置的新节点。

## 清理
最后，我们将提供在不再需要资源时清理和取消配置资源的说明。

**步骤1：** 删除Gradio容器

在运行`docker run`的localhost终端窗口上按`Ctrl-c`以终止运行Gradio应用程序的容器。可选择清理docker镜像

```bash
docker rmi gradio-app:sd
```
**步骤2：** 删除Ray集群

```bash
cd data-on-eks/gen-ai/inference/stable-diffusion-rayserve-gpu
kubectl delete -f ray-service-stablediffusion.yaml
```

**步骤3：** 清理EKS集群
此脚本将使用`-target`选项清理环境，以确保所有资源按正确顺序删除。

```bash
cd data-on-eks/ai-ml/jark-stack/
./cleanup.sh
```
