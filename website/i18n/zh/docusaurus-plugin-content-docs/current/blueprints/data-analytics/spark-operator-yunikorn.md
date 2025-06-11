---
sidebar_position: 2
sidebar_label: 带有 YuniKorn 的 Spark Operator
hide_table_of_contents: true
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

import TaxiTripExecute from '../../../../../../docs/blueprints/data-analytics/_taxi_trip_exec.md'
import ReplaceS3BucketPlaceholders from '../../../../../../docs/blueprints/data-analytics/_replace_s3_bucket_placeholders.mdx';

import CodeBlock from '@theme/CodeBlock';

# 带有 YuniKorn 的 Spark Operator

## 介绍

Data on EKS 蓝图的 EKS 集群设计针对使用 Spark Operator 和 Apache YuniKorn 作为批处理调度器运行 Spark 应用程序进行了优化。此蓝图利用 Karpenter 来扩展工作节点，使用 AWS for FluentBit 进行日志记录，并结合 Prometheus、Amazon Managed Prometheus 和开源 Grafana 进行可观测性。此外，Spark History Server Live UI 通过 NLB 和 NGINX 入口控制器配置，用于监控正在运行的 Spark 作业。

<CollapsibleContent header={<h2><span>使用 Karpenter 的 Spark 工作负载</span></h2>}>

使用 Karpenter 作为自动扩缩器，消除了对 Spark 工作负载的托管节点组和集群自动扩缩器的需求。在这种设计中，Karpenter 及其节点池负责创建按需实例和竞价型实例，根据用户需求动态选择实例类型。与集群自动扩缩器相比，Karpenter 提供了更好的性能，节点扩展更高效，响应时间更快。Karpenter 的关键特性包括从零开始扩展的能力，优化资源利用率，并在没有资源需求时降低成本。此外，Karpenter 支持多个节点池，为定义不同工作负载类型（如计算密集型、内存密集型和 GPU 密集型任务）所需的基础设施提供了更大的灵活性。此外，Karpenter 与 Kubernetes 无缝集成，根据观察到的工作负载和扩展事件，提供对集群大小的自动实时调整。这使得 EKS 集群设计更加高效和经济，能够适应 Spark 应用程序和其他工作负载不断变化的需求。

![img.png](../../../../../../docs/blueprints/data-analytics/img/eks-spark-operator-karpenter.png)

蓝图在下面的选项卡中配置了 Karpenter 节点池和 Ec2 类。

<Tabs>
<TabItem value="spark-memory-optimized" label="spark-memory-optimized">

此节点池使用 r5d 实例类型，从 xlarge 到 8xlarge 大小，非常适合需要更多内存的 Spark 作业。

