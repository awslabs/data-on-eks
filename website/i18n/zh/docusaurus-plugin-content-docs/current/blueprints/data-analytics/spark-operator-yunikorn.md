---
sidebar_position: 2
sidebar_label: Spark Operator with YuniKorn
hide_table_of_contents: true
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

import TaxiTripExecute from '../../../../../../docs/blueprints/data-analytics/_taxi_trip_exec.md'
import ReplaceS3BucketPlaceholders from '../../../../../../docs/blueprints/data-analytics/_replace_s3_bucket_placeholders.mdx';

import CodeBlock from '@theme/CodeBlock';

# Spark Operator with YuniKorn

## 介绍

Data on EKS 蓝图的 EKS 集群设计针对使用 Spark Operator 和 Apache YuniKorn 作为批处理调度器运行 Spark 应用程序进行了优化。此蓝图利用 Karpenter 来扩展工作节点，AWS for FluentBit 用于日志记录，Prometheus、Amazon Managed Prometheus 和开源 Grafana 的组合用于可观察性。此外，Spark History Server Live UI 配置为通过 NLB 和 NGINX 入口控制器监控正在运行的 Spark 作业。

<CollapsibleContent header={<h2><span>使用 Karpenter 的 Spark 工作负载</span></h2>}>

使用 Karpenter 作为自动扩展器，消除了 Spark 工作负载对托管节点组和 Cluster Autoscaler 的需求。在此设计中，Karpenter 及其 NodePool 负责创建按需和 Spot 实例，根据用户需求动态选择实例类型。与 Cluster Autoscaler 相比，Karpenter 提供了改进的性能，具有更高效的节点扩展和更快的响应时间。Karpenter 的关键功能包括从零扩展的能力，在没有资源需求时优化资源利用率并降低成本。此外，Karpenter 支持多个 NodePool，允许在为不同工作负载类型（如计算、内存和 GPU 密集型任务）定义所需基础设施时具有更大的灵活性。此外，Karpenter 与 Kubernetes 无缝集成，根据观察到的工作负载和扩展事件提供自动、实时的集群大小调整。这使得 EKS 集群设计更加高效和经济，能够适应 Spark 应用程序和其他工作负载不断变化的需求。

![img.png](../../../../../../docs/blueprints/data-analytics/img/eks-spark-operator-karpenter.png)

蓝图在下面的选项卡中配置 Karpenter NodePool 和 Ec2 类。

<Tabs>
<TabItem value="spark-memory-optimized" label="spark-memory-optimized">

此 NodePool 使用 r5d 实例类型，从 xlarge 到 8xlarge 大小，非常适合需要更多内存的 Spark 作业。

要查看 Karpenter 配置，[请在此处查看 `addons.tf` 文件](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/addons.tf#L177-L223)
</TabItem>

<TabItem value="spark-graviton-memory-optimized" label="spark-graviton-memory-optimized">

此 NodePool 使用 r6g、r6gd、r7g、r7gd 和 r8g 实例类型，从 4xlarge 到 16xlarge 大小

要查看 Karpenter 配置，[请在此处查看 `addons.tf` 文件](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/addons.tf#L117-L170)
</TabItem>

<TabItem value="spark-compute-optimized" label="spark-compute-optimized">

此 NodePool 使用 C5d 实例类型，从 4xlarge 到 24xlarge 大小，非常适合需要更多 CPU 时间的 Spark 作业。

要查看 Karpenter 配置，[请在此处查看 `addons.tf` 文件](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/addons.tf#L63-L110)
</TabItem>

<TabItem value="spark-vertical-ebs-scale" label="spark-vertical-ebs-scale">

此 NodePool 使用广泛的 EC2 实例类型，在引导过程中实例创建并挂载辅助 EBS 卷。此卷大小根据 Ec2 实例上的核心数进行扩展。
这提供了可用于 Spark 工作负载的辅助存储位置，减少实例根卷的负载并避免对系统守护程序或 kubelet 的影响。由于较大的节点可以接受更多 Pod，引导过程为较大的实例创建更大的卷。

要查看 Karpenter 配置，[请在此处查看 `addons.tf` 文件](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/addons.tf#L230-L355)
</TabItem>

</Tabs>
</CollapsibleContent>

<CollapsibleContent header={<h2><span>用于 Spark 洗牌数据的 NVMe SSD 实例存储</span></h2>}>

重要的是要注意，此 EKS 集群设计中的 NodePool 利用每个节点的 NVMe SSD 实例存储作为 Spark 工作负载的洗牌存储。这些高性能存储选项适用于所有"d"类型实例。

使用 NVMe SSD 实例存储作为 Spark 的洗牌存储带来了许多优势。首先，它提供低延迟和高吞吐量的数据访问，显著改善 Spark 的洗牌性能。这导致更快的作业完成时间和增强的整体应用程序性能。其次，使用本地 SSD 存储减少了对远程存储系统（如 EBS 卷）的依赖，这些系统在洗牌操作期间可能成为瓶颈。这也减少了为洗牌数据配置和管理额外 EBS 卷相关的成本。最后，通过利用 NVMe SSD 存储，EKS 集群设计提供了更好的资源利用率和增强的性能，允许 Spark 应用程序处理更大的数据集并更高效地处理更复杂的分析工作负载。这种优化的存储解决方案最终有助于为在 Kubernetes 上运行 Spark 工作负载量身定制更可扩展和经济高效的 EKS 集群。

NVMe SSD 实例存储由实例启动时的引导脚本配置（[Karpenter NodePool 配置为 `instanceStorePolicy: RAID0`](https://karpenter.sh/docs/concepts/nodeclasses/#specinstancestorepolicy)）。NVMe 设备组合成单个 RAID0（条带化）阵列，然后挂载到 `/mnt/k8s-disks/0`。此目录进一步与 `/var/lib/kubelet`、`/var/lib/containerd` 和 `/var/log/pods` 链接，确保写入这些位置的所有数据都存储在 NVMe 设备上。由于在 Pod 内写入的数据将写入这些目录之一，Pod 受益于高性能存储，而无需利用 hostPath 挂载或 PersistentVolume

</CollapsibleContent>

<CollapsibleContent header={<h2><span>Spark Operator</span></h2>}>

Apache Spark 的 Kubernetes Operator 旨在使指定和运行 Spark 应用程序像在 Kubernetes 上运行其他工作负载一样简单和惯用。

* 一个 SparkApplication 控制器，监视 SparkApplication 对象的创建、更新和删除事件并对监视事件采取行动，
* 一个提交运行器，为从控制器接收的提交运行 spark-submit，
* 一个 Spark Pod 监视器，监视 Spark Pod 并向控制器发送 Pod 状态更新，
* 一个变异准入 Webhook，根据控制器添加的 Pod 上的注释处理 Spark 驱动程序和执行器 Pod 的自定义，

</CollapsibleContent>
