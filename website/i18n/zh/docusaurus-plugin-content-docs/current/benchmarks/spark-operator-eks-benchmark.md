---
sidebar_position: 3
sidebar_label: Kubeflow Spark Operator 基准测试
---

# Kubeflow Spark Operator 基准测试 🚀
本文档作为在 Amazon EKS 上对 Kubeflow Spark Operator 进行规模测试的综合指南。主要目标是通过提交数千个作业并分析其在压力下的行为，评估 Spark Operator 在重负载下的性能、可扩展性和稳定性。

本指南提供了分步方法：

- **配置 Spark Operator** 进行大规模作业提交的步骤。
- 性能优化的**基础设施设置**修改。
- 使用 **Locust** 的负载测试执行详细信息。
- 用于监控 Spark Operator 指标和 Kubernetes 指标的 **Grafana 仪表板**

### ✨ 为什么我们需要基准测试
基准测试是评估 Spark Operator 在处理大规模作业提交时的效率和可靠性的关键步骤。这些测试提供了有价值的见解：

- **识别性能瓶颈：** 确定系统在重负载下遇到困难的区域。
- **确保优化的资源利用率：** 确保 CPU、内存和其他资源得到有效利用。
- **评估重负载下的系统稳定性：** 测试系统在极端条件下维持性能和可靠性的能力。

通过进行这些测试，您可以确保 Spark Operator 能够有效处理现实世界的高需求场景。

### 先决条件

- 在运行基准测试之前，请确保您已按照[此处](https://awslabs.github.io/data-on-eks/docs/blueprints/data-analytics/spark-operator-yunikorn#deploy)的说明部署了 **Spark Operator** EKS 集群。
- 访问必要的 AWS 资源和修改 EKS 配置的权限。
- 熟悉 **Terraform**、**Kubernetes** 和用于负载测试的 **Locust**。

### 集群更新

为了准备集群进行基准测试，应用以下修改：

**步骤 1：更新 Spark Operator Helm 配置**

在文件 [analytics/terraform/spark-k8s-operator/addons.tf](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/addons.tf) 中取消注释指定的 Spark Operator Helm 值（从 `-- Start` 到 `-- End` 部分）。然后，运行 terraform apply 以应用更改。

这些更新确保：
- Spark Operator 和 webhook Pod 使用 Karpenter 部署在专用的 `c5.9xlarge` 实例上。
- 实例提供 `36 vCPU` 来处理 `6000` 个应用程序提交。
- 为控制器 Pod 和 Webhook Pod 分配高 CPU 和内存资源。

以下是更新的配置：

```yaml
enable_spark_operator = true
  spark_operator_helm_config = {
    version = "2.1.0"
    timeout = "120"
