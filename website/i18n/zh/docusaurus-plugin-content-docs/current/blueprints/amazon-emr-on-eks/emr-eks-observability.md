---
sidebar_position: 5
sidebar_label: EMR on EKS 可观察性
---

# EMR on EKS 可观察性

## [使用 Amazon Managed Prometheus 和 Amazon Managed Grafana 监控 Amazon EMR on EKS](https://aws.amazon.com/blogs/mt/monitoring-amazon-emr-on-eks-with-amazon-managed-prometheus-and-amazon-managed-grafana/)

在这篇文章中，我们将学习通过利用 Amazon Managed Service for Prometheus 收集和存储 Spark 应用程序生成的指标，为 EMR on EKS Spark 工作负载构建端到端的可观察性。然后我们将使用 Amazon Managed Grafana 为监控用例构建仪表板

查看完整博客[这里](https://aws.amazon.com/blogs/mt/monitoring-amazon-emr-on-eks-with-amazon-managed-prometheus-and-amazon-managed-grafana/)

### 架构
下图说明了抓取 Spark 驱动程序和执行器指标以及写入 Amazon Managed Service for Prometheus 的解决方案架构。

![emr-eks-amp-amg](../../../../../../docs/blueprints/amazon-emr-on-eks/img/emr-eks-amp-amg.png)

### Spark 的 Grafana 仪表板
以下 Grafana 仪表板显示了带有驱动程序和执行器详细信息的 EMR on EKS Spark 作业指标。

![emr-eks-amp-amg-output](../../../../../../docs/blueprints/amazon-emr-on-eks/img/emr-eks-amp-amg-output.png)
