---
title: Kafka on EKS
sidebar_position: 4
---
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

# Apache Kafka
[Apache Kafka](https://kafka.apache.org/) 是一个开源分布式事件流平台，被数千家公司用于高性能数据管道、流分析、数据集成和关键任务应用程序。此蓝图使用 **KRaft (Kafka Raft) 模式**实现 Kafka，这是一个重要的架构改进，消除了对 Zookeeper 的需求。

## 为什么以及什么是 KRaft？
KRaft 模式简化了 Kafka 部署，增强了可扩展性，并提高了整体系统性能。通过使用内置的共识协议，KRaft 降低了操作复杂性，可能加快代理启动时间，并允许更好地处理元数据操作。这种架构转变使 Kafka 能够更高效地管理更大的集群，使其成为希望简化事件流基础设施并为未来可扩展性需求做准备的组织的有吸引力的选择。

## 用于 Apache Kafka 的 Strimzi
[Strimzi](https://strimzi.io/) 提供了一种在 Kubernetes 上以各种部署配置运行 Apache Kafka 集群的方法。Strimzi 结合了安全性和简单配置，使用 kubectl 和/或基于操作器模式的 GitOps 在 Kubernetes 上部署和管理 Kafka。

从版本 `0.32.0` 开始，Strimzi 提供了使用 KRaft 部署 Kafka 集群的完全支持，使组织更容易利用这种新架构。通过使用 Strimzi，您可以在 Kubernetes 上无缝部署和管理 KRaft 模式的 Kafka 集群，利用其自定义资源定义 (CRD) 和操作器来处理配置和生命周期管理的复杂性。

## 架构

:::info

架构图正在制作中

:::

<CollapsibleContent header={<h2><span>托管替代方案</span></h2>}>

### Amazon Managed Streaming for Apache Kafka (MSK)
[Amazon Managed Streaming for Apache Kafka (Amazon MSK)](https://aws.amazon.com/msk/) 是一个完全托管的服务，使您能够构建和运行使用 Apache Kafka 处理流数据的应用程序。Amazon MSK 提供控制平面操作，例如创建、更新和删除集群的操作。它让您使用 Apache Kafka 数据平面操作，例如生产和消费数据的操作。它运行开源版本的 Apache Kafka。这意味着支持来自合作伙伴和 Apache Kafka 社区的现有应用程序、工具和插件。您可以使用 Amazon MSK 创建使用[支持的 Apache Kafka 版本](https://docs.aws.amazon.com/msk/latest/developerguide/supported-kafka-versions.html)下列出的任何 Apache Kafka 版本的集群。Amazon MSK 提供基于集群或无服务器的部署类型。

### Amazon Kinesis Data Streams (KDS)
[Amazon Kinesis Data Streams (KDS)](https://aws.amazon.com/kinesis/data-streams/) 允许用户实时收集和处理大量数据记录流。您可以创建数据处理应用程序，称为 Kinesis Data Streams 应用程序。典型的 Kinesis Data Streams 应用程序从数据流中读取数据作为数据记录。您可以将处理后的记录发送到仪表板，使用它们生成警报，动态更改定价和广告策略，或将数据发送到各种其他 AWS 服务。Kinesis Data Streams 支持您选择的流处理框架，包括 Kinesis Client Library (KCL)、Apache Flink 和 Apache Spark Streaming。它是无服务器的，并自动扩展。

</CollapsibleContent>

<CollapsibleContent header={<h2><span>自管理 Kafka 时的存储考虑</span></h2>}>

Kafka 集群最常见的资源瓶颈是网络吞吐量、存储吞吐量，以及使用网络附加存储（如 [Amazon Elastic Block Store (EBS)](https://aws.amazon.com/ebs/)）的代理与存储后端之间的网络吞吐量。

### 使用 EBS 作为持久存储后端的优势
1. **提高灵活性和更快恢复：** 容错通常通过集群内的代理（服务器）复制和/或维护跨可用区或区域副本来实现。由于 EBS 卷的生命周期独立于 Kafka 代理，如果代理失败需要更换，附加到失败代理的 EBS 卷可以重新附加到替换代理。替换代理的大部分复制数据已经在 EBS 卷中可用，不需要通过网络从另一个代理复制。这避免了使替换代理跟上当前操作所需的大部分复制流量。

2. **即时扩展：** EBS 卷的特性可以在使用时修改。代理存储可以随时间自动扩展，而不是为峰值配置存储或添加额外的代理。

3. **针对频繁访问的吞吐量密集型工作负载进行优化：** 诸如 st1 之类的卷类型可能是一个很好的选择，因为这些卷以相对较低的成本提供，支持大的 1 MiB I/O 块大小，最大 IOPS 为 500/卷，并包括突发到每 TB 250 MB/s 的能力，基线吞吐量为每 TB 40 MB/s，

</CollapsibleContent>
