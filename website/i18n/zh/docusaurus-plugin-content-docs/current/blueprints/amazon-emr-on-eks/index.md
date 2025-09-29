---
sidebar_position: 1
sidebar_label: 介绍
---

# Amazon EMR on EKS
Amazon EMR on EKS 使您能够在 Amazon Elastic Kubernetes Service (EKS) 集群上按需提交 Apache Spark 作业。使用 EMR on EKS，您可以将分析工作负载与其他基于 Kubernetes 的应用程序整合在同一个 Amazon EKS 集群上，以提高资源利用率并简化基础设施管理。

## EMR on EKS 的优势

### 简化管理
您可以在 EKS 上获得与今天在 EC2 上相同的 Apache Spark EMR 优势。这包括完全托管的 Apache Spark 2.4 和 3.0 版本、自动配置、扩展、性能优化运行时，以及用于编写作业的 EMR Studio 和用于调试的 Apache Spark UI 等工具。

### 降低成本
使用 EMR on EKS，您的计算资源可以在 Apache Spark 应用程序和其他 Kubernetes 应用程序之间共享。资源按需分配和移除，以消除资源的过度配置或利用不足，使您能够降低成本，因为您只需为使用的资源付费。

### 优化性能
通过在 EKS 上运行分析应用程序，您可以重用共享 Kubernetes 集群中的现有 EC2 实例，避免为分析专门创建新 EC2 实例集群的启动时间。与 EKS 上的标准 Apache Spark 相比，使用 EMR on EKS 运行性能优化的 Spark 还可以获得 [3 倍更快的性能](https://aws.amazon.com/blogs/big-data/amazon-emr-on-amazon-eks-provides-up-to-61-lower-costs-and-up-to-68-performance-improvement-for-spark-workloads/)。

## 使用 Terraform 的 EMR on EKS 部署模式

以下 Terraform 模板可用于部署。

- [带有 Karpenter 的 EMR on EKS](./emr-eks-karpenter.md): **:point_left::skin-tone-3: 从这里开始** 如果您是 EMR on EKS 的新手。此模板部署 EMR on EKS 集群并使用 [Karpenter](https://karpenter.sh/) 来扩展 Spark 作业。
- [带有 Spark Operator 的 EMR on EKS](./emr-eks-spark-operator.md): 此模板部署带有 Spark Operator 的 EMR on EKS 集群来管理 Spark 作业
