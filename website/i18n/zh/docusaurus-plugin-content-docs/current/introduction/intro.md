---
sidebar_position: 1
sidebar_label: 介绍
---

# 介绍
Data on Amazon EKS(DoEKS) - 用于在 [Amazon EKS](https://aws.amazon.com/eks/) 上构建 [aws](https://aws.amazon.com/) 托管和自管理可扩展数据平台的工具。使用 DoEKS，您可以访问：

1. 使用 [Terraform](https://www.terraform.io/) 和 [AWS CDK](https://aws.amazon.com/cdk/) 等的强大部署基础设施即代码 (IaC) 模板
2. 在 Amazon EKS 上部署数据解决方案的最佳实践
3. 详细的性能基准报告
4. [Apache Spark](https://spark.apache.org/)/[ML](https://aws.amazon.com/machine-learning/) 作业和各种其他框架的实践示例
5. 深入的参考架构和数据博客，让您保持领先

# 架构
该图显示了在 DoEKS 中涵盖的在 Kubernetes 上运行的开源数据工具、k8s 操作器和框架。AWS 数据分析托管服务与 Data on EKS OSS 工具的集成。

![Data on EKS.png](../../../../../docs/introduction/doeks.png)

# 主要功能

🚀 [EMR on EKS](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/emr-eks.html)

🚀 [EKS 上的开源 Spark](https://spark.apache.org/docs/latest/running-on-kubernetes.html)

🚀 自定义 Kubernetes 调度器（例如，[Apache YuniKorn](https://yunikorn.apache.org/)、[Volcano](https://volcano.sh/en/)）

🚀 作业调度器（例如，[Apache Airflow](https://airflow.apache.org/)、[Argo Workflows](https://argoproj.github.io/argo-workflows/)）

🚀 Kubernetes 上的 AI/ML（例如，[KubeFlow](https://www.kubeflow.org/)、[MLFlow](https://mlflow.org/)、[Tensorflow](https://www.tensorflow.org/)、[PyTorch](https://pytorch.org/) 等）

🚀 分布式数据库（例如，[Cassandra](https://cassandra.apache.org/_/blog/Cassandra-on-Kubernetes-A-Beginners-Guide.html)、[CockroachDB](https://github.com/cockroachdb/cockroach-operator)、[MongoDB](https://github.com/mongodb/mongodb-kubernetes-operator) 等）

🚀 流处理平台（例如，[Apache Kafka](https://github.com/apache/kafka)、[Apache Flink](https://github.com/apache/flink)、Apache Beam 等）

# 入门

查看每个部分的文档以部署基础设施并运行示例 Spark/ML 作业。
