---
sidebar_position: 3
title: EMR on EKS with Flink Streaming
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

## EMR on EKS Flink Kubernetes Operator
Amazon EMR 6.13.0 及更高版本支持带有 Apache Flink 的 Amazon EMR on EKS，或 ![EMR Flink Kubernetes operator](https://gallery.ecr.aws/emr-on-eks/flink-kubernetes-operator)，作为 Amazon EMR on EKS 的作业提交模型。使用带有 Apache Flink 的 Amazon EMR on EKS，您可以在自己的 Amazon EKS 集群上使用 Amazon EMR 发布运行时部署和管理 Flink 应用程序。在 Amazon EKS 集群中部署 Flink Kubernetes 操作器后，您可以直接使用操作器提交 Flink 应用程序。操作器管理 Flink 应用程序的生命周期。

1. 运行、暂停和删除应用程序
2. 有状态和无状态应用程序升级
3. 触发和管理保存点
4. 处理错误，回滚损坏的升级

除了上述功能外，EMR Flink Kubernetes 操作器还提供以下附加功能：
1. 使用 Amazon S3 中的 jar 启动 Flink 应用程序
2. 与 Amazon S3 和 Amazon CloudWatch 的监控集成以及容器日志轮转。
3. 根据观察到的指标的历史趋势自动调整 Autoscaler 配置。
4. 在扩展或故障恢复期间更快的 Flink 作业重启
5. IRSA（服务账户的 IAM 角色）原生集成
6. Pyflink 支持

Flink Operator 定义了两种类型的自定义资源 (CR)，它们是 Kubernetes API 的扩展。

<Tabs>
<TabItem value="FlinkDeployment" label="FlinkDeployment">

</TabItem>
</Tabs>
