---
sidebar_position: 2
sidebar_label: 使用 Karpenter 的 EMR on EKS
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

# 使用 [Karpenter](https://karpenter.sh/) 的 EMR on EKS

## 介绍

在这个[模式](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/emr-eks-karpenter)中，您将部署一个 EMR on EKS 集群并使用 [Karpenter](https://karpenter.sh/) Nodepool 来扩展 Spark 作业。

**架构**
![emr-eks-karpenter](../../../../../../docs/blueprints/amazon-emr-on-eks/img/emr-eks-karpenter.png)

此模式使用有主见的默认值来保持部署体验简单，但也保持灵活性，以便您可以在部署期间选择必要的插件。如果您是 EMR on EKS 的新手，我们建议保持默认值，只有在有可行的替代选项时才进行自定义。

在基础设施方面，此模式创建的资源如下：

- 创建具有公共端点的 EKS 集群控制平面（推荐用于演示/概念验证环境）
- 一个托管节点组
  - 核心节点组，包含跨多个可用区的 3 个实例，用于运行系统关键 Pod。例如，Cluster Autoscaler、CoreDNS、可观测性、日志记录等。
- 启用 EMR on EKS
  - 为数据团队创建两个命名空间（`emr-data-team-a`、`emr-data-team-b`）
  - 为两个命名空间创建 Kubernetes 角色和角色绑定（`emr-containers` 用户）
  - 两个团队作业执行所需的 IAM 角色
  - 使用 `emr-containers` 用户和 `AWSServiceRoleForAmazonEMRContainers` 角色更新 `AWS_AUTH` 配置映射
  - 在作业执行角色和 EMR 托管服务账户的身份之间创建信任关系
  - 为 `emr-data-team-a` 和 `emr-data-team-b` 创建 EMR 虚拟集群以及两者的 IAM 策略

您可以在下面看到可用插件的列表。
:::tip
我们建议在专用的 EKS 托管节点组（如此模式提供的 `core-node-group`）上运行所有默认系统插件。
:::
:::danger
我们不建议删除关键插件（`Amazon VPC CNI`、`CoreDNS`、`Kube-proxy`）。
:::
| 插件 | 默认启用？ | 好处 | 链接 |
| :---  | :----: | :---- | :---- |
| Amazon VPC CNI | 是 | VPC CNI 作为 [EKS 插件](https://docs.aws.amazon.com/eks/latest/userguide/eks-networking-add-ons.html) 可用，负责为您的 spark 应用程序 Pod 创建 ENI 和 IPv4 或 IPv6 地址 | [VPC CNI 文档](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html) |
| CoreDNS | 是 | CoreDNS 作为 [EKS 插件](https://docs.aws.amazon.com/eks/latest/userguide/eks-networking-add-ons.html) 可用，负责解析 spark 应用程序和 Kubernetes 集群的 DNS 查询 | [EKS CoreDNS 文档](https://docs.aws.amazon.com/eks/latest/userguide/managing-coredns.html) |
| Kube-proxy | 是 | Kube-proxy 作为 [EKS 插件](https://docs.aws.amazon.com/eks/latest/userguide/eks-networking-add-ons.html) 可用，它维护节点上的网络规则并启用到 spark 应用程序 Pod 的网络通信 | [EKS kube-proxy 文档](https://docs.aws.amazon.com/eks/latest/userguide/managing-kube-proxy.html) |
| Amazon EBS CSI 驱动程序 | 是 | EBS CSI 驱动程序作为 [EKS 插件](https://docs.aws.amazon.com/eks/latest/userguide/eks-networking-add-ons.html) 可用，它允许 EKS 集群管理 EBS 卷的生命周期 | [EBS CSI 驱动程序文档](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)
| Karpenter | 是 | Karpenter 是无节点组的自动扩展器，为 Kubernetes 集群上的 spark 应用程序提供即时计算容量 | [Karpenter 文档](https://karpenter.sh/) |
| Cluster Autoscaler | 是 | Kubernetes Cluster Autoscaler 自动调整 Kubernetes 集群的大小，可用于扩展集群中的节点组（如 `core-node-group`） | [Cluster Autoscaler 文档](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md) |
| 集群比例自动扩展器 | 是 | 这负责在您的 Kubernetes 集群中扩展 CoreDNS Pod | [集群比例自动扩展器文档](https://github.com/kubernetes-sigs/cluster-proportional-autoscaler) |
| Metrics server | 是 | Kubernetes metrics server 负责聚合集群内的 CPU、内存和其他容器资源使用情况 | [EKS Metrics Server 文档](https://docs.aws.amazon.com/eks/latest/userguide/metrics-server.html) |
| Prometheus | 是 | Prometheus 负责监控 EKS 集群，包括 EKS 集群中的 spark 应用程序。我们使用 Prometheus 部署来抓取和摄取指标到 Amazon Managed Prometheus 和 Kubecost | [Prometheus 文档](https://prometheus.io/docs/introduction/overview/) |
| Amazon Managed Prometheus | 是 | 这负责存储和扩展 EKS 集群和 spark 应用程序指标 | [Amazon Managed Prometheus 文档](https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-Prometheus.html) |
| Kubecost | 是 | Kubecost 负责按 Spark 应用程序提供成本分解。您可以基于每个作业、命名空间或标签监控成本 | [EKS Kubecost 文档](https://docs.aws.amazon.com/eks/latest/userguide/cost-monitoring.html) |
| CloudWatch 指标 | 否 | CloudWatch 容器洞察指标显示了在 CloudWatch 仪表板上监控 AWS 资源和 EKS 资源的简单和标准化方式 | [CloudWatch 容器洞察文档](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-EKS.html) |
|AWS for Fluent-bit | 否 | 这可用于将 EKS 集群和工作节点日志发布到 CloudWatch Logs 或第三方日志系统 | [AWS For Fluent-bit 文档](https://github.com/aws/aws-for-fluent-bit) |
| FSx for Lustre CSI 驱动程序 | 否 | 这可用于使用 FSx for Lustre 运行 Spark 应用程序 | [FSx for Lustre CSI 驱动程序文档](https://docs.aws.amazon.com/eks/latest/userguide/fsx-csi.html) |

<CollapsibleContent header={<h3><span>自定义插件</span></h3>}>

### 自定义插件

您可以随时通过更改 `addons.tf` 中推荐的系统插件或更改 `variables.tf` 中的可选插件来自定义部署。

例如，假设您想要删除 Amazon Managed Prometheus，因为您有另一个捕获 Prometheus 指标的应用程序，您可以使用您喜欢的编辑器编辑 `addons.tf`，找到 Amazon Managed Prometheus 并更改为 `false`
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

如果您想在运行 Spark 应用程序时使用 FSx for Lustre 存储来存储 shuffle 文件或从 S3 访问数据，您可以通过在 `variables.tf` 中搜索 FSx 并编辑文件来安装 FSx CSI 驱动程序
```yaml
variable "enable_fsx_for_lustre" {
  default     = false
  description = "Deploys fsx for lustre addon, storage class and static FSx for Lustre filesystem for EMR"
  type        = bool
}
```
保存更改后，如果这是新安装，请按照[部署指南](#部署解决方案)进行操作，或者对于现有安装使用 Terraform 应用这些更改
```
terraform apply
```

</CollapsibleContent>

<CollapsibleContent header={<h2><span>部署解决方案</span></h2>}>

让我们来看看部署步骤

### 先决条件：

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

_注意：目前 Amazon Managed Prometheus 仅在选定区域受支持。请参阅此[用户指南](https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-Prometheus.html)了解支持的区域。_

首先，克隆存储库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到示例目录之一并运行 `install.sh` 脚本

```bash
cd data-on-eks/analytics/terraform/emr-eks-karpenter

chmod +x install.sh

./install.sh

```

### 验证资源

验证 Amazon EKS 集群和 Amazon Managed service for Prometheus

```bash
aws eks describe-cluster --name emr-eks-karpenter

aws amp list-workspaces --alias amp-ws-emr-eks-karpenter
```

创建 k8s 配置文件以与 EKS 集群进行身份验证

```bash
aws eks --region us-west-2 update-kubeconfig --name emr-eks-karpenter
```

输出显示 EKS 托管节点组节点

```bash
kubectl get nodes
```

验证 EMR on EKS 命名空间 `emr-data-team-a` 和 `emr-data-team-b`。

```bash
kubectl get ns | grep emr-data-team
```

</CollapsibleContent>

## 运行示例 Spark 作业

该模式展示了如何在多租户 EKS 集群中运行 spark 作业。示例展示了两个数据团队使用映射到其 EMR 虚拟集群的命名空间 `emr-data-team-a` 和 `emr-data-team-b`。您可以为每个团队使用不同的 Karpenter Nodepool，以便他们可以提交适合其工作负载的作业。团队还可以使用不同的存储要求来运行其 Spark 作业。例如，您可以使用具有 `taints` 的计算优化 Nodepool，并使用 pod 模板指定 `tolerations`，以便您可以在计算优化的 EC2 实例上运行 spark。在存储方面，您可以决定是使用 [EC2 实例存储](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/InstanceStorage.html) 还是 [EBS](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AmazonEBS.html) 或 [FSx for lustre](https://docs.aws.amazon.com/fsx/latest/LustreGuide/what-is.html) 卷进行数据处理。这些示例中使用的默认存储是 EC2 实例存储，因为性能优势

- `spark-compute-optimized` Nodepool 在 `c5d` 实例上运行 spark 作业。
- `spark-memory-optimized` Nodepool 在 `r5d` 实例上运行 spark 作业。
- `spark-graviton-memory-optimized` Nodepool 在 `r6gd` Graviton 实例（`ARM64`）上运行 spark 作业。

<Tabs>
<TabItem value="spark-compute-optimized" lebal="spark-compute-optimized"default>

在本教程中，您将使用使用计算优化实例的 Karpenter Nodepool。此模板利用 Karpenter AWSNodeTemplates。

<details>
<summary> 要查看计算优化实例的 Karpenter Nodepool，点击切换内容！</summary>

在[此处](https://github.com/awslabs/data-on-eks/blob/35e09a8fbe64266778e0d86fe2eb805b8373e590/analytics/terraform/emr-eks-karpenter/addons.tf#L204)验证计算优化实例的 Karpenter NodeClass 和 Nodepool 代码

</details>

要运行可以使用此 Nodepool 的 Spark 作业，您需要通过向 pod 模板添加 `tolerations` 来提交作业

例如，

```yaml
spec:
  tolerations:
    - key: "spark-compute-optimized"
      operator: "Exists"
      effect: "NoSchedule"
```

**执行示例 PySpark 作业以触发计算优化的 Karpenter Nodepool**

以下脚本需要四个输入参数 `virtual_cluster_id`、`job_execution_role_arn`、`cloudwatch_log_group_name` 和 `S3_Bucket` 来存储 PySpark 脚本、Pod 模板和输入数据。这些值由 `execute_emr_eks_job.sh` 自动填充。

:::caution

此 shell 脚本将测试数据下载到您的本地机器并上传到 S3 存储桶。在运行作业之前验证 shell 脚本。

:::

```bash
cd data-on-eks/analytics/terraform/emr-eks-karpenter/examples/nvme-ssd/karpenter-compute-provisioner/

./execute_emr_eks_job.sh

```

```
Enter the EMR Virtual Cluster ID: 4ucrncg6z4nd19vh1lidna2b3
Enter the EMR Execution Role ARN: arn:aws:iam::123456789102:role/emr-eks-karpenter-emr-eks-data-team-a
Enter the CloudWatch Log Group name: /emr-on-eks-logs/emr-eks-karpenter/emr-data-team-a
Enter the S3 Bucket for storing PySpark Scripts, Pod Templates and Input data. For e.g., s3://<bucket-name>: s3://example-bucket
```

Karpenter 可能需要 1 到 2 分钟来启动 Nodepool 模板中指定的新计算节点，然后再运行 Spark 作业。
作业完成后，节点将被排空

**验证作业执行**

```bash
kubectl get pods --namespace=emr-data-team-a -w
```

</TabItem>

<TabItem value="spark-memory-optimized" label="spark-memory-optimized">

在本教程中，您将使用使用内存优化实例的 Karpenter Nodepool。此模板使用带有 Userdata 的 AWS Node 模板。

<details>
<summary> 要查看内存优化实例的 Karpenter Nodepool，点击切换内容！</summary>

在[此处](https://github.com/awslabs/data-on-eks/blob/35e09a8fbe64266778e0d86fe2eb805b8373e590/analytics/terraform/emr-eks-karpenter/addons.tf#L204)验证内存优化实例的 Karpenter NodeClass 和 Nodepool 代码

</details>

要运行可以使用此 Nodepool 的 Spark 作业，您需要通过向 pod 模板添加 `tolerations` 来提交作业

例如，

```yaml
spec:
  tolerations:
    - key: "spark-memory-optimized"
      operator: "Exists"
      effect: "NoSchedule"
```
**执行示例 PySpark 作业以触发内存优化的 Karpenter Nodepool**

以下脚本需要四个输入参数 `virtual_cluster_id`、`job_execution_role_arn`、`cloudwatch_log_group_name` 和 `S3_Bucket` 来存储 PySpark 脚本、Pod 模板和输入数据。您可以从 `terraform apply` 输出值或通过运行 `terraform output` 获取这些值。对于 `S3_BUCKET`，要么创建新的 S3 存储桶，要么使用现有的 S3 存储桶。

:::caution

此 shell 脚本将测试数据下载到您的本地机器并上传到 S3 存储桶。在运行作业之前验证 shell 脚本。

:::

```bash
cd data-on-eks/analytics/terraform/emr-eks-karpenter/examples/nvme-ssd/karpenter-memory-provisioner/
./execute_emr_eks_job.sh
```
```
Enter the EMR Virtual Cluster ID: 4ucrncg6z4nd19vh1lidna2b3
Enter the EMR Execution Role ARN: arn:aws:iam::123456789102:role/emr-eks-karpenter-emr-eks-data-team-a
Enter the CloudWatch Log Group name: /emr-on-eks-logs/emr-eks-karpenter/emr-data-team-a
Enter the S3 Bucket for storing PySpark Scripts, Pod Templates and Input data. For e.g., s3://<bucket-name>: s3://example-bucket
```

Karpenter 可能需要 1 到 2 分钟来启动 Nodepool 模板中指定的新计算节点，然后再运行 Spark 作业。
作业完成后，节点将被排空

**验证作业执行**

```bash
kubectl get pods --namespace=emr-data-team-a -w
```
</TabItem>

<TabItem value="spark-graviton-memory-optimized" label="spark-graviton-memory-optimized">

在本教程中，您将使用使用 Graviton 内存优化实例的 Karpenter Nodepool。此模板使用带有 Userdata 的 AWS Node 模板。

<details>
<summary> 要查看 Graviton 内存优化实例的 Karpenter Nodepool，点击切换内容！</summary>

在[此处](https://github.com/awslabs/data-on-eks/blob/35e09a8fbe64266778e0d86fe2eb805b8373e590/analytics/terraform/emr-eks-karpenter/addons.tf#L204)验证 Graviton 内存优化实例的 Karpenter NodeClass 和 Nodepool 代码

</details>

要运行可以使用此 Nodepool 的 Spark 作业，您需要通过向 pod 模板添加 `tolerations` 来提交作业

例如，

```yaml
spec:
  tolerations:
    - key: "spark-graviton-memory-optimized"
      operator: "Exists"
      effect: "NoSchedule"
```
**执行示例 PySpark 作业以触发 Graviton 内存优化的 Karpenter Nodepool**

以下脚本需要四个输入参数 `virtual_cluster_id`、`job_execution_role_arn`、`cloudwatch_log_group_name` 和 `S3_Bucket` 来存储 PySpark 脚本、Pod 模板和输入数据。您可以从 `terraform apply` 输出值或通过运行 `terraform output` 获取这些值。对于 `S3_BUCKET`，要么创建新的 S3 存储桶，要么使用现有的 S3 存储桶。

:::caution

此 shell 脚本将测试数据下载到您的本地机器并上传到 S3 存储桶。在运行作业之前验证 shell 脚本。

:::

```bash
cd data-on-eks/analytics/terraform/emr-eks-karpenter/examples/nvme-ssd/karpenter-graviton-memory-provisioner/
./execute_emr_eks_job.sh
```
```
Enter the EMR Virtual Cluster ID: 4ucrncg6z4nd19vh1lidna2b3
Enter the EMR Execution Role ARN: arn:aws:iam::123456789102:role/emr-eks-karpenter-emr-eks-data-team-a
Enter the CloudWatch Log Group name: /emr-on-eks-logs/emr-eks-karpenter/emr-data-team-a
Enter the S3 Bucket for storing PySpark Scripts, Pod Templates and Input data. For e.g., s3://<bucket-name>: s3://example-bucket
```

Karpenter 可能需要 1 到 2 分钟来启动 Nodepool 模板中指定的新计算节点，然后再运行 Spark 作业。
作业完成后，节点将被排空

**验证作业执行**

```bash
kubectl get pods --namespace=emr-data-team-a -w
```
</TabItem>

</Tabs>

### 执行使用 EBS 卷和计算优化 Karpenter Nodepool 的示例 PySpark 作业

此模式使用 EBS 卷进行数据处理和计算优化 Nodepool。您可以通过更改驱动程序和执行器 pod 模板中的 nodeselector 来修改 Nodepool。要更改 Nodepool，只需将您的 pod 模板更新为所需的 Nodepool
```yaml
  nodeSelector:
    NodeGroupType: "SparkComputeOptimized"
```
您还可以更新不包含实例存储卷的 [EC2 实例](https://aws.amazon.com/ec2/instance-types/#Compute_Optimized)（例如 c5.xlarge），如果需要，可以为此练习删除 c5d

我们将创建驱动程序和执行器将使用的 Storageclass。我们将为驱动程序 pod 创建静态持久卷声明 (PVC)，但我们将为执行器使用动态创建的 ebs 卷。

使用提供的示例创建 StorageClass 和 PVC
```bash
cd data-on-eks/analytics/terraform/emr-eks-karpenter/examples/ebs-pvc/karpenter-compute-provisioner-ebs/
kubectl apply -f ebs-storageclass-pvc.yaml
```
让我们运行作业

```bash
cd data-on-eks/analytics/terraform/emr-eks-karpenter/examples/ebs-pvc/karpenter-compute-provisioner-ebs/
./execute_emr_eks_job.sh
Enter the EMR Virtual Cluster ID: 4ucrncg6z4nd19vh1lidna2b3
Enter the EMR Execution Role ARN: arn:aws:iam::123456789102:role/emr-eks-karpenter-emr-eks-data-team-a
Enter the CloudWatch Log Group name: /emr-on-eks-logs/emr-eks-karpenter/emr-data-team-a
Enter the S3 Bucket for storing PySpark Scripts, Pod Templates and Input data. For e.g., s3://<bucket-name>: s3://example-bucket
```

您会注意到 PVC `spark-driver-pvc` 将被驱动程序 pod 使用，但 Spark 将为映射到 Storageclass `emr-eks-karpenter-ebs-sc` 的执行器创建多个 ebs 卷。作业完成后，所有动态创建的 ebs 卷都将被删除

### 使用 FSx for Lustre 运行示例 Spark 作业

Amazon FSx for Lustre 是一个完全托管的共享存储选项，构建在世界上最受欢迎的高性能文件系统之上。您可以使用 FSx 存储 shuffle 文件，也可以在数据管道中存储中间数据处理任务。您可以在[文档](https://docs.aws.amazon.com/fsx/latest/LustreGuide/what-is.html)中阅读有关 FSX for Lustre 的更多信息，并在我们的[最佳实践指南](https://aws.github.io/aws-emr-containers-best-practices/storage/docs/spark/fsx-lustre/)中了解如何在 EMR on EKS 中使用此存储

在此示例中，您将学习如何部署、配置和使用 FSx for Lustre 作为 shuffle 存储。有两种使用 FSx for Lustre 的方法
- 使用静态 FSx for Lustre 卷
- 使用动态创建的 FSx for Lustre 卷

<Tabs>
<TabItem value="fsx-static" lebal="fsx-static"default>

**通过使用带有静态配置卷和计算优化 Karpenter Nodepool 的 `FSx for Lustre` 执行 Spark 作业。**

Fsx for Lustre Terraform 模块默认禁用。在运行 Spark 作业之前，请按照[自定义插件](#自定义插件)步骤进行操作。

使用以下 shell 脚本执行 Spark 作业。

此脚本需要输入参数，可以从 `terraform apply` 输出值中提取。

:::caution

此 shell 脚本将测试数据下载到您的本地机器并上传到 S3 存储桶。在运行作业之前验证 shell 脚本。

:::

```bash
cd analytics/terraform/emr-eks-karpenter/examples/fsx-for-lustre/fsx-static-pvc-shuffle-storage

./fsx-static-spark.sh
```
Karpetner 可能需要 1 到 2 分钟来启动 Nodepool 模板中指定的新计算节点，然后再运行 Spark 作业。
作业完成后，节点将被排空

**验证作业执行事件**

```bash
kubectl get pods --namespace=emr-data-team-a -w
```
这将显示带有 FSx DNS 名称的挂载 `/data` 目录

```bash
kubectl exec -ti taxidata-exec-1 -c spark-kubernetes-executor -n emr-data-team-a -- df -h

kubectl exec -ti taxidata-exec-1 -c spark-kubernetes-executor -n emr-data-team-a -- ls -lah /static
```
</TabItem>

<TabItem value="fsx-dynamic" lebal="fsx-dynamic"default>

**通过使用带有动态配置卷和计算优化 Karpenter Nodepool 的 `FSx for Lustre` 执行 Spark 作业。**

Fsx for Lustre Terraform 模块默认禁用。在运行 Spark 作业之前，请按照[自定义插件](#自定义插件)步骤进行操作。

通过使用 `FSx for Lustre` 作为驱动程序和执行器 Pod 的 Shuffle 存储，使用动态配置的 FSx 文件系统和持久卷执行 Spark 作业。
使用以下 shell 脚本执行 Spark 作业。

此脚本需要输入参数，可以从 `terraform apply` 输出值中提取。

:::caution

此 shell 脚本将测试数据下载到您的本地机器并上传到 S3 存储桶。在运行作业之前验证 shell 脚本。

:::

```bash
cd analytics/terraform/emr-eks-karpenter/examples/fsx-for-lustre/fsx-dynamic-pvc-shuffle-storage

./fsx-dynamic-spark.sh
```
Karpetner 可能需要 1 到 2 分钟来启动 Nodepool 模板中指定的新计算节点，然后再运行 Spark 作业。
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

### 使用 Apache YuniKorn 批处理调度器运行示例 Spark 作业

Apache YuniKorn 是一个开源的通用资源调度器，用于管理分布式大数据处理工作负载，如 Spark、Flink 和 Storm。它旨在在共享的多租户集群环境中高效管理多个租户的资源。
Apache YuniKorn 的一些关键功能包括：
 - **灵活性**：YuniKorn 提供灵活且可扩展的架构，可以处理各种工作负载，从长期运行的服务到批处理作业。
 - **动态资源分配**：YuniKorn 使用动态资源分配机制，根据需要为工作负载分配资源，这有助于最小化资源浪费并提高整体集群利用率。
 - **基于优先级的调度**：YuniKorn 支持基于优先级的调度，允许用户根据业务需求为其工作负载分配不同的优先级。
 - **多租户**：YuniKorn 支持多租户，使多个用户能够共享同一集群，同时确保资源隔离和公平性。
 - **可插拔架构**：YuniKorn 具有可插拔架构，允许用户使用自定义调度策略和可插拔组件扩展其功能。

Apache YuniKorn 是一个强大且多功能的资源调度器，可以帮助组织高效管理其大数据工作负载，同时确保高资源利用率和工作负载性能。

**Apache YuniKorn 架构**
![Apache YuniKorn](../../../../../../docs/blueprints/amazon-emr-on-eks/img/yunikorn.png)

**Apache YuniKorn Gang 调度与 Karpenter**

Apache YuniKorn 调度器插件默认禁用。按照步骤部署 Apache YuniKorn 插件并执行 Spark 作业。

1. 使用以下内容更新 `analytics/terraform/emr-eks-karpenter/variables.tf` 文件

```terraform
variable "enable_yunikorn" {
  default     = true
  description = "Enable Apache YuniKorn Scheduler"
  type        = bool
}
```

2. 再次执行 `terrafrom apply`。这将部署 FSx for Lustre 插件和所有必要的资源。

```terraform
terraform apply -auto-approve
```

此示例演示了 [Apache YuniKorn Gang 调度](https://yunikorn.apache.org/docs/user_guide/gang_scheduling/) 与 Karpenter 自动扩展器。

```bash
cd analytics/terraform/emr-eks-karpenter/examples/nvme-ssd/karpenter-yunikorn-gangscheduling

./execute_emr_eks_job.sh
```

**验证作业执行**
Apache YuniKorn Gang 调度将为请求的执行器总数创建暂停 pod。

```bash
kubectl get pods --namespace=emr-data-team-a -w
```
验证以 `tg-` 为前缀的驱动程序和执行器 pod 表示暂停 pod。
一旦节点被 Karpenter 扩展并准备就绪，这些 pod 将被实际的 Spark 驱动程序和执行器 pod 替换。

![img.png](../../../../../../docs/blueprints/amazon-emr-on-eks/img/karpenter-yunikorn-gang-schedule.png)

<CollapsibleContent header={<h2><span>Delta Lake 表格式</span></h2>}>

Delta Lake 是一种领先的表格式，用于组织和存储数据。
表格式允许我们将存储为对象的不同数据文件抽象为单个数据集，即表。

源格式提供事务性和可扩展的层，实现高效且易于管理的数据处理。
它提供的功能包括

  - ACID（原子性、一致性、隔离性和持久性）事务
  - 数据合并操作
  - 数据版本控制
  - 处理性能

以下快速入门示例展示了 delta lake 表格式的功能和用法。

<Tabs>
  <TabItem value="deltalake" label="插入和合并操作" default>
在此示例中，我们将通过在 EMR on EKS 集群上运行 Spark 作业将 csv 文件加载到 delta lake 表格式中。

### 先决条件：

已按照本页开头的说明配置了必要的 EMR on EKS 集群。
此脚本需要输入参数，可以从 `terraform apply` 输出值中提取。
使用以下 shell 脚本执行 Spark 作业。

```bash
导航到文件夹并执行脚本：

cd analytics/terraform/emr-eks-karpenter/examples/nvme-ssd/deltalake
./execute-deltacreate.sh
```

:::tip
    此 shell 脚本将测试数据和 pyspark 脚本上传到 S3 存储桶。
    指定要上传工件和创建 delta 表的 S3 存储桶。

    通过导航到 EMR on EKS 虚拟集群并查看作业状态来验证作业成功完成。
    对于作业失败，您可以导航到 S3 存储桶 emr-on-eks-logs 并深入到作业文件夹，调查 spark 驱动程序 stdout 和 stderr 日志。
:::

**脚本执行并且 EMR on EKS 作业成功完成后，在 S3 中创建以下工件。**

![](../../../../../../docs/blueprints/amazon-emr-on-eks/img/deltalake-s3.png)

  - data 文件夹包含两个 csv 文件。(initial_emp.csv 和 update_emp.csv)
  - scripts 文件夹包含两个 pyspark 脚本。(delta-create.py 和 delta-merge.py) 用于初始加载和后续合并。
  - delta lake 表在 delta\delta_emp 文件夹中创建。
  - 还有一个符号链接清单文件在 delta\delta_emp\_symlink_format_manifest 中创建并注册到 glue 目录，供 athena 查询初始表。

** 使用 Athena 查询创建的 delta 表。 **

Athena 是 AWS 提供的无服务器查询服务。
它需要为注册到 Glue 目录的 Delta 表提供符号链接文件。
这是必需的，因为 Delta Lake 使用特定的目录结构来存储数据和元数据。
符号链接文件充当指向 Delta 日志文件最新版本的指针。没有此符号链接，
Athena 将无法确定用于给定查询的元数据文件的正确版本

  - 导航到 Athena 查询编辑器。
  - delta 表应该出现在 AWSDataCatalog 中的默认数据库下，如下所示。
  - 选择表并预览数据，验证是否显示了 initial_emp.csv 中的所有记录。

![](../../../../../../docs/blueprints/amazon-emr-on-eks/img/athena-query-1.png)

**查询输出作为表**

![](../../../../../../docs/blueprints/amazon-emr-on-eks/img/athena-query-results.png)

在第二个示例中，我们将通过运行合并 Spark 作业将更新的 csv 文件加载到先前创建的 delta lake 表中。

```bash
导航到文件夹并执行脚本：

cd analytics/terraform/emr-eks-karpenter/examples/nvme-ssd/deltalake
./execute-deltamerge.sh
```

** 验证作业成功完成。在 Athena 中重新运行查询并验证数据已合并（插入和更新）并在 delta lake 表中正确显示。**

  </TabItem>
</Tabs>

</CollapsibleContent>

## 使用托管端点运行交互式工作负载

托管端点是一个网关，提供从 EMR Studio 到 EMR on EKS 的连接，以便您可以运行交互式工作负载。您可以在[此处](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/how-it-works.html)找到有关它的更多信息。

### 创建托管端点

在此示例中，我们将在其中一个数据团队下创建托管端点。

```bash
导航到文件夹并执行脚本：

cd analytics/terraform/emr-eks-karpenter/examples/managed-endpoints
./create-managed-endpoint.sh
```
```
Enter the EMR Virtual Cluster Id: 4ucrncg6z4nd19vh1lidna2b3
Provide your EMR on EKS team (emr-data-team-a or emr-data-team-b): emr-eks-data-team-a
Enter your AWS Region: us-west-2
Enter a name for your endpoint: emr-eks-team-a-endpoint
Provide an S3 bucket location for logging (i.e. s3://my-bucket/logging/): s3://<bucket-name>/logs
Enter the EMR Execution Role ARN (i.e. arn:aws:00000000000000000:role/EMR-Execution-Role): arn:aws:iam::181460066119:role/emr-eks-karpenter-emr-data-team-a
```

脚本将提供以下内容：
- 托管端点的 JSON 配置文件
- 配置设置：
  - 默认 8G Spark 驱动程序
  - CloudWatch 监控，日志存储在提供的 S3 存储桶中
- 使用适当的安全组正确创建端点以允许使用 Karpenter
- 输出：托管端点 ID 和负载均衡器 ARN。

创建托管端点后，您可以按照[此处](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-studio-configure.html)的说明配置 EMR Studio 并将托管端点关联到工作空间。

### 端点资源清理

要删除托管端点，只需运行以下命令：

```bash
aws emr-containers delete-managed-endpoint --id <Managed Endpoint ID> --virtual-cluster-id <Virtual Cluster ID>
```

## 清理
<CollapsibleContent header={<h2><span>清理</span></h2>}>
此脚本将使用 `-target` 选项清理环境，以确保所有资源按正确顺序删除。

```bash
cd analytics/terraform/emr-eks-karpenter && chmod +x cleanup.sh
./cleanup.sh
```
</CollapsibleContent>

:::caution
为避免对您的 AWS 账户产生不必要的费用，请删除在此部署期间创建的所有 AWS 资源
:::
