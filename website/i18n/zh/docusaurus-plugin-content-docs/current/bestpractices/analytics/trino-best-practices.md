---
sidebar_position: 2
sidebar_label: Trino on EKS 最佳实践
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

# Trino on EKS 最佳实践
在 [Amazon Elastic Kubernetes Service](https://aws.amazon.com/eks/) (EKS) 上部署 [Trino](https://trino.io/) 提供了具有云原生可扩展性的分布式查询处理。组织可以通过选择与其工作负载要求匹配的特定计算实例和存储解决方案来优化成本，同时使用 [Karpenter](https://karpenter.sh/) 将 Trino 的强大功能与 EKS 的可扩展性和灵活性相结合。

本指南为在 EKS 上部署 Trino 提供了规范性指导。它专注于通过最佳配置、有效的资源管理和成本节约策略实现高可扩展性和低成本。我们涵盖了流行文件格式（如 Hive 和 Iceberg）的详细配置。这些配置确保无缝的数据访问并优化性能。我们的目标是帮助您建立既高效又经济的 Trino 部署。

我们有一个[部署就绪的蓝图](https://awslabs.github.io/data-on-eks/docs/blueprints/distributed-databases/trino)用于在 EKS 上部署 Trino，它集成了这里讨论的最佳实践。

请参考这些最佳实践以获得合理性和进一步的优化/微调。

<CollapsibleContent header={<h2><span>Trino 基础知识</span></h2>}>
本节涵盖 Trino 的核心架构、功能、用例和生态系统及其参考。

### 核心架构

Trino 是一个强大的分布式 SQL 查询引擎，专为高性能分析和大数据处理而设计。一些关键组件包括

- 分布式协调器-工作器模型
- 内存处理架构
- MPP（大规模并行处理）执行
- 动态查询优化引擎
- 更多详细信息可以在[这里](https://trino.io/docs/current/overview/concepts.html#architecture)找到

### 关键功能

Trino 提供了几个增强数据处理能力的功能。

- 查询联邦
- 跨多个数据源的同时查询
- 支持异构数据环境
- 实时数据处理能力
- 多样化数据源的统一 SQL 接口

### 连接器生态系统

Trino 通过使用适当的连接器配置目录并通过标准 SQL 客户端连接，实现对多样化数据源的 SQL 查询。

- 50+ [生产就绪连接器](https://trino.io/ecosystem/data-source)包括：
  - 云存储（AWS S3）
  - 关系数据库（PostgreSQL、MySQL、SQL Server）
  - NoSQL 存储（MongoDB、Cassandra）
  - 数据湖（Apache Hive、Apache Iceberg、Delta Lake）
  - 流处理平台（Apache Kafka）

</CollapsibleContent>
