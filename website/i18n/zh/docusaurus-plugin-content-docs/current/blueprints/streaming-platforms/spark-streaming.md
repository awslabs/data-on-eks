---
title: Spark Streaming from Kafka in EKS
sidebar_position: 6
---

:::danger
**弃用通知**

此蓝图将被弃用，并最终于 **2024 年 10 月 27 日** 从此 GitHub 存储库中删除。不会修复错误，也不会添加新功能。弃用的决定基于对此蓝图缺乏需求和兴趣，以及难以分配资源来维护一个没有任何用户或客户积极使用的蓝图。

如果您在生产中使用此蓝图，请将自己添加到 [adopters.md](https://github.com/awslabs/data-on-eks/blob/main/ADOPTERS.md) 页面并在存储库中提出问题。这将帮助我们重新考虑并可能保留和继续维护蓝图。否则，您可以制作本地副本或使用现有标签来访问它。
:::

此示例展示了使用 Spark Operator 创建使用 Kafka (Amazon MSK) 的生产者和消费者堆栈的用法。主要思想是展示 Spark Streaming 与 Kafka 的工作，使用 Apache Iceberg 以 Parquet 格式持久化数据。

## 部署 EKS 集群以及测试此示例所需的所有附加组件和基础设施

### 克隆存储库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

### 初始化 Terraform

导航到示例目录并运行初始化脚本 `install.sh`。

```bash
cd data-on-eks/streaming/spark-streaming/terraform/
./install.sh
```

### 导出 Terraform 输出

Terraform 脚本完成后，导出必要的变量以在 `sed` 命令中使用它们。

```bash
export CLUSTER_NAME=$(terraform output -raw cluster_name)
export PRODUCER_ROLE_ARN=$(terraform output -raw producer_iam_role_arn)
export CONSUMER_ROLE_ARN=$(terraform output -raw consumer_iam_role_arn)
export MSK_BROKERS=$(terraform output -raw bootstrap_brokers)
export REGION=$(terraform output -raw s3_bucket_region_spark_history_server)
export ICEBERG_BUCKET=$(terraform output -raw s3_bucket_id_iceberg_bucket)
```

### 更新 kubeconfig

更新 kubeconfig 以验证部署。
