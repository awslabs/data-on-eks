---
sidebar_position: 2
sidebar_label: 使用Karpenter的EMR on EKS
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

# 使用[Karpenter](https://karpenter.sh/)的EMR on EKS

## 介绍

在这个[模式](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/emr-eks-karpenter)中，您将部署一个EMR on EKS集群，并使用[Karpenter](https://karpenter.sh/) Nodepools来扩展Spark作业。

**架构**
![emr-eks-karpenter](../../../../../../docs/blueprints/amazon-emr-on-eks/img/emr-eks-karpenter.png)

这个模式使用有主见的默认设置来保持部署体验简单，但也保持灵活性，以便您可以在部署期间选择必要的附加组件。如果您是EMR on EKS的新手，我们建议保留默认设置，只有在您有可行的替代选项可用于替换时才进行自定义。

在基础设施方面，此模式创建的资源包括：

- 创建具有公共端点的EKS集群控制平面（推荐用于演示/概念验证环境）
- 一个托管节点组
  - 核心节点组，包含3个跨多个可用区的实例，用于运行系统关键pod。例如，集群自动扩展器、CoreDNS、可观察性、日志记录等。
- 启用EMR on EKS
  - 为数据团队创建两个命名空间（`emr-data-team-a`、`emr-data-team-b`）
  - 为两个命名空间创建Kubernetes角色和角色绑定（`emr-containers`用户）
  - 两个团队执行作业所需的IAM角色
  - 使用`emr-containers`用户和`AWSServiceRoleForAmazonEMRContainers`角色更新`AWS_AUTH`配置映射
  - 在作业执行角色和EMR托管服务账户的身份之间创建信任关系
  - 为`emr-data-team-a`和`emr-data-team-b`创建EMR虚拟集群和IAM策略

您可以在下面看到可用的附加组件列表。
:::tip
我们建议在专用的EKS托管节点组（如此模式提供的`core-node-group`）上运行所有默认系统附加组件。
:::
:::danger
我们不建议删除关键附加组件（`Amazon VPC CNI`、`CoreDNS`、`Kube-proxy`）。
:::
| 附加组件 | 默认启用？ | 好处 | 链接 |
| :---  | :----: | :---- | :---- |
| Amazon VPC CNI | 是 | VPC CNI作为[EKS附加组件](https://docs.aws.amazon.com/eks/latest/userguide/eks-networking-add-ons.html)提供，负责为您的spark应用程序pod创建ENI和IPv4或IPv6地址 | [VPC CNI文档](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html) |
| CoreDNS | 是 | CoreDNS作为[EKS附加组件](https://docs.aws.amazon.com/eks/latest/userguide/eks-networking-add-ons.html)提供，负责解析spark应用程序和Kubernetes集群的DNS查询 | [EKS CoreDNS文档](https://docs.aws.amazon.com/eks/latest/userguide/managing-coredns.html) |
| Kube-proxy | 是 | Kube-proxy作为[EKS附加组件](https://docs.aws.amazon.com/eks/latest/userguide/eks-networking-add-ons.html)提供，它在您的节点上维护网络规则并启用与您的spark应用程序pod的网络通信 | [EKS kube-proxy文档](https://docs.aws.amazon.com/eks/latest/userguide/managing-kube-proxy.html) |
| Amazon EBS CSI驱动程序 | 是 | EBS CSI驱动程序作为[EKS附加组件](https://docs.aws.amazon.com/eks/latest/userguide/eks-networking-add-ons.html)提供，它允许EKS集群管理EBS卷的生命周期 | [EBS CSI驱动程序文档](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)
| Karpenter | 是 | Karpenter是无节点组的自动扩展器，为Kubernetes集群上的spark应用程序提供及时的计算容量 | [Karpenter文档](https://karpenter.sh/) |
| 集群自动扩展器 | 是 | Kubernetes集群自动扩展器自动调整Kubernetes集群的大小，可用于扩展集群中的节点组（如`core-node-group`） | [集群自动扩展器文档](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md) |
| 集群比例自动扩展器 | 是 | 这负责扩展Kubernetes集群中的CoreDNS pod | [集群比例自动扩展器文档](https://github.com/kubernetes-sigs/cluster-proportional-autoscaler) |
| 指标服务器 | 是 | Kubernetes指标服务器负责聚合集群内的cpu、内存和其他容器资源使用情况 | [EKS指标服务器文档](https://docs.aws.amazon.com/eks/latest/userguide/metrics-server.html) |
| Prometheus | 是 | Prometheus负责监控EKS集群，包括EKS集群中的spark应用程序。我们使用Prometheus部署来抓取和摄取指标到Amazon托管Prometheus和Kubecost | [Prometheus文档](https://prometheus.io/docs/introduction/overview/) |
| Amazon托管Prometheus | 是 | 这负责存储和扩展EKS集群和spark应用程序指标 | [Amazon托管Prometheus文档](https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-Prometheus.html) |
| Kubecost | 是 | Kubecost负责提供按Spark应用程序细分的成本。您可以基于每个作业、命名空间或标签监控成本 | [EKS Kubecost文档](https://docs.aws.amazon.com/eks/latest/userguide/cost-monitoring.html) |
| CloudWatch指标 | 否 | CloudWatch容器洞察指标显示了一种简单且标准化的方式，不仅可以监控AWS资源，还可以在CloudWatch仪表板上监控EKS资源 | [CloudWatch容器洞察文档](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-EKS.html) |
|AWS for Fluent-bit | 否 | 这可用于将EKS集群和工作节点日志发布到CloudWatch Logs或第三方日志系统 | [AWS For Fluent-bit文档](https://github.com/aws/aws-for-fluent-bit) |
| FSx for Lustre CSI驱动程序 | 否 | 这可用于使用FSx for Lustre运行Spark应用程序 | [FSx for Lustre CSI驱动程序文档](https://docs.aws.amazon.com/eks/latest/userguide/fsx-csi.html) |


<CollapsibleContent header={<h3><span>自定义附加组件</span></h3>}>

### 自定义附加组件

您可以随时通过更改`addons.tf`中的推荐系统附加组件或更改`variables.tf`中的可选附加组件来自定义您的部署。

例如，假设您想要删除Amazon托管Prometheus，因为您有另一个捕获Prometheus指标的应用程序，您可以使用您喜欢的编辑器编辑`addons.tf`，找到Amazon托管Prometheus并将其更改为`false`
```yaml
  enable_prometheus = false
  prometheus_helm_config = {
    name       = "prometheus"
    repository = "https://prometheus-community.github.io/helm-charts"
    chart      = "prometheus"
    version    = "15.10.1"
    namespace  = "prometheus"
    timeout    = "300"
    values     = [templatefile("${path.module}/helm-values/prometheus-values.yaml", {})]
  }
```

如果您想在运行Spark应用程序时使用FSx for Lustre存储来存储shuffle文件或从S3访问数据，您可以通过在`variables.tf`中搜索FSx并编辑文件来安装FSx CSI驱动程序
```yaml
variable "enable_fsx_for_lustre" {
  default     = false
  description = "Deploys fsx for lustre addon, storage class and static FSx for Lustre filesystem for EMR"
  type        = bool
}
```
保存更改后，如果这是新安装，请按照[部署指南](#deploying-the-solution)进行操作，或者对于现有安装，使用Terraform应用这些更改
```
terraform apply
```

</CollapsibleContent>

<CollapsibleContent header={<h2><span>部署解决方案</span></h2>}>

让我们来看一下部署步骤

### 先决条件：

确保您已在机器上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

_注意：目前Amazon托管Prometheus仅在选定区域支持。请参阅此[用户指南](https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-Prometheus.html)了解支持的区域。_

首先，克隆仓库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到示例目录之一并运行`install.sh`脚本

```bash
cd data-on-eks/analytics/terraform/emr-eks-karpenter
chmod +x install.sh
./install.sh
```

### 验证资源

验证Amazon EKS集群和Amazon托管Prometheus服务

```bash
aws eks describe-cluster --name emr-eks-karpenter

aws amp list-workspaces --alias amp-ws-emr-eks-karpenter
```

验证EMR on EKS命名空间`emr-data-team-a`和`emr-data-team-b`以及`Prometheus`、`垂直Pod自动扩展器`、`指标服务器`和`集群自动扩展器`的Pod状态。

```bash
aws eks --region us-west-2 update-kubeconfig --name emr-eks-karpenter # 创建k8s配置文件以与EKS集群进行身份验证

kubectl get nodes # 输出显示EKS托管节点组节点

kubectl get ns | grep emr-data-team # 输出显示数据团队的emr-data-team-a和emr-data-team-b命名空间

kubectl get pods --namespace=prometheus # 输出显示Prometheus服务器和节点导出器pod

kubectl get pods --namespace=vpa  # 输出显示垂直Pod自动扩展器pod

kubectl get pods --namespace=kube-system | grep  metrics-server # 输出显示指标服务器pod

kubectl get pods --namespace=kube-system | grep  cluster-autoscaler # 输出显示集群自动扩展器pod
```

</CollapsibleContent>

## 运行示例Spark作业

该模式展示了如何在多租户EKS集群中运行spark作业。示例展示了两个数据团队使用命名空间`emr-data-team-a`和`emr-data-team-b`，这些命名空间映射到他们的EMR虚拟集群。您可以为每个团队使用不同的Karpenter Nodepools，以便他们可以提交适合其工作负载的作业。团队还可以使用不同的存储需求来运行他们的Spark作业。例如，您可以使用具有`taints`的计算优化Nodepool，并使用pod模板指定`tolerations`，以便您可以在计算优化的EC2实例上运行spark。在存储方面，您可以决定是使用[EC2实例存储](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/InstanceStorage.html)、[EBS](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AmazonEBS.html)还是[FSx for lustre](https://docs.aws.amazon.com/fsx/latest/LustreGuide/what-is.html)卷进行数据处理。这些示例中使用的默认存储是EC2实例存储，因为它具有性能优势。

- `spark-compute-optimized` Nodepool在`c5d`实例上运行spark作业。
- `spark-memory-optimized` Nodepool在`r5d`实例上运行spark作业。
- `spark-graviton-memory-optimized` Nodepool在`r6gd` Graviton实例(`ARM64`)上运行spark作业。

<Tabs>
<TabItem value="spark-compute-optimized" lebal="spark-compute-optimized"default>

在本教程中，您将使用使用计算优化实例的Karpenter Nodepool。此模板利用Karpenter AWSNodeTemplates。

<details>
<summary> 要查看计算优化实例的Karpenter Nodepool，请点击切换内容！</summary>

在[此处](https://github.com/awslabs/data-on-eks/blob/35e09a8fbe64266778e0d86fe2eb805b8373e590/analytics/terraform/emr-eks-karpenter/addons.tf#L204)验证Karpenter NodeClass和Nodepool代码

</details>

要运行可以使用此Nodepool的Spark作业，您需要通过向pod模板添加`tolerations`来提交作业

例如，

```yaml
spec:
  tolerations:
    - key: "spark-compute-optimized"
      operator: "Exists"
      effect: "NoSchedule"
```

**执行示例PySpark作业以触发计算优化的Karpenter Nodepool**

以下脚本需要四个输入参数`virtual_cluster_id`、`job_execution_role_arn`、`cloudwatch_log_group_name`和`S3_Bucket`来存储PySpark脚本、Pod模板和输入数据。您可以从`terraform apply`输出值或通过运行`terraform output`获取这些值。对于`S3_BUCKET`，可以创建一个新的S3存储桶或使用现有的S3存储桶。

:::caution

此shell脚本将测试数据下载到您的本地机器并上传到S3存储桶。在运行作业之前，请验证shell脚本。

:::

```bash
cd data-on-eks/analytics/terraform/emr-eks-karpenter/examples/nvme-ssd/karpenter-compute-provisioner/
./execute_emr_eks_job.sh
```
```
输入EMR虚拟集群ID: 4ucrncg6z4nd19vh1lidna2b3
输入EMR执行角色ARN: arn:aws:iam::123456789102:role/emr-eks-karpenter-emr-eks-data-team-a
输入CloudWatch日志组名称: /emr-on-eks-logs/emr-eks-karpenter/emr-data-team-a
输入用于存储PySpark脚本、Pod模板和输入数据的S3存储桶。例如，s3:/<bucket-name>: s3:/example-bucket
```

Karpenter可能需要1到2分钟的时间来启动Nodepool模板中指定的新计算节点，然后再运行Spark作业。
作业完成后，节点将被排空

**验证作业执行**

```bash
kubectl get pods --namespace=emr-data-team-a -w
```

</TabItem>

<TabItem value="spark-memory-optimized" label="spark-memory-optimized">

在本教程中，您将使用使用内存优化实例的Karpenter Nodepool。此模板使用带有用户数据的AWS节点模板。

<details>
<summary> 要查看内存优化实例的Karpenter Nodepool，请点击切换内容！</summary>

在[此处](https://github.com/awslabs/data-on-eks/blob/35e09a8fbe64266778e0d86fe2eb805b8373e590/analytics/terraform/emr-eks-karpenter/addons.tf#L204)验证Karpenter NodeClass和Nodepool代码

</details>

要运行可以使用此Nodepool的Spark作业，您需要通过向pod模板添加`tolerations`来提交作业

例如，

```yaml
spec:
  tolerations:
    - key: "spark-memory-optimized"
      operator: "Exists"
      effect: "NoSchedule"
```
**执行示例PySpark作业以触发内存优化的Karpenter Nodepool**

以下脚本需要四个输入参数`virtual_cluster_id`、`job_execution_role_arn`、`cloudwatch_log_group_name`和`S3_Bucket`来存储PySpark脚本、Pod模板和输入数据。您可以从`terraform apply`输出值或通过运行`terraform output`获取这些值。对于`S3_BUCKET`，可以创建一个新的S3存储桶或使用现有的S3存储桶。

:::caution

此shell脚本将测试数据下载到您的本地机器并上传到S3存储桶。在运行作业之前，请验证shell脚本。

:::

```bash
cd data-on-eks/analytics/terraform/emr-eks-karpenter/examples/nvme-ssd/karpenter-memory-provisioner/
./execute_emr_eks_job.sh
```
```
输入EMR虚拟集群ID: 4ucrncg6z4nd19vh1lidna2b3
输入EMR执行角色ARN: arn:aws:iam::123456789102:role/emr-eks-karpenter-emr-eks-data-team-a
输入CloudWatch日志组名称: /emr-on-eks-logs/emr-eks-karpenter/emr-data-team-a
输入用于存储PySpark脚本、Pod模板和输入数据的S3存储桶。例如，s3:/<bucket-name>: s3:/example-bucket
```

Karpenter可能需要1到2分钟的时间来启动Nodepool模板中指定的新计算节点，然后再运行Spark作业。
作业完成后，节点将被排空

**验证作业执行**

```bash
kubectl get pods --namespace=emr-data-team-a -w
```
</TabItem>

<TabItem value="spark-graviton-memory-optimized" label="spark-graviton-memory-optimized">

在本教程中，您将使用使用Graviton内存优化实例的Karpenter Nodepool。此模板使用带有用户数据的AWS节点模板。

<details>
<summary> 要查看Graviton内存优化实例的Karpenter Nodepool，请点击切换内容！</summary>

在[此处](https://github.com/awslabs/data-on-eks/blob/35e09a8fbe64266778e0d86fe2eb805b8373e590/analytics/terraform/emr-eks-karpenter/addons.tf#L204)验证Karpenter NodeClass和Nodepool代码

</details>

要运行可以使用此Nodepool的Spark作业，您需要通过向pod模板添加`tolerations`来提交作业

例如，

```yaml
spec:
  tolerations:
    - key: "spark-graviton-memory-optimized"
      operator: "Exists"
      effect: "NoSchedule"
```
**执行示例PySpark作业以触发Graviton内存优化的Karpenter Nodepool**

以下脚本需要四个输入参数`virtual_cluster_id`、`job_execution_role_arn`、`cloudwatch_log_group_name`和`S3_Bucket`来存储PySpark脚本、Pod模板和输入数据。您可以从`terraform apply`输出值或通过运行`terraform output`获取这些值。对于`S3_BUCKET`，可以创建一个新的S3存储桶或使用现有的S3存储桶。

:::caution

此shell脚本将测试数据下载到您的本地机器并上传到S3存储桶。在运行作业之前，请验证shell脚本。

:::

```bash
cd data-on-eks/analytics/terraform/emr-eks-karpenter/examples/nvme-ssd/karpenter-graviton-memory-provisioner/
./execute_emr_eks_job.sh
```
```
输入EMR虚拟集群ID: 4ucrncg6z4nd19vh1lidna2b3
输入EMR执行角色ARN: arn:aws:iam::123456789102:role/emr-eks-karpenter-emr-eks-data-team-a
输入CloudWatch日志组名称: /emr-on-eks-logs/emr-eks-karpenter/emr-data-team-a
输入用于存储PySpark脚本、Pod模板和输入数据的S3存储桶。例如，s3:/<bucket-name>: s3:/example-bucket
```

Karpenter可能需要1到2分钟的时间来启动Nodepool模板中指定的新计算节点，然后再运行Spark作业。
作业完成后，节点将被排空

**验证作业执行**

```bash
kubectl get pods --namespace=emr-data-team-a -w
```
</TabItem>

</Tabs>
### 执行使用EBS卷和计算优化Karpenter Nodepool的示例PySpark作业

此模式使用EBS卷进行数据处理和计算优化Nodepool。您可以通过更改驱动程序和执行器pod模板中的nodeselector来修改Nodepool。要更改Nodepools，只需将您的pod模板更新为所需的Nodepool
```yaml
  nodeSelector:
    NodeGroupType: "SparkComputeOptimized"
```
您还可以更新不包含实例存储卷的[EC2实例](https://aws.amazon.com/ec2/instance-types/#Compute_Optimized)（例如c5.xlarge）并在需要时删除c5d

我们将创建一个将由驱动程序和执行器使用的StorageClass。我们将为驱动程序pod创建静态持久卷声明(PVC)，但我们将为执行器使用动态创建的ebs卷。

使用提供的示例创建StorageClass和PVC
```bash
cd data-on-eks/analytics/terraform/emr-eks-karpenter/examples/ebs-pvc/karpenter-compute-provisioner-ebs/
kubectl apply -f ebs-storageclass-pvc.yaml
```
让我们运行作业

```bash
cd data-on-eks/analytics/terraform/emr-eks-karpenter/examples/ebs-pvc/karpenter-compute-provisioner-ebs/
./execute_emr_eks_job.sh
输入EMR虚拟集群ID: 4ucrncg6z4nd19vh1lidna2b3
输入EMR执行角色ARN: arn:aws:iam::123456789102:role/emr-eks-karpenter-emr-eks-data-team-a
输入CloudWatch日志组名称: /emr-on-eks-logs/emr-eks-karpenter/emr-data-team-a
输入用于存储PySpark脚本、Pod模板和输入数据的S3存储桶。例如，s3:/<bucket-name>: s3:/example-bucket
```

您会注意到PVC `spark-driver-pvc`将被驱动程序pod使用，但Spark将为执行器创建多个ebs卷，映射到StorageClass `emr-eks-karpenter-ebs-sc`。一旦作业完成，所有动态创建的ebs卷都将被删除

### 使用FSx for Lustre运行示例Spark作业

Amazon FSx for Lustre是一个完全托管的共享存储选项，基于世界上最流行的高性能文件系统构建。您可以使用FSx存储shuffle文件，也可以在数据管道中存储中间数据处理任务。您可以在[文档](https://docs.aws.amazon.com/fsx/latest/LustreGuide/what-is.html)中阅读更多关于FSX for Lustre的信息，并在我们的[最佳实践指南](https://aws.github.io/aws-emr-containers-best-practices/storage../../..../../../docs/spark/fsx-lustre/)中了解如何将此存储与EMR on EKS一起使用

在此示例中，您将学习如何部署、配置和使用FSx for Lustre作为shuffle存储。使用FSx for Lustre有两种方式：
- 使用静态FSx for Lustre卷
- 使用动态创建的FSx for Lustre卷

<Tabs>
<TabItem value="fsx-static" lebal="fsx-static"default>

**使用静态配置的卷和计算优化Karpenter Nodepool执行使用`FSx for Lustre`的Spark作业。**

Fsx for Lustre Terraform模块默认是禁用的。在运行Spark作业之前，请按照[自定义附加组件](#customizing-add-ons)步骤操作。

使用下面的shell脚本执行Spark作业。

此脚本需要可以从`terraform apply`输出值中提取的输入参数。

:::caution

此shell脚本将测试数据下载到您的本地机器并上传到S3存储桶。在运行作业之前，请验证shell脚本。

:::

```bash
cd analytics/terraform/emr-eks-karpenter/examples/fsx-for-lustre/fsx-static-pvc-shuffle-storage

./fsx-static-spark.sh
```
Karpetner可能需要1到2分钟的时间来启动Nodepool模板中指定的新计算节点，然后再运行Spark作业。
作业完成后，节点将被排空

**验证作业执行事件**

```bash
kubectl get pods --namespace=emr-data-team-a -w
```
这将显示带有FSx DNS名称的挂载的`/data`目录

```bash
kubectl exec -ti taxidata-exec-1 -c spark-kubernetes-executor -n emr-data-team-a -- df -h

kubectl exec -ti taxidata-exec-1 -c spark-kubernetes-executor -n emr-data-team-a -- ls -lah /static
```
</TabItem>

<TabItem value="fsx-dynamic" lebal="fsx-dynamic"default>

**使用动态配置的卷和计算优化Karpenter Nodepool执行使用`FSx for Lustre`的Spark作业。**

Fsx for Lustre Terraform模块默认是禁用的。在运行Spark作业之前，请按照[自定义附加组件](#customizing-add-ons)步骤操作。

使用`FSx for Lustre`作为驱动程序和执行器pod的Shuffle存储执行Spark作业，使用动态配置的FSx文件系统和持久卷。
使用下面的shell脚本执行Spark作业。

此脚本需要可以从`terraform apply`输出值中提取的输入参数。

:::caution

此shell脚本将测试数据下载到您的本地机器并上传到S3存储桶。在运行作业之前，请验证shell脚本。

:::

```bash
cd analytics/terraform/emr-eks-karpenter/examples/fsx-for-lustre/fsx-dynamic-pvc-shuffle-storage

./fsx-dynamic-spark.sh
```
Karpetner可能需要1到2分钟的时间来启动Nodepool模板中指定的新计算节点，然后再运行Spark作业。
作业完成后，节点将被排空

**验证作业执行事件**

```bash
kubectl get pods --namespace=emr-data-team-a -w
```

```bash
kubectl exec -ti taxidata-exec-1 -c spark-kubernetes-executor -n emr-data-team-a -- df -h

kubectl exec -ti taxidata-exec-1 -c spark-kubernetes-executor -n emr-data-team-a -- ls -lah /dynamic
```
</TabItem>
</Tabs>

### 使用Apache YuniKorn批处理调度器运行示例Spark作业

Apache YuniKorn是一个开源的通用资源调度器，用于管理分布式大数据处理工作负载，如Spark、Flink和Storm。它旨在有效地管理共享、多租户集群环境中多个租户之间的资源。
Apache YuniKorn的一些关键特性包括：
 - **灵活性**：YuniKorn提供了一个灵活且可扩展的架构，可以处理各种工作负载，从长时间运行的服务到批处理作业。
 - **动态资源分配**：YuniKorn使用动态资源分配机制，根据需要为工作负载分配资源，这有助于最小化资源浪费并提高整体集群利用率。
 - **基于优先级的调度**：YuniKorn支持基于优先级的调度，允许用户根据业务需求为其工作负载分配不同级别的优先级。
 - **多租户**：YuniKorn支持多租户，使多个用户能够共享同一个集群，同时确保资源隔离和公平性。
 - **可插拔架构**：YuniKorn具有可插拔架构，允许用户使用自定义调度策略和可插拔组件扩展其功能。

Apache YuniKorn是一个强大且多功能的资源调度器，可以帮助组织有效地管理其大数据工作负载，同时确保高资源利用率和工作负载性能。

**Apache YuniKorn架构**
![Apache YuniKorn](../../../../../../docs/blueprints/amazon-emr-on-eks/img/yunikorn.png)

**Apache YuniKorn与Karpenter的Gang调度**

Apache YuniKorn调度器附加组件默认是禁用的。按照以下步骤部署Apache YuniKorn附加组件并执行Spark作业。

1. 使用以下内容更新`analytics/terraform/emr-eks-karpenter/variables.tf`文件

```terraform
variable "enable_yunikorn" {
  default     = true
  description = "Enable Apache YuniKorn Scheduler"
  type        = bool
}
```

2. 再次执行`terrafrom apply`。这将部署FSx for Lustre附加组件和所有必要的资源。

```terraform
terraform apply -auto-approve
```

此示例演示了带有Karpenter自动扩展器的[Apache YuniKorn Gang调度](https://yunikorn.apache.org/docs/user_guide/gang_scheduling/)。

```bash
cd analytics/terraform/emr-eks-karpenter/examples/nvme-ssd/karpenter-yunikorn-gangscheduling

./execute_emr_eks_job.sh
```

**验证作业执行**
Apache YuniKorn Gang调度将为请求的执行器总数创建暂停pod。

```bash
kubectl get pods --namespace=emr-data-team-a -w
```
验证前缀为`tg-`的驱动程序和执行器pod，表示暂停pod。
一旦节点由Karpenter扩展并准备就绪，这些pod将被替换为实际的Spark驱动程序和执行器pod。

![img.png](../../../../../../docs/blueprints/amazon-emr-on-eks/img/karpenter-yunikorn-gang-schedule.png)

<CollapsibleContent header={<h2><span>Delta Lake表格式</span></h2>}>

Delta Lake是一种领先的表格式，用于组织和存储数据。
表格式允许我们将存储为对象的不同数据文件抽象为单一数据集，即表。

源格式提供了一个事务性和可扩展的层，实现高效且易于管理的数据处理。
它提供了以下功能：

  - ACID（原子性、一致性、隔离性和持久性）事务
  - 数据合并操作
  - 数据版本控制
  - 处理性能

以下快速入门示例展示了delta lake表格式的功能和用法。

<Tabs>
  <TabItem value="deltalake" label="插入和合并操作" default>
在此示例中，我们将通过在EMR on EKS集群上运行Spark作业，将csv文件加载到delta lake表格式中。

### 先决条件：

已按照本页开头的说明配置了必要的EMR on EKS集群。
此脚本需要可以从`terraform apply`输出值中提取的输入参数。
使用以下shell脚本执行Spark作业。


```bash
导航到文件夹并执行脚本：

cd analytics/terraform/emr-eks-karpenter/examples/nvme-ssd/deltalake
./execute-deltacreate.sh
```

:::tip
    此shell脚本将测试数据和pyspark脚本上传到S3存储桶。
    指定您想要上传工件并创建delta表的S3存储桶。

    通过导航到EMR on EKS虚拟集群并查看作业状态来验证作业是否成功完成。
    对于作业失败，您可以导航到S3存储桶emr-on-eks-logs并深入到作业文件夹，调查spark驱动程序stdout和stderr日志。
:::

**脚本执行成功且EMR on EKS作业成功完成后，S3中创建了以下工件。**

![](../../../../../../docs/blueprints/amazon-emr-on-eks/img/deltalake-s3.png)

  - 数据文件夹包含两个csv文件（initial_emp.csv和update_emp.csv）。
  - 脚本文件夹包含两个pyspark脚本（delta-create.py和delta-merge.py），用于初始加载和后续合并。
  - delta lake表在delta\delta_emp文件夹中创建。
  - 还在delta\delta_emp\_symlink_format_manifest中创建了一个符号链接清单文件，并注册到glue目录中，供athena查询初始表。


** 使用Athena查询创建的delta表。 **

Athena是AWS提供的无服务器查询服务。
它需要一个符号链接文件用于注册到Glue目录的Delta表。
这是必需的，因为Delta Lake使用特定的目录结构来存储数据和元数据。
符号链接文件作为指向Delta日志文件最新版本的指针。没有这个符号链接，
Athena将无法确定给定查询要使用的元数据文件的正确版本

  - 导航到Athena查询编辑器。
  - delta表应该出现在AWSDataCatalog下的默认数据库中，如下所示。
  - 选择表并预览数据，验证是否显示了initial_emp.csv中的所有记录。

![](../../../../../../docs/blueprints/amazon-emr-on-eks/img/athena-query-1.png)

**查询输出为表格**

![](../../../../../../docs/blueprints/amazon-emr-on-eks/img/athena-query-results.png)

在第二个示例中，我们将通过运行合并Spark作业，将更新的csv文件加载到先前创建的delta lake表中。

```bash
导航到文件夹并执行脚本：

cd analytics/terraform/emr-eks-karpenter/examples/nvme-ssd/deltalake
./execute-deltamerge.sh
```

** 验证作业是否成功完成。在Athena中重新运行查询，验证数据是否已合并（插入和更新）并在delta lake表中正确显示。**

  </TabItem>
</Tabs>

</CollapsibleContent>

## 使用托管端点运行交互式工作负载

托管端点是一个网关，提供从EMR Studio到EMR on EKS的连接，以便您可以运行交互式工作负载。您可以在[此处](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/how-it-works.html)找到更多相关信息。

### 创建托管端点

在此示例中，我们将在其中一个数据团队下创建托管端点。

```bash
导航到文件夹并执行脚本：

cd analytics/terraform/emr-eks-karpenter/examples/managed-endpoints
./create-managed-endpoint.sh
```
```
输入EMR虚拟集群Id: 4ucrncg6z4nd19vh1lidna2b3
提供您的EMR on EKS团队（emr-data-team-a或emr-data-team-b）: emr-eks-data-team-a
输入您的AWS区域: us-west-2
为您的端点输入一个名称: emr-eks-team-a-endpoint
提供用于日志记录的S3存储桶位置（例如s3:/my-bucket/logging/）: s3:/<bucket-name>/logs
输入EMR执行角色ARN（例如arn:aws:00000000000000000:role/EMR-Execution-Role）: arn:aws:iam::181460066119:role/emr-eks-karpenter-emr-data-team-a
```

该脚本将提供以下内容：
- 托管端点的JSON配置文件
- 配置设置：
  - 默认8G Spark驱动程序
  - CloudWatch监控，日志存储在提供的S3存储桶中
- 使用适当的安全组创建正确的端点，以允许使用Karpenter
- 输出：托管端点ID和负载均衡器ARN。

创建托管端点后，您可以按照[此处](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-studio-configure.html)的说明配置EMR Studio并将托管端点关联到工作区。

### 清理端点资源

要删除托管端点，只需运行以下命令：

```bash
aws emr-containers delete-managed-endpoint --id <托管端点ID> --virtual-cluster-id <虚拟集群ID>
```

## 清理
<CollapsibleContent header={<h2><span>清理</span></h2>}>
此脚本将使用`-target`选项清理环境，以确保所有资源按正确顺序删除。

```bash
cd analytics/terraform/emr-eks-karpenter && chmod +x cleanup.sh
./cleanup.sh
```
</CollapsibleContent>

:::caution
为避免对您的AWS账户产生不必要的费用，请删除在此部署期间创建的所有AWS资源
:::