要查看 Karpenter 配置，[请在此处查看 `addons.tf` 文件](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/addons.tf#L177-L223)
</TabItem>

<TabItem value="spark-graviton-memory-optimized" label="spark-graviton-memory-optimized">

此节点池使用 r6g、r6gd、r7g、r7gd 和 r8g 实例类型，从 4xlarge 到 16xlarge 大小

要查看 Karpenter 配置，[请在此处查看 `addons.tf` 文件](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/addons.tf#L117-L170)
</TabItem>


<TabItem value="spark-compute-optimized" label="spark-compute-optimized">

此节点池使用 C5d 实例类型，从 4xlarge 到 24xlarge 大小，非常适合需要更多 CPU 时间的 Spark 作业。

要查看 Karpenter 配置，[请在此处查看 `addons.tf` 文件](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/addons.tf#L63-L110)
</TabItem>

<TabItem value="spark-vertical-ebs-scale" label="spark-vertical-ebs-scale">

此节点池使用广泛的 EC2 实例类型，并在引导过程中创建并挂载辅助 EBS 卷。此卷大小根据 Ec2 实例上的核心数量进行扩展。
这提供了一个可用于 Spark 工作负载的辅助存储位置，减少了对实例根卷的负载，避免了对系统守护进程或 kubelet 的影响。由于较大的节点可以接受更多的 Pod，引导过程会为较大的实例创建更大的卷。

要查看 Karpenter 配置，[请在此处查看 `addons.tf` 文件](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/addons.tf#L230-L355)
</TabItem>

</Tabs>
</CollapsibleContent>

<CollapsibleContent header={<h2><span>用于 Spark Shuffle 数据的 NVMe SSD 实例存储</span></h2>}>

需要注意的是，此 EKS 集群设计中的节点池利用每个节点的 NVMe SSD 实例存储作为 Spark 工作负载的 shuffle 存储。这些高性能存储选项在所有 "d" 类型实例中都可用。

将 NVMe SSD 实例存储用作 Spark 的 shuffle 存储带来了众多优势。首先，它提供低延迟和高吞吐量的数据访问，显著提高 Spark 的 shuffle 性能。这导致作业完成时间更快，整体应用程序性能增强。其次，使用本地 SSD 存储减少了对远程存储系统（如 EBS 卷）的依赖，这些系统在 shuffle 操作期间可能成为瓶颈。这也减少了为 shuffle 数据配置和管理额外 EBS 卷相关的成本。最后，通过利用 NVMe SSD 存储，EKS 集群设计提供了更好的资源利用率和更高的性能，使 Spark 应用程序能够更高效地处理更大的数据集并解决更复杂的分析工作负载。这种优化的存储解决方案最终有助于构建一个更具可扩展性和成本效益的 EKS 集群，专为在 Kubernetes 上运行 Spark 工作负载而定制。

NVMe SSD 实例存储由实例启动时的引导脚本配置（[Karpenter 节点池配置了 `instanceStorePolicy: RAID0`](https://karpenter.sh/docs/concepts/nodeclasses/#specinstancestorepolicy)）。NVMe 设备被组合成单个 RAID0（条带化）阵列，然后挂载到 `/mnt/k8s-disks/0`。此目录进一步与 `/var/lib/kubelet`、`/var/lib/containerd` 和 `/var/log/pods` 链接，确保写入这些位置的所有数据都存储在 NVMe 设备上。因为在 Pod 内写入的数据将被写入这些目录之一，所以 Pod 无需利用 hostPath 挂载或 PersistentVolumes 就能受益于高性能存储。

</CollapsibleContent>

<CollapsibleContent header={<h2><span>Spark Operator</span></h2>}>

Apache Spark 的 Kubernetes Operator 旨在使指定和运行 Spark 应用程序与在 Kubernetes 上运行其他工作负载一样简单和符合习惯。

* SparkApplication 控制器，用于监视 SparkApplication 对象的创建、更新和删除事件，并对监视事件采取行动，
* 提交运行器，用于为从控制器接收到的提交运行 spark-submit，
* Spark pod 监视器，用于监视 Spark pod 并将 pod 状态更新发送到控制器，
* 变更准入 Webhook，用于根据控制器添加到 pod 上的注释处理 Spark 驱动程序和执行器 pod 的自定义设置，
* 以及名为 sparkctl 的命令行工具，用于与操作员一起工作。

下图显示了 Spark Operator 附加组件的不同组件如何交互和协同工作。

![img.png](../../../../../../docs/blueprints/data-analytics/img/spark-operator.png)

</CollapsibleContent>

<CollapsibleContent header={<h2><span>部署解决方案</span></h2>}>

在这个[示例](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/spark-k8s-operator)中，您将配置运行带有开源 Spark Operator 和 Apache YuniKorn 的 Spark 作业所需的以下资源。

此示例将 Spark K8s Operator 部署到新的 VPC 中的 EKS 集群。

- 创建一个新的示例 VPC、2 个私有子网、2 个公共子网和 2 个 RFC6598 空间（100.64.0.0/10）中的子网，用于 EKS Pod。
- 为公共子网创建互联网网关，为私有子网创建 NAT 网关
- 创建带有公共端点（仅用于演示目的）的 EKS 集群控制平面，带有用于基准测试和核心服务的托管节点组，以及用于 Spark 工作负载的 Karpenter 节点池。
- 部署指标服务器、Spark-operator、Apache Yunikorn、Karpenter、集群自动扩缩器、Grafana、AMP 和 Prometheus 服务器。

### 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### 部署

克隆仓库。

```bash
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks
export DOEKS_HOME=$(pwd)
```

如果 DOEKS_HOME 未设置，您可以随时从 data-on-eks 目录使用 `export
DATA_ON_EKS=$(pwd)` 手动设置它。

导航到示例目录之一并运行 `install.sh` 脚本。

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator
chmod +x install.sh
./install.sh
```

现在创建一个 S3_BUCKET 变量，保存安装期间创建的存储桶名称。
此存储桶将在后续示例中用于存储输出数据。如果 S3_BUCKET 未设置，您可以再次运行以下命令。

```bash
export S3_BUCKET=$(terraform output -raw s3_bucket_id_spark_history_server)
echo $S3_BUCKET
```

</CollapsibleContent>

<CollapsibleContent header={<h2><span>使用 Karpenter 执行示例 Spark 作业</span></h2>}>

导航到示例目录。您需要将此文件中的 `<S3_BUCKET>` 占位符替换为之前创建的存储桶名称。您可以通过运行 echo $S3_BUCKET 获取该值。

要自动执行此操作，您可以运行以下命令，它将创建一个 .old 备份文件并为您进行替换。


```bash
sed -i.old s/\<S3_BUCKET\>/${S3_BUCKET}/g ./pyspark-pi-job.yaml
```

提交 Spark 作业

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator/examples/karpenter
kubectl apply -f pyspark-pi-job.yaml
```

使用以下命令监控作业状态。
您应该看到由 karpenter 触发的新节点，YuniKorn 将在此节点上调度一个驱动程序 pod 和 2 个执行器 pod。

```bash
kubectl get pods -n spark-team-a -w
```

如果 pod 已经完成，您可以检查 SparkApplication 的状态：
```bash
kubectl describe sparkapplication pyspark-pi-karpenter -n spark-team-a
```

您可以尝试以下示例，利用多个 Karpenter 节点池、EBS 作为动态 PVC 而不是 SSD 以及 YuniKorn 组调度。

## 将示例数据放入 S3

<TaxiTripExecute />

## 用于 Spark shuffle 存储的 NVMe 临时 SSD 磁盘

使用基于 NVMe 的临时 SSD 磁盘作为驱动程序和执行器 shuffle 存储的示例 PySpark 作业

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator/examples/karpenter/
```
<!-- Docusaurus will not render the {props.filename} inside of a ```codeblock``` -->
<ReplaceS3BucketPlaceholders filename="./nvme-ephemeral-storage.yaml" />
```bash
sed -i.old s/\<S3_BUCKET\>/${S3_BUCKET}/g ./nvme-ephemeral-storage.yaml
```

现在存储桶名称已就位，您可以创建 Spark 作业。

```bash
kubectl apply -f nvme-ephemeral-storage.yaml
```

## 用于 shuffle 存储的 EBS 动态 PVC
使用 EBS ON_DEMAND 卷通过动态 PVC 作为驱动程序和执行器 shuffle 存储的示例 PySpark 作业

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator/examples/karpenter/
```
<!-- Docusaurus will not render the {props.filename} inside of a ```codeblock``` -->
<ReplaceS3BucketPlaceholders filename="./ebs-storage-dynamic-pvc.yaml" />
```bash
sed -i.old s/\<S3_BUCKET\>/${S3_BUCKET}/g ./ebs-storage-dynamic-pvc.yaml
```

现在存储桶名称已就位，您可以创建 Spark 作业。

```bash
kubectl apply -f ebs-storage-dynamic-pvc.yaml
```

## 使用基于 NVMe 的 SSD 磁盘进行 shuffle 存储的 Apache YuniKorn 组调度

使用 Apache YuniKorn 和 Spark Operator 进行组调度 Spark 作业

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator/examples/karpenter/
```
<!-- Docusaurus will not render the {props.filename} inside of a ```codeblock``` -->
<ReplaceS3BucketPlaceholders filename="./nvme-storage-yunikorn-gang-scheduling.yaml" />
```bash
sed -i.old s/\<S3_BUCKET\>/${S3_BUCKET}/g ./nvme-storage-yunikorn-gang-scheduling.yaml
```

现在存储桶名称已就位，您可以创建 Spark 作业。

```bash
kubectl apply -f nvme-storage-yunikorn-gang-scheduling.yaml
```

</CollapsibleContent>

<CollapsibleContent header={<h2><span>带有 Graviton 和 Intel 的 Karpenter 节点池权重</span></h2>}>

## 使用 Karpenter 节点池权重在 AWS Graviton 和 Intel EC2 实例上运行 Spark 作业

客户经常寻求利用 AWS Graviton 实例运行 Spark 作业，因为与传统 Intel 实例相比，它们可以节省成本并提高性能。然而，一个常见的挑战是特定区域或可用区中 Graviton 实例的可用性，尤其是在高需求时期。为了解决这个问题，需要一个回退到等效 Intel 实例的策略。

#### 解决方案
**步骤 1：创建多架构 Spark Docker 镜像**
首先，通过创建多架构 Docker 镜像，确保您的 Spark 作业可以在 AWS Graviton（ARM 架构）和 Intel（AMD 架构）实例上运行。您可以在示例目录中找到示例 [Dockerfile](../../../../../../../analytics/terraform/spark-k8s-operator/examples/docker/Dockerfile) 和[将此镜像构建并推送到 Amazon Elastic Container Registry (ECR) 的说明](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/spark-k8s-operator/examples/docker)。

**步骤 2：部署带有权重的两个 Karpenter 节点池**
部署两个单独的 Karpenter 节点池：一个配置为 Graviton 实例，另一个配置为 Intel 实例。

Graviton 节点池（ARM）：将 Graviton 节点池的权重设置为 `100`。这优先考虑 Graviton 实例用于您的 Spark 工作负载。

Intel 节点池（AMD）：将 Intel 节点池的权重设置为 `50`。这确保当 Graviton 实例不可用或达到其最大 CPU 容量时，Karpenter 将回退到 Intel 节点池。

内存优化的 Karpenter 节点池配置了这些权重。

<Tabs>
<TabItem value="spark-memory-optimized" label="spark-memory-optimized">

此节点池使用 r5d 实例类型，从 xlarge 到 8xlarge 大小，非常适合需要更多内存的 Spark 作业。

要查看 Karpenter 配置，[请在此处查看 `addons.tf` 文件](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/addons.tf#L177-L223)
</TabItem>

<TabItem value="spark-graviton-memory-optimized" label="spark-graviton-memory-optimized">

此节点池使用 r6g、r6gd、r7g、r7gd 和 r8g 实例类型，从 4xlarge 到 16xlarge 大小

要查看 Karpenter 配置，[请在此处查看 `addons.tf` 文件](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/addons.tf#L117-L170)
</TabItem>
</Tabs>

**步骤 3：使用针对两个节点池的标签选择器**
由于两个节点池都有标签 `multiArch: Spark`，我们可以使用匹配该标签的 NodeSelector 配置 Spark 作业。这将允许 Karpenter 从两个内存优化节点池中配置节点，并且由于上面配置的权重，它将从 Graviton 实例开始。

```yaml
    nodeSelector:
      multiArch: Spark
```

</CollapsibleContent>


<CollapsibleContent header={<h2><span>清理</span></h2>}>

:::caution
为避免对您的 AWS 账户产生不必要的费用，请删除在此部署期间创建的所有 AWS 资源
:::

此脚本将使用 `-target` 选项清理环境，确保所有资源按正确顺序删除。

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator && chmod +x cleanup.sh
./cleanup.sh
```

</CollapsibleContent>
