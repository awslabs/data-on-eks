---
sidebar_position: 5
sidebar_label: Ray on EKS
---
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

# Ray on EKS

:::caution

**AI on EKS**内容**正在迁移**到一个新的仓库。
🔗 👉 [阅读完整的迁移公告 »](https://awslabs.github.io/data-on-eks/docs/migration/migration-announcement)

:::

:::danger
**弃用通知**

此蓝图将于**2024年10月27日**从此GitHub仓库中弃用并最终移除，转而使用[**JARK堆栈**](https://awslabs.github.io/data-on-eks/docs/blueprints/ai-ml/jark)。请改用JARK堆栈蓝图。
:::


## 介绍

[Ray](https://www.ray.io/)是一个用于构建可扩展和分布式应用程序的开源框架。它旨在通过提供简单直观的分布式计算API，使编写并行和分布式Python应用程序变得容易。它拥有不断增长的用户和贡献者社区，并由Anyscale, Inc.的Ray团队积极维护和开发。

要在多台机器上部署生产环境的Ray，用户必须首先部署[**Ray集群**](https://docs.ray.io/en/latest/cluster/getting-started.html)。Ray集群由头节点和工作节点组成，可以使用内置的**Ray自动扩缩器**进行自动扩展。

![Ray集群](../../../../../../docs/blueprints/ai-ml/img/ray-cluster.svg)

*来源：https://docs.ray.io/en/latest/cluster/key-concepts.html*

## Ray on Kubernetes

通过[**KubeRay operator**](https://ray-project.github.io/kuberay/)支持在Kubernetes（包括Amazon EKS）上部署Ray集群。该 operator提供了一种Kubernetes原生方式来管理Ray集群。KubeRay operator的安装涉及部署 operator和`RayCluster`、`RayJob`和`RayService`的CRD，如[此处](https://ray-project.github.io/kuberay/deploy/helm/)所述。

在Kubernetes上部署Ray可以提供几个好处：

1. 可扩展性：Kubernetes允许您根据工作负载需求扩展或缩减Ray集群，使管理大规模分布式应用程序变得容易。

1. 容错性：Kubernetes提供内置机制来处理节点故障并确保Ray集群的高可用性。

1. 资源分配：使用Kubernetes，您可以轻松分配和管理Ray工作负载的资源，确保它们能够访问最佳性能所需的资源。

1. 可移植性：通过在Kubernetes上部署Ray，您可以在多个云和本地数据中心运行工作负载，使应用程序的迁移变得容易。

1. 监控：Kubernetes提供丰富的监控功能，包括指标和日志记录，使故障排除和性能优化变得容易。

总的来说，在Kubernetes上部署Ray可以简化分布式应用程序的部署和管理，使其成为许多需要运行大规模机器学习工作负载的组织的热门选择。

在继续部署之前，请确保您已阅读官方[文档](https://docs.ray.io/en/latest/cluster/kubernetes/index.html)的相关部分。

![Kubernetes上的Ray](../../../../../../docs/blueprints/ai-ml/img/ray_on_kubernetes.webp)

*来源：https://docs.ray.io/en/latest/cluster/kubernetes/index.html*

## 部署示例

在这个[示例](https://github.com/awslabs/data-on-eks/tree/main/ai-ml/ray/terraform)中，您将使用KubeRay operator在Amazon EKS上配置Ray集群。该示例还演示了使用Karpenter对特定作业的Ray集群的工作节点进行自动扩展。


![Ray on EKS](../../../../../../docs/blueprints/ai-ml/img/ray-on-eks.png)

<CollapsibleContent header={<h3><span>先决条件</span></h3>}>

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [python3](https://www.python.org/)
6. [ray](https://docs.ray.io/en/master/ray-overview/installation.html#from-wheels)

</CollapsibleContent>

<CollapsibleContent header={<h3><span>部署带有KubeRay operator的EKS集群</span></h3>}>

#### 克隆仓库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

#### 初始化Terraform

导航到示例目录

```bash
cd data-on-eks/ai-ml/ray/terraform
```

#### 运行安装脚本


使用提供的辅助脚本`install.sh`运行terraform init和apply命令。默认情况下，脚本将EKS集群部署到`us-west-2`区域。更新`variables.tf`以更改区域。这也是更新任何其他输入变量或对terraform模板进行任何其他更改的时机。


```bash
./install .sh
```

</CollapsibleContent>

<CollapsibleContent header={<h3><span>验证部署</span></h3>}>

更新本地kubeconfig，以便我们可以访问kubernetes集群

```bash
aws eks update-kubeconfig --name ray-cluster #或者您用于EKS集群的任何名称
```

首先，让我们验证集群中是否有工作节点在运行。

```bash
kubectl get nodes
```
:::info
```bash
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-1-26-241.ec2.internal   Ready    <none>   10h   v1.24.9-eks-49d8fe8
ip-10-1-4-21.ec2.internal     Ready    <none>   10h   v1.24.9-eks-49d8fe8
ip-10-1-40-196.ec2.internal   Ready    <none>   10h   v1.24.9-eks-49d8fe8
```
:::

接下来，让我们验证所有pod是否正在运行。

```bash
kubectl get pods -n kuberay-operator
```
:::info
```bash
NAME                               READY   STATUS    RESTARTS        AGE
kuberay-operator-7b5c85998-vfsjr   1/1     Running   1 (1h37m ago)   1h
```
:::


此时，我们已准备好部署Ray集群。
</CollapsibleContent>

<CollapsibleContent header={<h3><span>部署Ray集群和工作负载</span></h3>}>

为了方便起见，我们将Ray集群的helm chart部署打包为可重复使用的terraform[模块](https://github.com/awslabs/data-on-eks/tree/main/ai-ml/ray/terraform/modules/ray-cluster/)。这使我们能够为多个数据科学团队部署Ray集群时，将组织最佳实践和要求编码化。该模块还创建了karpenter所需的配置，以便能够在需要时为Ray应用程序配置EC2实例，并在作业期间使用。这个模型可以通过GitOps工具（如ArgoCD或Flux）复制，但在这里通过terraform进行演示。

##### XGBoost

首先，我们将为[XGBoost基准测试](https://docs.ray.io/en/latest/cluster/kubernetes/examples/ml-example.html#kuberay-ml-example)示例作业部署一个Ray集群。

转到xgboost目录，然后执行terraform init和plan。

```bash
cd examples/xgboost
terraform init
terraform plan
```

如果更改看起来不错，让我们应用它们。

```bash
terraform apply -auto-approve
```

当RayCluster pod进入pending状态时，Karpenter将根据我们提供的`Provisioner`和`AWSNodeTemplate`配置配置一个EC2实例。我们可以检查是否已创建新节点。

```bash
kubectl get nodes
```

:::info
```bash
NAME                          STATUS   ROLES    AGE     VERSION
# 新节点出现
ip-10-1-13-204.ec2.internal   Ready    <none>   2m22s   v1.24.9-eks-49d8fe8
ip-10-1-26-241.ec2.internal   Ready    <none>   12h     v1.24.9-eks-49d8fe8
ip-10-1-4-21.ec2.internal     Ready    <none>   12h     v1.24.9-eks-49d8fe8
ip-10-1-40-196.ec2.internal   Ready    <none>   12h     v1.24.9-eks-49d8fe8
```
:::

等待RayCluster头节点pod配置完成。

```bash
kubectl get pods -n xgboost
```
:::info
```
NAME                         READY   STATUS    RESTARTS   AGE
xgboost-kuberay-head-585d6   2/2     Running   0          5m42s
```
:::

现在我们准备运行XGBoost的示例训练基准测试。首先，打开另一个终端并将Ray服务器转发到我们的localhost。

```sh
kubectl port-forward service/xgboost-kuberay-head-svc -n xgboost 8265:8265
```
:::info
```bash
Forwarding from 127.0.0.1:8265 -> 8265
Forwarding from [::1]:8265 -> 8265
```
:::

提交XGBoost基准测试的ray作业。

```bash
python job/xgboost_submit.py
```

您可以在浏览器中打开 http://localhost:8265 来监控作业进度。如果执行过程中有任何失败，可以在Jobs部分的日志中查看。

![Ray仪表板](../../../../../../docs/blueprints/ai-ml/img/ray-dashboard.png)

随着作业的进行，您会注意到Ray自动扩缩器将根据RayCluster配置中定义的自动扩展配置配置额外的ray工作节点pod。这些工作节点pod最初将保持在pending状态。这将触发karpenter启动新的EC2实例，以便可以调度pending的pod。在工作节点pod进入running状态后，作业将继续完成。

```bash
kubectl get nodes
```
:::info
```bash
NAME                          STATUS    ROLES    AGE   VERSION
ip-10-1-1-241.ec2.internal    Unknown   <none>   1s
ip-10-1-10-211.ec2.internal   Unknown   <none>   1s
ip-10-1-13-204.ec2.internal   Ready     <none>   24m   v1.24.9-eks-49d8fe8
ip-10-1-26-241.ec2.internal   Ready     <none>   12h   v1.24.9-eks-49d8fe8
ip-10-1-3-64.ec2.internal     Unknown   <none>   7s
ip-10-1-4-21.ec2.internal     Ready     <none>   12h   v1.24.9-eks-49d8fe8
ip-10-1-40-196.ec2.internal   Ready     <none>   12h   v1.24.9-eks-49d8fe8
ip-10-1-7-167.ec2.internal    Unknown   <none>   1s
ip-10-1-9-112.ec2.internal    Unknown   <none>   1s
ip-10-1-9-172.ec2.internal    Unknown   <none>   1s
```
:::

或者，您也可以使用[eks-node-viewer](https://github.com/awslabs/eks-node-viewer)来可视化集群内的动态节点使用情况。

![EKS节点查看器](../../../../../../docs/blueprints/ai-ml/img/eks-node-viewer.png)

基准测试完成后，作业日志将显示结果。根据您的配置，您可能会看到不同的结果。

:::info
```bash
Results: {'training_time': 1338.488839321999, 'prediction_time': 403.36653568099973}
```
:::
##### PyTorch

我们也可以同时部署PyTorch基准测试。我们部署一个单独的Ray集群，并为Karpenter工作节点配置自己的配置。不同的作业可能对Ray集群有不同的要求，例如不同版本的Ray库或EC2实例配置，如使用Spot市场或GPU实例。我们利用Ray集群pod规范中的节点污点和容忍度来匹配Ray集群配置和Karpenter配置，从而利用Karpenter提供的灵活性。

转到PyTorch目录，并像之前一样运行terraform init和plan。

```bash
cd ../pytorch
terraform init
terraform plan
```

应用更改。


```bash
terraform apply -auto-approve
```

等待pytorch Ray集群头节点pod准备就绪。

```bash
kubectl get pods -n pytorch -w
```

:::info
```bash
NAME                         READY   STATUS    RESTARTS   AGE
pytorch-kuberay-head-9tx56   0/2     Pending   0          43s
```
:::

运行后，我们可以转发服务器的端口，注意我们将其转发到另一个本地端口，因为8265可能被xgboost连接占用。

```bash
kubectl port-forward service/pytorch-kuberay-head-svc -n pytorch 8266:8265
```

然后我们可以提交PyTorch基准测试工作负载的作业。

```bash
python job/pytorch_submit.py
```

您可以打开 http://localhost:8266 来监控pytorch基准测试的进度。
</CollapsibleContent>

<CollapsibleContent header={<h3><span>清理</span></h3>}>

:::caution
为避免对您的AWS账户产生不必要的费用，请删除在此部署期间创建的所有AWS资源。
:::

销毁pytorch的Ray集群，然后是xgboost的Ray集群。

从pytorch目录。

```bash
cd ../pytorch
terraform destroy -auto-approve
```

从xgboost目录。

```bash
cd ../xgboost
terraform destroy -auto-approve
```

使用提供的辅助脚本`cleanup.sh`来拆除EKS集群和其他AWS资源。

```bash
cd ../../
./cleanup.sh
```

</CollapsibleContent>
