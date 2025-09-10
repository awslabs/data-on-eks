---
title: AWS Batch on EKS
sidebar_position: 5
---

# AWS Batch on EKS
AWS Batch 是一个完全托管的 AWS 原生批处理计算服务，它在 AWS 托管容器编排服务（如 Amazon Elastic Kubernetes Service (EKS)）之上规划、调度和运行您的容器化批处理工作负载（机器学习、仿真和分析）。

AWS Batch 为高性能计算工作负载添加了必要的操作语义和资源，使它们能够在您现有的 EKS 集群上高效且经济地运行。

具体来说，Batch 提供了一个始终在线的作业队列来接受工作请求。您创建一个 AWS Batch 作业定义，这是作业的模板，然后将它们提交到 Batch 作业队列。然后 Batch 负责为您的 EKS 集群在 Batch 特定的命名空间中配置节点，并在这些实例上放置 Pod 来运行您的工作负载。

此示例提供了一个蓝图，用于建立使用 AWS Batch 在 Amazon EKS 集群上运行工作负载的完整环境，包括：
* 所有必要的支持基础设施，如 VPC、IAM 角色、安全组等。
* 用于您的工作负载的 EKS 集群
* 用于在 EC2 按需和 Spot 实例上运行作业的 AWS Batch 资源。

您可以在[这里](https://github.com/awslabs/data-on-eks/tree/main/schedulers/terraform/aws-batch-eks)找到蓝图。

## 考虑因素

AWS Batch 适用于离线分析和数据处理任务，如重新格式化媒体、训练 ML 模型、批量推理或其他不与用户交互的计算和数据密集型任务。

特别是，Batch *针对运行时间超过三分钟的作业进行了调优*。如果您的作业很短（少于一分钟），请考虑将更多工作打包到单个 AWS Batch 作业请求中，以增加作业的总运行时间。

## 先决条件

确保您已在本地安装以下工具：

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

## 部署

**要配置此示例：**

1. 将存储库克隆到您的本地计算机。
   ```bash
   git clone https://github.com/awslabs/data-on-eks.git
   cd data-on-eks/schedulers/terraform/aws-batch
   ```
2. 运行安装脚本。
   ```bash
   /bin/sh install.sh
   ```
   在命令提示符处输入区域以继续。

脚本将运行 Terraform 来建立所有资源。完成后，您将看到如下 terraform 输出。
