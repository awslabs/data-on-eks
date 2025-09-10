---
title: Flink Operator on EKS
sidebar_position: 3
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

:::info
请注意，我们正在为此蓝图添加更多功能，如带有多个连接器的 Flink 示例、WebUI 的 Ingress、Grafana 仪表板等。
:::

## Apache Flink 介绍
[Apache Flink](https://flink.apache.org/) 是一个开源的统一流处理和批处理框架，专为处理大量数据而设计。它提供快速、可靠和可扩展的数据处理，具有容错和精确一次语义。

Flink 的一些关键功能包括：
- **分布式处理**：Flink 设计用于以分布式方式处理大量数据，使其具有水平可扩展性和容错性。
- **流处理和批处理**：Flink 为流处理和批处理提供 API。这意味着您可以在数据生成时实时处理数据，或批量处理数据。
- **容错**：Flink 具有处理节点故障、网络分区和其他类型故障的内置机制。
- **精确一次语义**：Flink 支持精确一次处理，确保每条记录都被精确处理一次，即使在出现故障的情况下。
- **低延迟**：Flink 的流引擎针对低延迟处理进行了优化，使其适用于需要实时数据处理的用例。
- **可扩展性**：Flink 提供丰富的 API 和库集合，使其易于扩展和自定义以适应您的特定用例。

## 架构

Flink 架构与 EKS 的高级设计。

![Flink Design UI](../../../../../../docs/blueprints/streaming-platforms/img/flink-design.png)

## Flink Kubernetes Operator
[Flink Kubernetes Operator](https://nightlies.apache.org/flink/flink-kubernetes-operator-docs-main/) 是在 Kubernetes 上管理 Flink 集群的强大工具。Flink Kubernetes Operator（操作器）充当控制平面来管理 Apache Flink 应用程序的完整部署生命周期。操作器可以使用 Helm 安装在 Kubernetes 集群上。Flink 操作器的核心职责是管理 Flink 应用程序的完整生产生命周期。

1. 运行、暂停和删除应用程序
2. 有状态和无状态应用程序升级
3. 触发和管理保存点
4. 处理错误，回滚损坏的升级

Flink Operator 定义了两种类型的自定义资源 (CR)，它们是 Kubernetes API 的扩展。

<Tabs>
<TabItem value="FlinkDeployment" label="FlinkDeployment">

**FlinkDeployment**
- FlinkDeployment CR 定义 **Flink 应用程序** 和 **会话集群** 部署。
- 应用程序部署在应用程序模式下的专用 Flink 集群上管理单个作业部署。
- 会话集群允许您在现有会话集群上运行多个 Flink 作业。

    <details>
    <summary>应用程序模式下的 FlinkDeployment，点击切换内容！</summary>
    </details>

</TabItem>
</Tabs>
