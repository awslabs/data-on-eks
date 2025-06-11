---
sidebar_position: 2
sidebar_label: JARK on EKS
---
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

# JARK on EKS

:::caution

**AI on EKS**内容**正在迁移**到一个新的仓库。
🔗 👉 [阅读完整的迁移公告 »](https://awslabs.github.io/data-on-eks/docs/migration/migration-announcement)

:::

:::warning
在EKS上部署ML模型需要访问GPU或Neuron实例。如果您的部署不起作用，通常是由于缺少对这些资源的访问权限。此外，一些部署模式依赖于Karpenter自动扩展和静态节点组；如果节点未初始化，请检查Karpenter或节点组的日志以解决问题。
:::

:::info
这些说明仅部署JARK集群作为基础。如果您正在寻找部署特定模型进行推理或训练，请参考此[生成式AI](https://awslabs.github.io/data-on-eks/docs/gen-ai)页面获取端到端说明。
:::

### 什么是JARK？
JARK是一个强大的技术栈，由[JupyterHub](https://jupyter.org/hub)、[Argo Workflows](https://github.com/argoproj/argo-workflows)、[Ray](https://github.com/ray-project/ray)和[Kubernetes](https://kubernetes.io/)组成，旨在简化在Amazon EKS上部署和管理生成式AI模型的过程。这个技术栈汇集了AI和Kubernetes生态系统中一些最有效的工具，为训练、微调和推理大型生成式AI模型提供了强大的解决方案。

### 主要特点和优势
[JupyterHub](https://jupyter.org/hub)：提供运行笔记本的协作环境，对模型开发和提示工程至关重要。

[Argo Workflows](https://github.com/argoproj/argo-workflows)：自动化整个AI模型管道—从数据准备到模型部署—确保一致且高效的流程。

[Ray](https://github.com/ray-project/ray)：跨多个节点扩展AI模型训练和推理，使处理大型数据集和减少训练时间变得更容易。

[Kubernetes](https://kubernetes.io/)：通过提供必要的编排来运行、扩展和管理容器化AI模型，实现高可用性和资源效率，为整个技术栈提供动力。

### 为什么使用JARK？
JARK技术栈非常适合寻求简化部署和管理AI模型复杂过程的团队和组织。无论您是在研究前沿生成式模型还是扩展现有AI工作负载，Amazon EKS上的JARK都提供了您成功所需的灵活性、可扩展性和控制力。


![alt text](../../../../../../docs/blueprints/ai-ml/img/jark.png)


### Ray on Kubernetes

[Ray](https://www.ray.io/)是一个用于构建可扩展和分布式应用程序的开源框架。它旨在通过为分布式计算提供简单直观的API，使编写并行和分布式Python应用程序变得容易。它拥有不断增长的用户和贡献者社区，并由Anyscale, Inc.的Ray团队积极维护和开发。

![RayCluster](../../../../../../docs/blueprints/ai-ml/img/ray-cluster.svg)

*来源：https://docs.ray.io/en/latest/cluster/key-concepts.html*

要在多台机器上生产环境中部署Ray，用户必须首先部署[**Ray集群**](https://docs.ray.io/en/latest/cluster/getting-started.html)。Ray集群由头节点和工作节点组成，可以使用内置的**Ray自动扩缩器**进行自动扩展。

通过[**KubeRay Operator**](https://ray-project.github.io/kuberay/)支持在Kubernetes（包括Amazon EKS）上部署Ray集群。该 operator提供了一种Kubernetes原生方式来管理Ray集群。KubeRay operator的安装涉及部署 operator和`RayCluster`、`RayJob`和`RayService`的CRD，如[此处](https://ray-project.github.io/kuberay/deploy/helm/)所述。

在Kubernetes上部署Ray可以提供几个好处：

1. **可扩展性**：Kubernetes允许您根据工作负载需求扩展或缩减Ray集群，使管理大规模分布式应用程序变得容易。

1. **容错性**：Kubernetes提供内置机制来处理节点故障并确保Ray集群的高可用性。

1. **资源分配**：使用Kubernetes，您可以轻松分配和管理Ray工作负载的资源，确保它们能够访问最佳性能所需的资源。

1. **可移植性**：通过在Kubernetes上部署Ray，您可以在多个云和本地数据中心运行工作负载，使应用程序的迁移变得容易。

1. **监控**：Kubernetes提供丰富的监控功能，包括指标和日志记录，使故障排除和性能优化变得容易。

总体而言，在Kubernetes上部署Ray可以简化分布式应用程序的部署和管理，使其成为许多需要运行大规模机器学习工作负载的组织的热门选择。

在继续部署之前，请确保您已阅读官方[文档](https://docs.ray.io/en/latest/cluster/kubernetes/index.html)的相关部分。

![RayonK8s](../../../../../../docs/blueprints/ai-ml/img/ray_on_kubernetes.webp)

*来源：https://docs.ray.io/en/latest/cluster/kubernetes/index.html*

<CollapsibleContent header={<h2><span>部署解决方案</span></h2>}>

在这个[示例](https://github.com/awslabs/data-on-eks/tree/main/ai-ml/jark-stack/terraform)中，您将在Amazon EKS上配置JARK集群。

![JARK](../../../../../../docs/blueprints/ai-ml/img/jark-stack.png)


### 先决条件

确保您已在机器上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### 部署

克隆仓库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```
:::info
如果您使用配置文件进行身份验证
将您的`export AWS_PROFILE="<PROFILE_name>"`设置为所需的配置文件名
:::

导航到示例目录之一并运行`install.sh`脚本

:::info
确保在部署蓝图之前更新`variables.tf`文件中的区域。
此外，确认您的本地区域设置与指定区域匹配，以防止任何差异。
例如，将您的`export AWS_DEFAULT_REGION="<REGION>"`设置为所需的区域：
:::


```bash
cd data-on-eks/ai-ml/jark-stack/terraform && chmod +x install.sh
./install.sh
```

</CollapsibleContent>

<CollapsibleContent header={<h3><span>验证部署</span></h3>}>

更新本地kubeconfig，以便我们可以访问kubernetes集群

```bash
aws eks update-kubeconfig --name jark-stack #或您用于EKS集群名称的任何名称
```

首先，让我们验证集群中是否有工作节点运行。

```bash
kubectl get nodes
```

```bash
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-1-26-241.ec2.internal   Ready    <none>   10h   v1.24.9-eks-49d8fe8
ip-10-1-4-21.ec2.internal     Ready    <none>   10h   v1.24.9-eks-49d8fe8
ip-10-1-40-196.ec2.internal   Ready    <none>   10h   v1.24.9-eks-49d8fe8
```

接下来，让我们验证所有pod是否正在运行。

```bash
kubectl get pods -n kuberay-operator
```

```bash
NAME                               READY   STATUS    RESTARTS        AGE
kuberay-operator-7b5c85998-vfsjr   1/1     Running   1 (1h37m ago)   1h
```

```bash
kubectl get deployments -A

NAMESPACE              NAME                                                 READY   UP-TO-DATE   AVAILABLE   AGE
ingress-nginx          ingress-nginx-controller                             1/1     1            1           36h
jupyterhub             hub                                                  1/1     1            1           36h
jupyterhub             proxy                                                1/1     1            1           36h
kube-system            aws-load-balancer-controller                         2/2     2            2           36h
kube-system            coredns                                              2/2     2            2           2d5h
kube-system            ebs-csi-controller                                   2/2     2            2           2d5h
kuberay-operator       kuberay-operator                                     1/1     1            1           36h
nvidia-device-plugin   nvidia-device-plugin-node-feature-discovery-master   1/1     1
```

:::info

请参考[生成式AI](https://awslabs.github.io/data-on-eks/docs/gen-ai)页面，了解在EKS上部署生成式AI模型。

:::

</CollapsibleContent>

<CollapsibleContent header={<h3><span>清理</span></h3>}>

:::caution
为避免对您的AWS账户产生不必要的费用，请删除在此部署期间创建的所有AWS资源。
:::

此脚本将使用`-target`选项清理环境，以确保所有资源按正确顺序删除。

```bash
cd data-on-eks/ai-ml/jark-stack/terraform && chmod +x cleanup.sh
```

</CollapsibleContent>
