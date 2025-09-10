---
sidebar_position: 3
sidebar_label: Trino on EKS
---

# 在 EKS 上部署 Trino

## 介绍

[Trino](https://trino.io/) 是一个开源、快速、分布式查询引擎，专为在多种数据源上运行大数据分析的 SQL 查询而设计，包括 Amazon S3、关系数据库、分布式数据存储和数据仓库。

当 Trino 执行查询时，它通过将执行分解为阶段层次结构来实现，这些阶段作为分布在 Trino 工作节点网络上的一系列任务来实现。Trino 集群由一个协调器和许多用于并行处理的工作节点组成，可以作为 Kubernetes Pod 部署在 EKS 集群上。协调器和工作节点协作访问连接的数据源，模式和引用存储在目录中。要访问数据源，您可以使用 Trino 提供的许多[连接器](https://trino.io/docs/current/connector.html)之一来适配 Trino。示例包括 Hive、Iceberg 和 Kafka。有关 Trino 项目的更多详细信息可以在此[链接](https://trino.io)中找到

## 蓝图解决方案

此蓝图将在 EKS 集群（Kubernetes 版本 1.29）上部署 Trino，节点使用 Karpenter（v0.34.0）配置。为了优化成本和性能，Karpenter 将为 Trino 协调器配置按需节点，为 Trino 工作节点配置 EC2 Spot 实例。借助 Trino 的多架构容器镜像，Karpenter [NodePool](https://karpenter.sh/v0.34/concepts/nodepools/) 将允许配置来自不同 CPU 架构的 EC2 实例节点，包括基于 AWS Graviton 的实例。Trino 使用[官方 Helm 图表](https://trinodb.github.io/charts/charts/trino/)部署，为用户提供自定义值以利用 Hive 和 Iceberg 连接器。示例将使用 AWS 上的 Glue 和 Iceberg 表作为后端数据源，使用 S3 作为存储。

## 部署解决方案

让我们来看看部署步骤。

### 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [Trino CLI 客户端](https://trino.io/docs/current/client/cli.html)
<details>
<summary> 切换查看 Trino CLI 安装步骤</summary>
```bash
wget https://repo1.maven.org/maven2/io/trino/trino-cli/427/trino-cli-427-executable.jar
mv trino-cli-427-executable.jar trino
chmod +x trino
```
</details>

### 使用 Trino 部署 EKS 集群

首先，克隆存储库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到 `distributed-databases/trino` 并运行 `install.sh` 脚本。在提示时输入您要配置资源的 AWS 区域（例如，`us-west-2`）。

```bash
cd data-on-eks/distributed-databases/trino
