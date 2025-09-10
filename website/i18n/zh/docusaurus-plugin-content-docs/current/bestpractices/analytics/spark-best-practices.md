---
sidebar_position: 3
sidebar_label: Spark on EKS 最佳实践
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

# Spark on EKS 最佳实践

本页面旨在为在 Amazon Elastic Kubernetes Service (EKS) 上部署、管理和优化 Apache Spark 工作负载提供全面的最佳实践和指导。这有助于组织在 Amazon EKS 的容器化环境中成功运行和扩展 Spark 应用程序。

要在 EKS 上部署 Spark，您可以利用[蓝图](https://awslabs.github.io/data-on-eks/docs/blueprints/data-analytics/spark-operator-yunikorn)，它已经集成了大部分最佳实践。您可以进一步自定义此蓝图，调整配置以匹配您的特定应用程序要求和环境约束，如本指南中所述。

## EKS 网络
### VPC 和子网大小调整
#### VPC IP 地址耗尽

随着 EKS 集群扩展更多 Spark 工作负载，集群管理的 Pod 数量可以轻松增长到数千个，每个都消耗一个 IP 地址。这带来了挑战，因为 VPC 内的 IP 地址是有限的，重新创建更大的 VPC 或扩展当前 VPC 的 CIDR 块并不总是可行的。

工作节点和 Pod 都消耗 IP 地址。默认情况下，VPC CNI 有 `WARM_ENI_TARGET=1`，这意味着 `ipamd` 应该在 `ipamd` 预热池中保持"一个完整 ENI"的可用 IP，用于 Pod IP 分配。

#### IP 地址耗尽的补救措施
虽然存在 VPC 的 IP 耗尽补救方法，但它们会引入额外的操作复杂性并有重要的影响需要考虑。因此，对于新的 EKS 集群，建议为您将用于 Pod 网络的子网过度配置以适应增长。

为了解决 IP 地址耗尽问题，考虑向您的 VPC 添加辅助 CIDR 块并从这些额外的地址范围创建新子网，然后在这些扩展的子网中部署工作节点。

如果添加更多子网不是选项，那么您将必须通过调整 CNI 配置变量来优化 IP 地址分配。请参考[配置 MINIMUM_IP_TARGET](/docs/bestpractices/networking#avoid-using-warm_ip_target-in-large-clusters-or-cluster-with-a-lot-of-churn)。

### CoreDNS 建议
#### DNS 查找限制
在 Kubernetes 上运行的 Spark 应用程序在执行器与外部服务通信时会产生大量 DNS 查找。

这是因为 Kubernetes 的 DNS 解析模型要求每个 Pod 为每个新连接查询集群的 DNS 服务（kube-dns 或 CoreDNS），在任务执行期间，Spark 执行器经常创建新连接来与外部服务通信。默认情况下，Kubernetes 不在 Pod 级别缓存 DNS 结果，这意味着每个执行器 Pod 必须执行新的 DNS 查找，即使是之前解析过的主机名。

这种行为在 Spark 应用程序中被放大，因为它们的分布式特性，多个执行器 Pod 同时尝试解析相同的外部服务端点。这发生在数据摄取、处理以及连接到外部数据库或洗牌服务时。

当 DNS 流量超过每秒 1024 个数据包对于一个 CoreDNS 副本时，DNS 请求将被限制，导致 `unknownHostException` 错误。

#### 补救措施
建议随着工作负载的扩展来扩展 CoreDNS。请参考[扩展 CoreDNS](/docs/bestpractices/networking#scaling-coredns) 了解实现选择的更多详细信息。

还建议持续监控 CoreDNS 指标。请参考 [EKS 网络最佳实践](https://docs.aws.amazon.com/eks/latest/best-practices/monitoring_eks_workloads_for_network_performance_issues.html#_monitoring_coredns_traffic_for_dns_throttling_issues) 获取详细信息。

### 减少跨可用区流量

#### 跨可用区成本
在洗牌阶段，Spark 执行器可能需要在它们之间交换数据。如果 Pod 分布在多个可用区 (AZ) 中，这种洗牌操作可能会变得非常昂贵，特别是在网络 I/O 方面，这将作为跨可用区流量成本收费。

#### 补救措施
对于 Spark 工作负载，建议将执行器 Pod 和工作节点放置在同一个可用区中。将工作负载放置在同一个可用区中有两个主要目的：
* 减少跨可用区流量成本
* 减少执行器/Pod 之间的网络延迟

请参考[跨可用区网络优化](/docs/bestpractices/networking#inter-az-network-optimization)以使 Pod 在同一个可用区中共同定位。

## Karpenter 建议

[Karpenter](https://karpenter.sh/docs/) 通过提供与 Spark 动态资源扩展需求相匹配的快速节点配置能力来增强 EKS 上的 Spark 部署。这种自动扩展解决方案通过根据需要引入合适大小的节点来提高资源利用率和成本效率。这还允许 Spark 作业无缝扩展，无需预配置的节点组或手动干预，从而简化操作管理。

以下是在运行 Spark 工作负载时扩展计算节点的 Karpenter 建议。有关完整的 Karpenter 配置详细信息，请参考 [Karpenter 文档](https://karpenter.sh/docs/)。

考虑为驱动程序和执行器 Pod 创建单独的 NodePool。

### 驱动程序 NodePool
Spark 驱动程序是单个 Pod，管理 Spark 应用程序的整个生命周期。终止 Spark 驱动程序 Pod 实际上意味着终止整个 Spark 作业。
* 配置驱动程序 NodePool 始终仅使用 `on-demand` 节点。当 Spark 驱动程序 Pod 在 Spot 实例上运行时，由于 Spot 实例回收，它们容易受到意外终止的影响，导致计算损失和中断处理，需要手动干预重新启动。
* 在驱动程序 NodePool 上禁用[`consolidation`](https://karpenter.sh/docs/concepts/disruption/#consolidation)。
* 使用 `node selectors` 或 `taints/tolerations` 将驱动程序 Pod 放置在此指定的驱动程序 NodePool 上。

### 执行器 NodePool
#### 配置 Spot 实例
在没有 [Amazon EC2 预留实例](https://aws.amazon.com/ec2/pricing/reserved-instances/) 或 [Savings Plans](https://aws.amazon.com/savingsplans/) 的情况下，考虑为执行器使用 [Amazon EC2 Spot 实例](https://aws.amazon.com/ec2/spot/) 来降低数据平面成本。

当 Spot 实例被中断时，执行器将被终止并在可用节点上重新调度。有关中断行为和节点终止管理的详细信息，请参考 `处理中断` 部分。

#### 实例和容量类型选择

在节点池中使用多种实例类型可以访问各种 Spot 实例池，增加容量可用性并在可用实例选项中优化价格和容量。

使用 `加权 NodePool`，可以使用按优先级顺序排列的加权节点池来优化节点选择。通过为每个节点池分配不同的权重，您可以建立选择层次结构，例如：Spot（最高权重），然后是 Graviton、AMD 和 Intel（最低权重）。

#### 整合配置
虽然为 Spark 执行器 Pod 启用 `consolidation` 可以带来更好的集群资源利用率，但在作业性能方面取得平衡至关重要。频繁的整合事件可能导致 Spark 作业执行时间变慢，因为执行器被迫重新计算洗牌数据和 RDD 块。

这种影响在长时间运行的 Spark 作业中特别明显。为了缓解这种情况，仔细调整整合间隔至关重要。

启用优雅的执行器 Pod 关闭：
* `spark.executor.decommission.enabled=true`：启用执行器的优雅退役，允许它们完成当前任务并在关闭前传输其缓存数据。这在为执行器使用 Spot 实例时特别有用。

* `spark.storage.decommission.enabled=true`：启用在关闭前将缓存的 RDD 块从退役执行器迁移到其他活动执行器，防止数据丢失和重新计算的需要。

要探索在 Spark 执行器中保存中间数据计算的其他方法，请参考[存储最佳实践](#存储最佳实践)。

#### 在 Karpenter 整合/Spot 终止期间处理中断

在节点计划终止时执行受控退役，而不是突然杀死执行器。要实现这一点：

* 为 Spark 工作负载配置适当的 TerminationGracePeriod 值。
* 实现执行器感知的终止处理。
* 确保在节点退役前保存洗牌数据。

Spark 提供原生配置来控制终止行为：

**控制执行器中断**
* **配置**：
* `spark.executor.decommission.enabled`
* `spark.executor.decommission.forceKillTimeout`
这些配置在执行器可能由于 Spot 实例中断或 Karpenter 整合事件而被终止的场景中特别有用。启用时，执行器将通过停止任务接受并通知驱动程序其退役状态来优雅关闭。

**控制执行器的 BlockManager 行为**
* **配置**：
* `spark.storage.decommission.enabled`
* `spark.storage.decommission.shuffleBlocks.enabled`
* `spark.storage.decommission.rddBlocks.enabled`
* `spark.storage.decommission.fallbackStorage.path`
这些设置启用将洗牌和 RDD 块从退役执行器迁移到其他可用执行器或回退存储位置。这种方法通过减少重新计算洗牌数据或 RDD 块的需要来帮助动态环境，从而提高作业完成时间和资源效率。

## 高级调度考虑
### 默认 Kubernetes 调度器行为

默认 Kubernetes 调度器使用 `最少分配` 方法。此策略旨在将 Pod 均匀分布在集群中，这有助于维护可用性和所有节点之间的平衡资源利用率，而不是在更少的节点中打包更多 Pod。

另一方面，`最多分配` 方法旨在偏向具有最多分配资源的节点，这导致将更多 Pod 打包到已经大量分配的节点上。这种方法对 Spark 作业有利，因为它在 Pod 调度时旨在选择节点上的高利用率，导致更好的节点整合。您将必须利用启用此选项的自定义 kube-scheduler，或利用专为更高级编排而构建的自定义调度器。

### 自定义调度器

自定义调度器通过提供针对批处理和高性能计算工作负载量身定制的高级功能来增强 Kubernetes 的原生调度能力。自定义调度器通过优化装箱并提供针对特定应用程序需求的调度来增强资源分配。以下是在 Kubernetes 上运行 Spark 工作负载的流行自定义调度器。
* [Apache Yunikorn](https://yunikorn.apache.org/)
* [Volcano](https://volcano.sh/en/)

利用像 Yunikorn 这样的自定义调度器的优势。
* 分层队列系统和可配置策略，允许复杂的资源管理。
* Gang 调度，确保所有相关 Pod（如 Spark 执行器）一起启动，防止资源浪费。
* 不同租户和工作负载之间的资源公平性。

### Yunikorn 和 Karpenter 如何协同工作？

Karpenter 和 Yunikorn 通过处理 Kubernetes 中工作负载管理的不同方面来相互补充：

* **Karpenter** 专注于节点配置和扩展，根据资源需求确定何时添加或删除节点。

* **Yunikorn** 通过队列管理、资源公平性和 Gang 调度等高级功能为调度带来应用程序感知。

在典型的工作流程中，Yunikorn 首先根据应用程序感知策略和队列优先级调度 Pod。当这些 Pod 由于集群资源不足而保持挂起状态时，Karpenter 检测到这些挂起的 Pod 并配置适当的节点来容纳它们。这种集成确保了高效的 Pod 放置（Yunikorn）和最佳的集群扩展（Karpenter）。

对于 Spark 工作负载，这种组合特别有效：Yunikorn 确保执行器根据应用程序 SLA 和依赖关系进行调度，而 Karpenter 确保正确的节点类型可用以满足这些特定要求。

## 存储最佳实践
### 节点存储
默认情况下，工作节点的 EBS 根卷设置为 20GB。Spark 执行器使用本地存储来存储临时数据，如洗牌数据、中间结果和临时文件。附加到工作节点的这个默认 20GB 根卷存储在大小和性能方面都可能是限制性的。考虑以下选项来满足您的性能和存储大小要求：
* 扩展根卷容量以为中间 Spark 数据提供充足空间。您将必须根据每个执行器将处理的数据集的平均大小和 Spark 作业的复杂性来确定最佳容量。
* 配置具有更好 I/O 和延迟的高性能存储。
* 在工作节点上挂载额外的卷用于临时数据存储。
* 利用可以直接附加到执行器 Pod 的动态配置 PVC。

### 重用 PVC
此选项允许重用与 Spark 执行器关联的 PVC，即使在执行器被终止后（由于整合活动或在 Spot 实例情况下的抢占）。

这允许在 PVC 上保留中间洗牌数据和缓存数据。当 Spark 请求新的执行器 Pod 来替换被终止的 Pod 时，系统尝试重用属于被终止执行器的现有 PVC。可以通过以下配置启用此选项：

`spark.kubernetes.executor.reusePersistentVolume=true`

### 外部洗牌服务
利用像 Apache Celeborn 这样的外部洗牌服务来解耦计算和存储，允许 Spark 执行器将数据写入外部洗牌服务而不是本地磁盘。这减少了由于执行器终止或整合而导致的数据丢失和数据重新计算的风险。

这还允许更好的资源管理，特别是当启用 `Spark 动态资源分配` 时。外部洗牌服务允许 Spark 即使在动态资源分配期间删除执行器后也保留洗牌数据，防止在添加新执行器时需要重新计算洗牌数据。这使得在不需要时更有效地缩减资源。

还要考虑外部洗牌服务的性能影响。对于较小的数据集或洗牌数据量较低的应用程序，设置和管理外部洗牌服务的开销可能超过其好处。

当处理每个作业超过 500GB 到 1TB 的洗牌数据量或运行数小时到多天的长时间运行 Spark 应用程序时，建议使用外部洗牌服务。

请参考此 [Celeborn 文档](https://celeborn.apache.org/docs/latest/deploy_on_k8s/) 了解在 Kubernetes 上的部署和与 Apache Spark 的集成配置。
