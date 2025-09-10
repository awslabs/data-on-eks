---
sidebar_position: 7
sidebar_label: Superset on EKS
---
# Superset on EKS

## 介绍
[Apache Superset](https://superset.apache.org/) 是一个流行的开源数据探索和可视化平台。Superset 为数据科学家、分析师和业务用户提供丰富的数据可视化和简单的即席查询和分析功能。

这个[蓝图](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/superset-on-eks)在 EKS 集群上部署 Superset，使用 Postgres 作为后端数据库，使用 Amazon Elastic Block Store (Amazon EBS) 进行持久存储。

## AWS 上的 Superset

在 AWS 上，Superset 可以在 EKS 集群上运行。通过使用 EKS，您可以利用 Kubernetes 进行 Superset 服务的部署、扩展和管理。其他 AWS 服务如 VPC、IAM 和 EBS 提供网络、安全和存储功能。

使用的关键 AWS 服务：

- Amazon EKS 作为托管 Kubernetes 集群来运行 Superset Pod 和服务。
- Amazon EBS 为 Superset 持久存储提供可扩展的块存储。
- Amazon ECR 存储 Superset 和依赖项的 Docker 容器镜像

## 部署解决方案

蓝图执行以下操作在 EKS 上部署 Superset：

- 创建具有公有和私有子网的新 VPC
- 配置 EKS 集群控制平面和托管工作节点
- 创建 Amazon EBS 文件系统和访问点
- 构建 Docker 镜像并推送到 Amazon ECR
- 通过 Helm 图表在 EKS 上安装 Superset 和服务
- 通过负载均衡器公开 Superset UI

启用 Ingress，AWS LoadBalancer Controller 将配置 ALB 以公开 Superset 前端 UI。

:::info
您可以通过更改 `variables.tf` 中的值来自定义蓝图，以部署到不同的区域（默认为 `us-west-1`），使用不同的集群名称、子网/可用区数量，或禁用 fluentbit 等附加组件
:::

### 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [Helm](https://helm.sh)

### 部署
