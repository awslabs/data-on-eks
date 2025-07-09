---
sidebar_position: 2
sidebar_label: EMR on EKS可观测性
---

# EMR on EKS可观测性

## [使用Amazon Managed Prometheus和Amazon Managed Grafana监控Amazon EMR on EKS](https://aws.amazon.com/blogs/mt/monitoring-amazon-emr-on-eks-with-amazon-managed-prometheus-and-amazon-managed-grafana/)

在本文中，我们将学习通过利用Amazon Managed Service for Prometheus收集和存储Spark应用程序生成的指标，为EMR on EKS Spark工作负载构建端到端可观测性。然后，我们将使用Amazon Managed Grafana为监控用例构建仪表板

查看完整博客[这里](https://aws.amazon.com/blogs/mt/monitoring-amazon-emr-on-eks-with-amazon-managed-prometheus-and-amazon-managed-grafana/)

### 架构
下图说明了抓取Spark驱动程序和执行器指标以及写入Amazon Managed Service for Prometheus的解决方案架构。

![emr-eks-amp-amg](../../../../../../docs/blueprints/amazon-emr-on-eks/img/emr-eks-amp-amg.png)

### Spark的Grafana仪表板
以下Grafana仪表板显示了EMR on EKS Spark作业指标，包括驱动程序和执行器详情。

![emr-eks-amp-amg-output](../../../../../../docs/blueprints/amazon-emr-on-eks/img/emr-eks-amp-amg-output.png)
