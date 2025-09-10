---
sidebar_position: 2
sidebar_label: 数据生成
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';
import ReplaceS3BucketPlaceholders from '../../../../../../docs/benchmarks/spark-operator-benchmark/_replace_s3_bucket_placeholders.mdx';

# 为在 Amazon EKS 上运行 Spark 基准测试生成数据

以下指南提供了如何为运行 Spark 的 TPCDS 基准测试生成数据集的说明。

## 部署数据生成工具包

在这个[示例](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/spark-k8s-operator)中，您将配置使用开源 Spark Operator 运行 Spark 作业所需的以下资源。

此示例将运行 Spark K8s Operator 的 EKS 集群部署到新的 VPC 中。

- 创建新的示例 VPC、2 个私有子网、2 个公有子网，以及 RFC6598 空间（100.64.0.0/10）中用于 EKS Pod 的 2 个子网。
- 为公有子网创建互联网网关，为私有子网创建 NAT 网关
- 创建具有公共端点的 EKS 集群控制平面（仅用于演示目的），包含用于基准测试和核心服务的托管节点组，以及用于 Spark 工作负载的 Karpenter NodePool。
- 部署 Metrics server、Spark-operator、Apache Yunikorn、Karpenter、Cluster Autoscaler、Grafana、AMP 和 Prometheus server。

### 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### 部署

克隆存储库。

```bash
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks
export DOEKS_HOME=$(pwd)
```

如果 DOEKS_HOME 被取消设置，您可以始终从 data-on-eks 目录使用 `export DATA_ON_EKS=$(pwd)` 手动设置它。

导出以下环境变量以设置启用 SSD 的 `c5d12xlarge` 实例的最小和期望数量。在我们的测试中，我们根据数据集的大小将这两个值都设置为 `6`。请根据您的要求和计划运行的数据集大小调整实例数量。

```bash
export TF_VAR_spark_benchmark_ssd_min_size=6
export TF_VAR_spark_benchmark_ssd_desired_size=6
