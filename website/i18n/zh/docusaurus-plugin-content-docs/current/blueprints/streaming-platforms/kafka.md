---
title: Kafka on EKS
sidebar_position: 4
---
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

# Apache Kafka
[Apache Kafka](https://kafka.apache.org/) 是一个开源的分布式事件流平台，被数千家公司用于高性能数据管道、流分析、数据集成和关键任务应用程序。此蓝图使用 **KRaft（Kafka Raft）模式** 实现 Kafka，这是一个重要的架构改进，消除了对 Zookeeper 的需求。

## 为什么使用 KRaft？什么是 KRaft？
KRaft 模式简化了 Kafka 部署，增强了可扩展性，并提高了整体系统性能。通过使用内置的共识协议，KRaft 降低了操作复杂性，可能加快代理启动时间，并允许更好地处理元数据操作。这种架构转变使 Kafka 能够更高效地管理更大的集群，对于希望简化其事件流基础设施并为未来可扩展性需求做准备的组织来说，这是一个有吸引力的选择。

## 用于 Apache Kafka 的 Strimzi
[Strimzi](https://strimzi.io/) 提供了一种在 Kubernetes 上以各种部署配置运行 Apache Kafka 集群的方法。Strimzi 结合了安全性和简单配置，使用 kubectl 和/或基于 Operator 模式的 GitOps 在 Kubernetes 上部署和管理 Kafka。

从版本 `0.32.0` 开始，Strimzi 提供了使用 KRaft 部署 Kafka 集群的完全支持，使组织更容易利用这种新架构。通过使用 Strimzi，您可以在 Kubernetes 上无缝部署和管理 KRaft 模式下的 Kafka 集群，利用其自定义资源定义 (CRD) 和操作器来处理配置和生命周期管理的复杂性。

## 架构

:::info

架构图正在制作中

:::

## 托管替代方案

### Amazon Managed Streaming for Apache Kafka (MSK)
[Amazon Managed Streaming for Apache Kafka (Amazon MSK)](https://aws.amazon.com/msk/) 是一个完全托管的服务，使您能够构建和运行使用 Apache Kafka 处理流数据的应用程序。Amazon MSK 提供控制平面操作，例如创建、更新和删除集群的操作。它让您使用 Apache Kafka 数据平面操作，例如生产和消费数据的操作。它运行开源版本的 Apache Kafka。这意味着支持现有的应用程序、工具和来自合作伙伴和 Apache Kafka 社区的插件。您可以使用 Amazon MSK 创建使用[支持的 Apache Kafka 版本](https://docs.aws.amazon.com/msk/latest/developerguide/supported-kafka-versions.html)下列出的任何 Apache Kafka 版本的集群。Amazon MSK 提供基于集群或无服务器的部署类型。

### Amazon Kinesis Data Streams (KDS)
[Amazon Kinesis Data Streams (KDS)](https://aws.amazon.com/kinesis/data-streams/) 允许用户实时收集和处理大量数据记录流。您可以创建数据处理应用程序，称为 Kinesis Data Streams 应用程序。典型的 Kinesis Data Streams 应用程序从数据流中读取数据作为数据记录。您可以将处理后的记录发送到仪表板，使用它们生成警报，动态更改定价和广告策略，或将数据发送到各种其他 AWS 服务。Kinesis Data Streams 支持您选择的流处理框架，包括 Kinesis Client Library (KCL)、Apache Flink 和 Apache Spark Streaming。它是无服务器的，并自动扩展。

<CollapsibleContent header={<h2 id="storage-considerations"><span>自管理 Kafka 时的存储考虑</span></h2>}>

Kafka 集群最常见的资源瓶颈是网络吞吐量、存储吞吐量，以及使用网络附加存储（如 [Amazon Elastic Block Store (EBS)](https://aws.amazon.com/ebs/)）的代理与存储后端之间的网络吞吐量。

### 使用 EBS 作为持久存储后端的优势 {#使用-ebs-作为持久存储后端的优势}
1. **提高灵活性和更快恢复：** 容错性通常通过集群内的代理（服务器）复制和/或维护跨可用区或区域副本来实现。由于 EBS 卷的生命周期独立于 Kafka 代理，如果代理失败需要更换，附加到失败代理的 EBS 卷可以重新附加到替换代理。替换代理的大部分复制数据已经在 EBS 卷中可用，不需要通过网络从另一个代理复制。这避免了使替换代理跟上当前操作所需的大部分复制流量。
2. **即时扩展：** EBS 卷的特性可以在使用时修改。代理存储可以随时间自动扩展，而不是为峰值配置存储或添加额外的代理。
3. **针对频繁访问的吞吐量密集型工作负载进行优化：** 像 st1 这样的卷类型可能是一个很好的选择，因为这些卷以相对较低的成本提供，支持大的 1 MiB I/O 块大小，最大 IOPS 为 500/卷，并包括突发到每 TB 250 MB/s 的能力，基线吞吐量为每 TB 40 MB/s，最大吞吐量为每卷 500 MB/s。

### 在 AWS 上自管理 Kafka 时应该使用什么 EBS 卷？ {#在-aws-上自管理-kafka-时应该使用什么-ebs-卷}
* 通用 SSD 卷 **gp3** 具有平衡的价格和性能，被广泛使用，您可以**独立**配置存储（最多 16TiB）、IOPS（最多 16,000）和吞吐量（最多 1,000MiB/s）
* **st1** 是频繁访问和吞吐量密集型工作负载的低成本 HDD 选项，最多 500 IOPS 和 500 MiB/s
* 对于像 Zookeeper 这样的关键应用程序，预配置 IOPS 卷（**io2 Block Express、io2**）提供更高的持久性

### 出于性能原因使用 NVMe SSD 实例存储怎么样？
虽然 EBS 提供灵活性和易于管理，但一些高性能用例可能受益于使用本地 NVMe SSD 实例存储。这种方法可以提供显著的性能改进，但在数据持久性和操作复杂性方面存在权衡。

#### NVMe SSD 实例存储的考虑和挑战
1. **数据持久性：** 本地存储是临时的。如果实例失败或终止，该存储上的数据将丢失。这需要仔细考虑您的复制策略和灾难恢复计划，特别是如果集群很大（数百 TB 数据）。
2. **集群升级：** 升级 Kafka 或 EKS 变得更加复杂，因为您需要确保在对具有本地存储的节点进行更改之前正确迁移或复制数据。
3. **扩展复杂性：** 扩展集群可能需要数据重新平衡，与使用网络附加存储相比，这可能更耗时和资源密集。
4. **实例类型锁定：** 您的实例类型选择变得更加有限，因为您需要选择具有适当本地存储选项的实例。

#### 那么，什么时候应该考虑使用本地存储？
1. 对于每毫秒延迟都很重要的极高性能要求。
2. 当您的用例可以容忍单个节点故障时的潜在数据丢失，依靠 Kafka 的复制来保证数据持久性。

虽然本地存储可以提供性能优势，但重要的是仔细权衡这些与操作挑战，特别是在像 EKS 这样的动态环境中。对于大多数用例，我们建议从 EBS 存储开始，因为它的灵活性和更容易管理，只有在特定的高性能场景中，权衡是合理的，才考虑本地存储。

</CollapsibleContent>

<CollapsibleContent header={<h2><span>部署解决方案</span></h2>}>

在这个[示例](https://github.com/awslabs/data-on-eks/tree/main/streaming/kafka)中，您将配置以下资源以在 EKS 上运行 Kafka 集群。

此示例将带有 Kafka 的 EKS 集群部署到新的 VPC 中。

- 创建新的示例 VPC、3 个私有子网和 3 个公有子网。
- 为公有子网创建互联网网关，为私有子网创建 NAT 网关。
- 创建具有公共端点的 EKS 集群控制平面（仅用于演示目的），包含一个托管节点组。
- 部署 Metrics server、Karpenter、自管理的 ebs-csi-driver、Strimzi Kafka Operator、Grafana Operator。
- Strimzi Kafka Operator 是部署到 `strimzi-kafka-operator` 命名空间的 Apache Kafka 的 Kubernetes Operator。默认情况下，operator 监视并处理所有命名空间中的 `kafka`。

### 先决条件
确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### 部署

克隆存储库：

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到示例目录之一并运行 `install.sh` 脚本：

```bash
cd data-on-eks/streaming/kafka
chmod +x install.sh
./install.sh
```

:::info

此部署可能需要 20 到 30 分钟。

:::

## 验证部署

### 创建 kube 配置

创建 kube 配置文件。

```bash
aws eks --region $AWS_REGION update-kubeconfig --name kafka-on-eks
```

### 获取节点

检查部署是否为核心节点组创建了大约 3 个节点：

```bash
kubectl get nodes
```

您应该看到类似这样的内容：

```text
NAME                                       STATUS   ROLES    AGE     VERSION
ip-10-1-0-193.eu-west-1.compute.internal   Ready    <none>   5h32m   v1.31.0-eks-a737599
ip-10-1-1-231.eu-west-1.compute.internal   Ready    <none>   5h32m   v1.31.0-eks-a737599
ip-10-1-2-20.eu-west-1.compute.internal    Ready    <none>   5h32m   v1.31.0-eks-a737599
```
</CollapsibleContent>

<CollapsibleContent header={<h2><span>创建 Kafka 集群</span></h2>}>

## 部署 Kafka 集群清单

创建专用于 Kafka 集群的命名空间：

```bash
kubectl create namespace kafka
```

部署 Kafka 集群清单：

```bash
kubectl apply -f kafka-manifests/
```

在 Grafana 中部署 Strimzi Kafka 仪表板：

```bash
kubectl apply -f monitoring-manifests/
```

### 检查 Karpenter 配置的节点

检查您现在是否看到大约 9 个节点，3 个用于核心节点组的节点和 6 个用于跨 3 个可用区的 Kafka 代理：

```bash
kubectl get nodes
```

您应该看到类似这样的内容：

```text
NAME                                       STATUS   ROLES    AGE     VERSION
ip-10-1-1-231.eu-west-1.compute.internal   Ready    <none>   5h32m   v1.31.0-eks-a737599
ip-10-1-2-20.eu-west-1.compute.internal    Ready    <none>   5h32m   v1.31.0-eks-a737599
ip-10-1-0-193.eu-west-1.compute.internal   Ready    <none>   5h32m   v1.31.0-eks-a737599
ip-10-1-0-151.eu-west-1.compute.internal   Ready    <none>   62m     v1.31.0-eks-5da6378
ip-10-1-0-175.eu-west-1.compute.internal   Ready    <none>   62m     v1.31.0-eks-5da6378
ip-10-1-1-104.eu-west-1.compute.internal   Ready    <none>   62m     v1.31.0-eks-5da6378
ip-10-1-1-106.eu-west-1.compute.internal   Ready    <none>   62m     v1.31.0-eks-5da6378
ip-10-1-2-4.eu-west-1.compute.internal     Ready    <none>   62m     v1.31.0-eks-5da6378
ip-10-1-2-56.eu-west-1.compute.internal    Ready    <none>   62m     v1.31.0-eks-5da6378
```

### 验证 Kafka 代理和控制器

验证由 Strimzi Operator 创建的 Kafka 代理和控制器 Pod 及其状态。

```bash
kubectl get strimzipodsets.core.strimzi.io -n kafka
```

您应该看到类似这样的内容：

```text
NAME                 PODS   READY PODS   CURRENT PODS   AGE
cluster-broker       3      3            3              64m
cluster-controller   3      3            3              64m
```

让我们确认您已在 KRaft 模式下创建了 Kafka 集群：

```bash
kubectl get kafka.kafka.strimzi.io -n kafka
```

您应该看到类似这样的输出：

```text
NAME      DESIRED KAFKA REPLICAS   DESIRED ZK REPLICAS   READY   METADATA STATE   WARNINGS
cluster                                                  True    KRaft            True
```

### 验证正在运行的 Kafka Pod
让我们确认 Kafka 集群的 Pod 正在运行：

```bash
kubectl get pods -n kafka
```

您应该看到类似这样的输出：

```text
NAME                                      READY   STATUS    RESTARTS   AGE
cluster-broker-0                          1/1     Running   0          24m
cluster-broker-1                          1/1     Running   0          15m
cluster-broker-2                          1/1     Running   0          8m31s
cluster-controller-3                      1/1     Running   0          16m
cluster-controller-4                      1/1     Running   0          7m8s
cluster-controller-5                      1/1     Running   0          7m48s
cluster-cruise-control-74f5977f48-l8pzp   1/1     Running   0          24m
cluster-entity-operator-d46598d9c-xgwnh   2/2     Running   0          24m
cluster-kafka-exporter-5ff5ff4675-2cz9m   1/1     Running   0          24m
```
</CollapsibleContent>

<CollapsibleContent header={<h2><span>创建 Kafka 主题并运行示例测试</span></h2>}>

我们将创建一个 kafka 主题并运行示例生产者脚本来向 kafka 主题生产新消息。

### 创建 kafka 主题

运行此命令在 `kafka` 命名空间下创建一个名为 `test-topic` 的新主题：

```bash
kubectl apply -f examples/kafka-topics.yaml
```

确认主题已创建：

```bash
kubectl get kafkatopic.kafka.strimzi.io -n kafka
```

您应该看到类似这样的输出：

```text
NAME         CLUSTER   PARTITIONS   REPLICATION FACTOR   READY
test-topic   cluster   12           3                    True
```

验证 `test-topic` 主题的状态。

```bash
kubectl exec -it cluster-broker-0 -c kafka -n kafka -- /bin/bash -c "/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092"
```

您应该看到类似这样的输出：

```text
strimzi.cruisecontrol.metrics
strimzi.cruisecontrol.modeltrainingsamples
strimzi.cruisecontrol.partitionmetricsamples
test-topic
```

### 执行示例 Kafka 生产者

打开两个终端，一个用于 Kafka 生产者，一个用于 Kafka 消费者。执行以下命令并按两次回车，直到您看到 `>` 提示符。开始输入一些随机内容。此数据将写入 `test-topic`。

```bash
kubectl -n kafka run kafka-producer -ti --image=quay.io/strimzi/kafka:0.43.0-kafka-3.8.0 --rm=true --restart=Never -- bin/kafka-console-producer.sh --bootstrap-server cluster-kafka-bootstrap:9092 --topic test-topic
```

### 执行示例 Kafka 消费者

现在，您可以通过在另一个终端中运行 Kafka 消费者 Pod 来验证写入 `test-topic` 的数据

```bash
kubectl -n kafka run kafka-consumer -ti --image=quay.io/strimzi/kafka:0.43.0-kafka-3.8.0 --rm=true --restart=Never -- bin/kafka-console-consumer.sh --bootstrap-server cluster-kafka-bootstrap:9092 --topic test-topic --from-beginning
```

### Kafka 生产者和消费者输出

![img.png](../../../../../../docs/blueprints/streaming-platforms/img/kafka-consumer.png)

</CollapsibleContent>

<CollapsibleContent header={<h2><span>Kafka 的 Grafana 仪表板</span></h2>}>

### 登录 Grafana
通过运行以下命令登录 Grafana 仪表板。

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 8080:80 -n kube-prometheus-stack
```
使用本地 [Grafana Web UI](http://localhost:8080/) 打开浏览器

输入用户名为 `admin`，**密码** 可以使用以下命令从 AWS Secrets Manager 中提取。

```bash
aws secretsmanager get-secret-value --secret-id kafka-on-eks-grafana --region $AWS_REGION --query "SecretString" --output text
```

### 打开 Strimzi Kafka 仪表板

转到 `http://localhost:8080/dashboards` 的 `Dashboards` 页面，然后点击 `General`，然后点击 `Strimizi Kafka`。

您应该看到在部署期间创建的以下内置 Kafka 仪表板：

![Kafka Brokers Dashboard](../../../../../../docs/blueprints/streaming-platforms/img/kafka-brokers.png)

</CollapsibleContent>

<CollapsibleContent header={<h2><span>清理</span></h2>}>

要清理您的环境，请运行以下命令并输入创建 EKS 集群时使用的相同区域：

```bash
cd data-on-eks/streaming/kafka
chmod +x cleanup.sh
./cleanup.sh
```

:::info

这可能需要 20 到 30 分钟。

:::
</CollapsibleContent>
