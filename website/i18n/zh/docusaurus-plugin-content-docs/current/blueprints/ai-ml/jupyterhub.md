---
sidebar_position: 3
sidebar_label: EKS上的JupyterHub
---
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

:::caution

**EKS上的AI**内容**正在迁移**到一个新的仓库。
🔗 👉 [阅读完整的迁移公告 »](https://awslabs.github.io/data-on-eks/docs/migration/migration-announcement)

:::

:::warning
在EKS上部署ML模型需要访问GPU或Neuron实例。如果您的部署不起作用，通常是由于缺少对这些资源的访问权限。此外，一些部署模式依赖于Karpenter自动扩展和静态节点组；如果节点未初始化，请检查Karpenter或节点组的日志以解决问题。
:::

# EKS上的JupyterHub

[JupyterHub](https://jupyter.org/hub)是一个强大的多用户服务器，使用户能够访问和交互Jupyter笔记本和其他Jupyter兼容环境。它提供了一个协作平台，多个用户可以同时访问和使用笔记本，促进用户之间的协作和共享。JupyterHub允许用户创建自己的隔离计算环境（称为"spawners"）并在这些环境中启动Jupyter笔记本或其他交互式计算环境。这为每个用户提供了自己的工作空间，包括文件、代码和计算资源。

## EKS上的JupyterHub
在Amazon Elastic Kubernetes Service (EKS)上部署JupyterHub结合了JupyterHub的多功能性与Kubernetes的可扩展性和灵活性。这个蓝图使用户能够在EKS上借助JupyterHub配置文件构建多租户JupyterHub平台。通过为每个用户利用EFS共享文件系统，它便于轻松共享笔记本并提供个人EFS存储，以便用户pod可以安全地存储数据，即使用户pod被删除或过期。当用户登录时，他们可以在现有EFS卷下访问所有脚本和数据。

通过利用EKS的功能，您可以无缝扩展JupyterHub环境以满足用户需求，确保高效的资源利用和最佳性能。使用EKS，您可以利用Kubernetes的功能，如自动扩展、高可用性以及轻松部署更新和升级。这使您能够为用户提供可靠且强大的JupyterHub体验，使他们能够有效地协作、探索和分析数据。

要开始使用EKS上的JupyterHub，请按照本指南中的说明设置和配置您的JupyterHub环境。

<CollapsibleContent header={<h3><span>部署解决方案</span></h3>}>

这个[蓝图](https://github.com/awslabs/data-on-eks/tree/main/ai-ml/jupyterhub)部署以下组件：

- 创建一个新的示例VPC、2个私有子网和2个公共子网。链接到VPC文档
- 为公共子网设置互联网网关，为私有子网设置NAT网关。
- 创建带有公共端点的EKS集群控制平面（仅用于演示目的）和核心托管节点组。
- 部署[JupyterHub Helm图表](https://hub.jupyter.org/helm-chart/)来设置JupyterHub。
- 设置两个EFS存储挂载：一个用于个人存储，一个用于共享存储。
- 可选：使用[Amazon Cognito](https://aws.amazon.com/cognito/)用户池对用户进行身份验证。链接到Cognito文档

通过遵循此蓝图，您可以轻松部署和配置EKS上的JupyterHub环境，利用各种AWS服务为用户提供协作和可扩展的平台。

<CollapsibleContent header={<h3><span>先决条件</span></h3>}>

**类型1：部署没有域名和负载均衡器的JupyterHub**：

这种方法在JupyterHub上使用端口转发（`kubectl port-forward svc/proxy-public 8080:80 -n jupyterhub`）。它有助于在开发和测试环境中进行测试。对于生产部署，您需要一个自定义域名来托管JupyterHub，并配合适当的身份验证机制，如Cognito。在生产环境中使用方法2进行身份验证。

**类型2：部署带有自定义域名、ACM和NLB的JupyterHub**：

这种方法需要创建域名并获取ACM证书。您需要与您的组织或平台团队协调域名和证书。您可以使用自己的身份验证机制或AWS Cognito。
确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

:::info

以下仅适用于类型2部署，它需要自定义域名和ACM证书

:::

4. **域名**：您需要自己的域名来使用自定义域名托管JupyterHub WebUI。出于测试目的，您可以使用免费域名服务提供商，如[ChangeIP](https://www.changeip.com/accounts/index.php)创建测试域名。但是，请注意，不建议使用ChangeIP或类似服务来托管带有JupyterHub的生产或开发集群。确保您查看使用此类服务的条款和条件。
5. **SSL证书**：您还需要从受信任的证书颁发机构(CA)或通过您的网络托管提供商获取SSL证书，以附加到域名。对于测试环境，您可以使用OpenSSL服务生成自签名证书。

```bash
openssl req -newkey rsa:2048 -nodes -keyout key.pem -x509 -days 365 -out certificate.pem
```

创建证书时使用通配符，以便可以用单个证书保护域名及其所有子域名
该服务生成私钥和自签名证书。
生成证书的示例提示：

![](../../../../../../docs/blueprints/ai-ml/img/Cert_Install.png)


6. 将证书导入AWS Certificate Manager

在文本编辑器中打开私钥(`key.pem`)，并将内容复制到ACM的私钥部分。同样，将`certificate.pem`文件的内容复制到证书正文部分并提交。

   ![](../../../../../../docs/blueprints/ai-ml/img/ACM.png)

   在ACM的控制台中验证证书是否正确安装。

   ![](../../../../../../docs/blueprints/ai-ml/img/Cert_List.png)

</CollapsibleContent>

**JupyterHub身份验证选项**

此蓝图提供了三种身份验证机制的支持：`dummy`、`cognito`和`oauth`。在本文中，我们将使用dummy机制进行简单演示，但这不是生产环境推荐的身份验证机制。我们强烈建议在生产就绪设置中使用cognito方法或在身份验证器页面上找到的其他支持的身份验证机制。

### 部署

**类型1部署配置更改：**

仅更新`variables.tf`文件中的`region`变量。

**类型2部署配置更改：**

使用以下变量更新`variables.tf`文件：
 - `acm_certificate_domain`
 - `jupyterhub_domain`
 - `jupyter_hub_auth_mechanism=cognito`

**类型3部署配置更改：**
- `acm_certificate_domain`
- `jupyterhub_domain`
- `jupyter_hub_auth_mechanism=oauth`
- `oauth_domain`
- `oauth_jupyter_client_id`
- `oauth_jupyter_client_secret`
- `oauth_username_key`

克隆仓库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到其中一个蓝图目录

```bash
cd data-on-eks/ai-ml/jupyterhub && chmod +x install.sh
```

:::info

如果部署未完成，请重新运行install.sh

:::


</CollapsibleContent>


<CollapsibleContent header={<h3><span>验证资源</span></h3>}>

首先，您需要配置kubeconfig以连接到新创建的Amazon EKS集群。使用以下命令，如有必要，将`us-west-2`替换为您的特定AWS区域：

```bash
aws eks --region us-west-2 update-kubeconfig --name jupyterhub-on-eks
```
现在，您可以通过运行以下命令检查各个命名空间中pod的状态。注意关键部署：

```bash
kubectl get pods -A
```
这个验证步骤对于确保所有必要组件正常运行至关重要。如果一切正常，那么您可以放心继续，知道您的Amazon EKS上的JupyterHub环境已准备好赋能您的数据和机器学习团队。

要验证JupyterHub附加组件是否正在运行，请确保控制器和webhook的附加组件部署处于RUNNING状态。

运行以下命令

```bash
kubectl get pods -n jupyterhub
```

验证此蓝图部署的Karpenter Provisioners。我们将讨论JupyterHub配置文件如何使用这些provisioners来启动特定节点。

```bash
kubectl get provisioners
```

验证此蓝图创建的持久卷声明(PVC)，每个都有独特的用途。名为efs-persist的Amazon EFS卷被挂载为每个JupyterHub单用户pod的个人主目录，这确保了每个用户都有专用空间。相比之下，efs-persist-shared是一个特殊的PVC，它在所有JupyterHub单用户pod之间挂载，便于用户之间协作共享笔记本。除此之外，还配置了额外的Amazon EBS卷，以强有力地支持JupyterHub、Kube Prometheus Stack和KubeCost部署。

```bash
kubectl get pvc -A
```

</CollapsibleContent>

### 类型1部署：登录JupyterHub

**使用端口转发暴露JupyterHub**：

执行以下命令，使JupyterHub服务可访问，以便在本地查看Web用户界面。重要的是要注意，我们当前的dummy部署只建立了一个带有`ClusterIP`的Web UI服务。如果您希望将其自定义为内部或面向互联网的负载均衡器，可以在JupyterHub Helm图表值文件中进行必要的调整。

```bash
kubectl port-forward svc/proxy-public 8080:80 -n jupyterhub
```

**登录：** 在网络浏览器中导航到[http://localhost:8080/](http://localhost:8080/)。输入`user-1`作为用户名，并选择任意密码。
![替代文本](../../../../../../docs/blueprints/ai-ml/img/image.png)

选择服务器选项：登录后，您将看到各种笔记本实例配置文件可供选择。`Data Engineering (CPU)`服务器用于传统的基于CPU的笔记本工作。`Elyra`服务器提供[Elyra](https://github.com/elyra-ai/elyra)功能，允许您快速开发管道：![工作流](../../../../../../docs/blueprints/ai-ml/img/elyra-workflow.png)。`Trainium`和`Inferentia`服务器将笔记本服务器部署到Trainium和Inferentia节点上，允许加速工作负载。`Time Slicing`和`MIG`是GPU共享的两种不同策略。最后，`Data Science (GPU)`服务器是运行在NVIDIA GPU上的传统服务器。

对于这个时间切片功能演示，我们将使用**Data Science (GPU + Time-Slicing – G5)**配置文件。继续选择此选项并选择开始按钮。

![替代文本](../../../../../../docs/blueprints/ai-ml/img/notebook-server-list.png)

Karpenter创建的具有`g5.2xlarge`实例类型的新节点已配置为利用[NVIDIA设备插件](https://github.com/NVIDIA/k8s-device-plugin)提供的时间切片功能。此功能通过将单个GPU分成多个可分配单元，实现高效的GPU利用。在这种情况下，我们在NVIDIA设备插件Helm图表配置映射中定义了`4`个可分配的GPU。以下是节点的状态：

GPU：节点通过NVIDIA设备插件的时间切片功能配置了4个GPU。这允许节点更灵活地将GPU资源分配给不同的工作负载。

```yaml
status:
  capacity:
    cpu: '8'                           # 节点有8个可用CPU
    ephemeral-storage: 439107072Ki     # 节点总共有439107072 KiB的临时存储容量
    hugepages-1Gi: '0'                 # 节点有0个1Gi大页
    hugepages-2Mi: '0'                 # 节点有0个2Mi大页
    memory: 32499160Ki                 # 节点总共有32499160 KiB的内存容量
    nvidia.com/gpu: '4'                # 节点总共有4个GPU，通过时间切片配置
    pods: '58'                         # 节点最多可容纳58个pod
  allocatable:
    cpu: 7910m                         # 7910毫核CPU可分配
    ephemeral-storage: '403607335062'  # 403607335062 KiB的临时存储可分配
    hugepages-1Gi: '0'                 # 0个1Gi大页可分配
    hugepages-2Mi: '0'                 # 0个2Mi大页可分配
    memory: 31482328Ki                 # 31482328 KiB的内存可分配
    nvidia.com/gpu: '4'                # 4个GPU可分配
    pods: '58'                         # 58个pod可分配

```

**设置第二个用户(`user-2`)环境**：

为了演示GPU时间切片的实际应用，我们将配置另一个Jupyter笔记本实例。这次，我们将验证第二个用户的pod是否安排在与第一个用户相同的节点上，利用我们之前设置的GPU时间切片配置。按照以下步骤实现这一点：

在隐身浏览器窗口中打开JupyterHub：在网络浏览器的新**隐身窗口**中导航到http://localhost:8080/ 输入`user-2`作为用户名，并选择任意密码。

选择服务器选项：登录后，您将看到服务器选项页面。确保选择**Data Science (GPU + Time-Slicing – G5)**单选按钮并选择开始。

![替代文本](../../../../../../docs/blueprints/ai-ml/img/image-2.png)

验证pod放置：注意，与`user-1`不同，此pod放置只需几秒钟。这是因为Kubernetes调度器能够将pod放置在`user-1` pod创建的现有`g5.2xlarge`节点上。`user-2`也使用相同的docker镜像，所以拉取docker镜像没有延迟，它利用了本地缓存。

打开终端并执行以下命令，检查新的Jupyter笔记本pod被安排在哪里：

```bash
kubectl get pods -n jupyterhub -owide | grep -i user
```

观察`user-1`和`user-2` pod都在同一个节点上运行。这确认了我们的**GPU时间切片**配置按预期运行。

:::info

查看[AWS博客：在Amazon EKS上构建多租户JupyterHub平台
](https://aws.amazon.com/blogs/containers/building-multi-tenant-jupyterhub-platforms-on-amazon-eks/)获取更多详细信息

:::

### 类型2部署（可选）：通过Amazon Cognito登录JupyterHub

在ChangeIP中为JupyterHub域名添加`CNAME` DNS记录，使用负载均衡器DNS名称。

![](../../../../../../docs/blueprints/ai-ml/img/CNAME.png)
:::info
在ChangeIP的CNAME值字段中添加负载均衡器DNS名称时，确保在负载均衡器DNS名称的末尾添加一个点(`.`)。
:::

现在在浏览器中输入域名URL应该重定向到Jupyterhub登录页面。

![](../../../../../../docs/blueprints/ai-ml/img/Cognito-Sign-in.png)


按照Cognito注册和登录流程进行登录。

![](../../../../../../docs/blueprints/ai-ml/img/Cognito-Sign-up.png)

成功登录将为登录用户打开JupyterHub环境。

![](../../../../../../docs/blueprints/ai-ml/img/jupyter_launcher.png)

要测试JupyterHub中共享和个人目录的设置，您可以按照以下步骤操作：
1. 从启动器仪表板打开终端窗口。

![](../../../../../../docs/blueprints/ai-ml/img/jupyter_env.png)

2. 执行命令

```bash
df -h
```
验证创建的EFS挂载。每个用户的私人主目录位于`/home/jovyan`。共享目录位于`/home/shared`

### 类型3部署（可选）：通过OAuth (Keycloak)登录JupyterHub

注意：根据您的OAuth提供商，这看起来会有所不同。

在ChangeIP中为JupyterHub域名添加`CNAME` DNS记录，使用负载均衡器DNS名称。

![](../../../../../../docs/blueprints/ai-ml/img/CNAME.png)

:::info
在ChangeIP的CNAME值字段中添加负载均衡器DNS名称时，确保在负载均衡器DNS名称的末尾添加一个点(`.`)。
:::

现在在浏览器中输入域名URL应该重定向到Jupyterhub登录页面。

![](../../../../../../docs/blueprints/ai-ml/img/oauth.png)

按照Keycloak注册和登录流程进行登录。

![](../../../../../../docs/blueprints/ai-ml/img/keycloak-login.png)

成功登录将为登录用户打开JupyterHub环境。

![](../../../../../../docs/blueprints/ai-ml/img/jupyter_launcher.png)


<CollapsibleContent header={<h3><span>清理</span></h3>}>

:::caution
为避免对您的AWS账户产生不必要的费用，请删除在此部署期间创建的所有AWS资源。
:::

此脚本将使用-target选项清理环境，以确保所有资源按正确顺序删除。

```bash
cd data-on-eks/ai-ml/jupyterhub/ && chmod +x cleanup.sh
./cleanup.sh
```

</CollapsibleContent>
