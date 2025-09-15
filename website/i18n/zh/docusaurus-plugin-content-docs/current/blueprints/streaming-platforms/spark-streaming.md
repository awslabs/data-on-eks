---
title: EKS 中从 Kafka 进行 Spark Streaming
sidebar_position: 6
---

:::danger
**弃用通知**

此蓝图将被弃用，并最终于 **2024年10月27日** 从此 GitHub 存储库中删除。不会修复任何错误，也不会添加新功能。弃用的决定基于对此蓝图缺乏需求和兴趣，以及难以分配资源来维护一个没有任何用户或客户积极使用的蓝图。

如果您在生产中使用此蓝图，请将自己添加到 [adopters.md](https://github.com/awslabs/data-on-eks/blob/main/ADOPTERS.md) 页面并在存储库中提出问题。这将帮助我们重新考虑并可能保留和继续维护该蓝图。否则，您可以制作本地副本或使用现有标签来访问它。
:::

此示例展示了使用 Spark Operator 创建使用 Kafka（Amazon MSK）的生产者和消费者堆栈的用法。主要思想是展示 Spark Streaming 与 Kafka 的工作，使用 Apache Iceberg 以 Parquet 格式持久化数据。

## 部署带有测试此示例所需的所有插件和基础设施的 EKS 集群

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

```bash
aws eks --region $REGION update-kubeconfig --name $CLUSTER_NAME
kubectl get nodes
```

### 配置生产者

为了部署生产者，使用从 Terraform 导出的变量更新 `examples/producer/00_deployment.yaml` 清单。

```bash
# 应用 `sed` 命令替换生产者清单中的占位符
sed -i.bak -e "s|__MY_PRODUCER_ROLE_ARN__|$PRODUCER_ROLE_ARN|g" \
           -e "s|__MY_AWS_REGION__|$REGION|g" \
           -e "s|__MY_KAFKA_BROKERS__|$MSK_BROKERS|g" \
           ../examples/producer/00_deployment.yaml

# 对删除主题清单应用 sed，这可用于删除 kafka 主题并再次启动堆栈
sed -i.bak -e "s|__MY_KAFKA_BROKERS__|$MSK_BROKERS|g" \
           ../examples/producer/01_delete_topic.yaml
```

### 配置消费者

为了部署 Spark 消费者，使用从 Terraform 导出的变量更新 `examples/consumer/manifests/01_spark_application.yaml` 清单。

```bash
# 应用 `sed` 命令替换消费者 Spark 应用程序清单中的占位符
sed -i.bak -e "s|__MY_BUCKET_NAME__|$ICEBERG_BUCKET|g" \
           -e "s|__MY_KAFKA_BROKERS_ADRESS__|$MSK_BROKERS|g" \
           ../examples/consumer/manifests/01_spark_application.yaml
```

### 部署生产者和消费者

配置生产者和消费者清单后，使用 kubectl 部署它们。

```bash
# 部署生产者
kubectl apply -f ../examples/producer/00_deployment.yaml

# 部署消费者
kubectl apply -f ../examples/consumer/manifests/
```

#### 检查生产者到 MSK

首先，让我们查看生产者日志以验证数据正在创建并流入 MSK：

```bash
kubectl logs $(kubectl get pods -l app=producer -oname) -f
```

#### 使用 Spark Operator 检查 Spark Streaming 应用程序

对于消费者，我们首先需要获取生成 `spark-submit` 命令到 Spark Operator 的 `SparkApplication`，以根据 YAML 配置创建驱动程序和执行器 Pod：

```bash
kubectl get SparkApplication -n spark-operator
```

您应该看到 `STATUS` 等于 `RUNNING`，现在让我们验证驱动程序和执行器 Pod：

```bash
kubectl get pods -n spark-operator
```

您应该看到如下输出：

```bash
NAME                                     READY   STATUS      RESTARTS   AGE
kafkatoiceberg-1e9a438f4eeedfbb-exec-1   1/1     Running     0          7m15s
kafkatoiceberg-1e9a438f4eeedfbb-exec-2   1/1     Running     0          7m14s
kafkatoiceberg-1e9a438f4eeedfbb-exec-3   1/1     Running     0          7m14s
spark-consumer-driver                    1/1     Running     0          9m
spark-operator-9448b5c6d-d2ksp           1/1     Running     0          117m
spark-operator-webhook-init-psm4x        0/1     Completed   0          117m
```

我们有 `1 个驱动程序` 和 `3 个执行器` Pod。现在，让我们检查驱动程序日志：

```bash
kubectl logs pod/spark-consumer-driver -n spark-operator
```

您应该只看到 `INFO` 日志，表明作业正在运行。

### 验证数据流

部署生产者和消费者后，通过检查消费者应用程序在 S3 存储桶中的输出来验证数据流。您可以运行 `s3_automation` 脚本来获取 S3 存储桶中数据大小的实时视图。

按照以下步骤操作：

1. **导航到 `s3_automation` 目录**：

    ```bash
    cd ../examples/s3_automation/
    ```

2. **运行 `s3_automation` 脚本**：

    ```bash
    python app.py
    ```

    此脚本将持续监控并显示 S3 存储桶的总大小，为您提供数据摄取的实时视图。您可以选择查看存储桶大小或根据需要删除特定目录。

#### 使用 `s3_automation` 脚本

`s3_automation` 脚本提供两个主要功能：

- **检查存储桶大小**：持续监控并显示 S3 存储桶的总大小。
- **删除目录**：删除 S3 存储桶中的特定目录。

以下是如何使用这些功能：

1. **检查存储桶大小**：
    - 提示时，输入 `size` 以获取存储桶的当前大小（以兆字节 (MB) 为单位）。

2. **删除目录**：
    - 提示时，输入 `delete`，然后提供您希望删除的目录前缀（例如，`myfolder/`）。

## 调整生产者和消费者以获得更好的性能

部署生产者和消费者后，您可以通过调整生产者的副本数量和 Spark 应用程序的执行器配置来进一步优化数据摄取和处理。以下是一些帮助您入门的建议：

### 调整生产者副本数量

您可以增加生产者部署的副本数量以处理更高的消息生产率。默认情况下，生产者部署配置为单个副本。增加此数量允许更多生产者实例并发运行，增加整体吞吐量。

要更改副本数量，请更新 `examples/producer/00_deployment.yaml` 中的 `replicas` 字段：

```yaml
spec:
  replicas: 200  # 增加此数量以扩展生产者
```

您还可以调整环境变量来控制生产消息的速率和数量：

```yaml
env:
  - name: RATE_PER_SECOND
    value: "200000"  # 增加此值以每秒生产更多消息
  - name: NUM_OF_MESSAGES
    value: "20000000"  # 增加此值以总共生产更多消息
```

应用更新的部署：

```bash
kubectl apply -f ../examples/producer/00_deployment.yaml
```

### 调整 Spark 执行器以获得更好的摄取性能

为了高效处理增加的数据量，您可以向 Spark 应用程序添加更多执行器或增加分配给每个执行器的资源。这将允许消费者更快地处理数据并减少摄取时间。

要调整 Spark 执行器配置，请更新 `examples/consumer/manifests/01_spark_application.yaml`：

```yaml
spec:
  dynamicAllocation:
    enabled: true
    initialExecutors: 5
    minExecutors: 5
    maxExecutors: 50  # 增加此数量以允许更多执行器
  executor:
    cores: 4  # 增加 CPU 分配
    memory: "8g"  # 增加内存分配
```

应用更新的 Spark 应用程序：

```bash
kubectl apply -f ../examples/consumer/manifests/01_spark_application.yaml
```

### 验证和监控

进行这些更改后，监控日志和指标以确保系统按预期执行。您可以检查生产者日志以验证数据生产，检查消费者日志以验证数据摄取和处理。

检查生产者日志：

```bash
kubectl logs $(kubectl get pods -l app=producer -oname) -f
```

检查消费者日志：

```bash
kubectl logs pod/spark-consumer-driver -n spark-operator
```

> 可以再次使用验证数据流脚本

### 总结

通过调整生产者副本数量和调整 Spark 执行器设置，您可以优化数据管道的性能。这允许您处理更高的摄取率并更高效地处理数据，确保您的 Spark Streaming 应用程序能够跟上来自 Kafka 的增加的数据量。

随意尝试这些设置以找到适合您工作负载的最佳配置。祝您流处理愉快！

### 清理生产者和消费者资源

要仅清理生产者和消费者资源，请使用以下命令：

```bash
# 清理生产者资源
kubectl delete -f ../examples/producer/00_deployment.yaml

# 清理消费者资源
kubectl delete -f ../examples/consumer/manifests/
```

### 从 `.bak` 恢复 `.yaml` 文件

如果您需要将 `.yaml` 文件重置为带有占位符的原始状态，请将 `.bak` 文件移回 `.yaml`。

```bash
# 恢复生产者清单
mv ../examples/producer/00_deployment.yaml.bak ../examples/producer/00_deployment.yaml

# 恢复消费者 Spark 应用程序清单
mv ../examples/consumer/manifests/01_spark_application.yaml.bak ../examples/consumer/manifests/01_spark_application.yaml
```

### 销毁 EKS 集群和资源

要清理整个 EKS 集群和相关资源：

```bash
cd data-on-eks/streaming/spark-streaming/terraform/
terraform destroy
```
