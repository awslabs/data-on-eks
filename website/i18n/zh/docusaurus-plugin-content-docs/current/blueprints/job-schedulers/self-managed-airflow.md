---
sidebar_position: 3
sidebar_label: Airflow on EKS
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

import CodeBlock from '@theme/CodeBlock';

# 在 Amazon EKS 上自管理 Apache Airflow 部署

## 介绍

此模式在 EKS 上部署自管理的 [Apache Airflow](https://airflow.apache.org/docs/apache-airflow/stable/) 部署。此蓝图在 Amazon EKS 托管节点组上部署 Airflow，并利用 Karpenter 运行工作负载。

**架构**

![airflow-eks-architecture](../../../../../../docs/blueprints/job-schedulers/img/airflow-eks-architecture.png)

此模式使用固定的默认值来保持部署体验简单，但也保持灵活性，以便您可以在部署期间选择必要的附加组件。我们建议保持默认值，只有在有可行的替代选项可供替换时才进行自定义。

在基础设施方面，以下是此模式创建的资源：

- 具有公共端点的 EKS 集群控制平面（推荐用于演示/概念验证环境）
- 一个托管节点组
  - 核心节点组，包含跨多个可用区的 3 个实例，用于运行 Apache Airflow 和其他系统关键 Pod。例如，Cluster Autoscaler、CoreDNS、可观察性、日志记录等。

- Apache Airflow 核心组件（使用 airflow-core.tf）：
  - 用于 Airflow 元数据库的 Amazon RDS PostgreSQL 实例和安全组。
  - Airflow 命名空间
  - Kubernetes 服务账户和 AWS IAM 角色用于服务账户（IRSA），适用于 Airflow Webserver、Airflow Scheduler 和 Airflow Worker。
  - Amazon Elastic File System (EFS)、EFS 挂载、用于 EFS 的 Kubernetes 存储类，以及用于为 Airflow Pod 挂载 Airflow DAG 的 Kubernetes 持久卷声明。
  - 用于 Airflow 日志的 Amazon S3 日志存储桶

AWS for FluentBit 用于日志记录，Prometheus、Amazon Managed Prometheus 和开源 Grafana 的组合用于可观察性。您可以在下面看到可用附加组件的完整列表。

:::tip
我们建议在专用的 EKS 托管节点组（如此模式提供的 `core-node-group`）上运行所有默认系统附加组件。
:::

:::danger
我们不建议删除关键附加组件（`Amazon VPC CNI`、`CoreDNS`、`Kube-proxy`）。
:::

| 附加组件 | 默认启用？ | 好处 | 链接 |
| :---  | :----: | :---- | :---- |
| Amazon VPC CNI | 是 | VPC CNI 作为 [EKS 附加组件](https://docs.aws.amazon.com/eks/latest/userguide/eks-networking-add-ons.html)可用，负责为您的 spark 应用程序 Pod 创建 ENI 和 IPv4 或 IPv6 地址 | [VPC CNI 文档](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html) |
| CoreDNS | 是 | CoreDNS 作为 [EKS 附加组件](https://docs.aws.amazon.com/eks/latest/userguide/eks-networking-add-ons.html)可用，负责解析 spark 应用程序和 Kubernetes 集群的 DNS 查询 | [EKS CoreDNS 文档](https://docs.aws.amazon.com/eks/latest/userguide/managing-coredns.html) |
| Kube-proxy | 是 | Kube-proxy 作为 [EKS 附加组件](https://docs.aws.amazon.com/eks/latest/userguide/eks-networking-add-ons.html)可用，它维护节点上的网络规则并启用到 spark 应用程序 Pod 的网络通信 | [EKS kube-proxy 文档](https://docs.aws.amazon.com/eks/latest/userguide/managing-kube-proxy.html) |
| Amazon EBS CSI 驱动程序 | 是 | EBS CSI 驱动程序作为 [EKS 附加组件](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)可用，它允许 EKS 集群管理 EBS 卷的生命周期 | [EBS CSI 驱动程序文档](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)
| Amazon EFS CSI 驱动程序 | 是 | Amazon EFS 容器存储接口 (CSI) 驱动程序提供 CSI 接口，允许在 AWS 上运行的 Kubernetes 集群管理 Amazon EFS 文件系统的生命周期。 | [EFS CSI 驱动程序文档](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html)
