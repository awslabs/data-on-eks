---
sidebar_position: 2
sidebar_label: Apache Pinot
---
# 在 EKS 上部署 Apache Pinot (🍷)

[Apache Pinot](https://pinot.apache.org/) 是实时分布式 OLAP 数据存储，专为低延迟和高吞吐量分析而构建。您可以使用 Pinot 从流式或批处理数据源（例如 Apache Kafka、Amazon Kinesis Data Streams、Amazon S3 等）摄取并立即查询数据。

Apache Pinot 包括以下特征：

- 即使在极高吞吐量下也能实现**超低延迟**分析。
- **列式数据存储**，具有多种智能索引和预聚合技术。
- **向上**和**向外扩展**，没有上限。
- 基于集群大小和预期每秒查询数 (QPS) 阈值的**一致性能**。

它是面向用户的实时分析和其他分析用例的完美解决方案，包括内部仪表板、异常检测和即席数据探索。您可以在其[文档](https://docs.pinot.apache.org/)中了解更多关于 Apache Pinot 及其组件的信息。

在此蓝图中，我们将在由 Elastic Kubernetes Service (EKS) 管理的 Kubernetes 集群上部署 Apache Pinot。在 EKS 集群上部署 Apache Pinot 的一些好处包括

- 使用 Kubernetes 管理 Apache Pinot 集群
- 独立扩展每一层
- 没有单点故障
- 自动恢复

## 架构

![Apache Pinot on EKS](../../../../../../docs/blueprints/distributed-databases/img/pinot-on-eks.png)

在此设置中，我们在跨 3 个可用区的私有子网中部署所有 Apache Pinot 组件。这允许更大的灵活性和弹性。大多数 Pinot 组件可以在最新一代通用计算实例 (`m7i`) 上运行，除了需要内存优化实例类型 (`r7i`) 的服务器组件。我们还设置内部 NLB 以轻松与控制器和代理组件通信。

> 注意：所有 Apache Pinot 组件都在 `StatefulSet` 上运行。

> 注意：此蓝图目前不利用 [DeepStore](https://docs.pinot.apache.org/basics/components/table/segment/deep-store)，而是使用 EBS 卷在服务器上存储表段。

> 注意：根据您的用例，您需要更新集群大小和配置以更好地适应您的用例。您可以在[这里](https://startree.ai/blog/capacity-planning-in-apache-pinot-part-1)和[这里](https://startree.ai/blog/capacity-planning-in-apache-pinot-part-2)阅读更多关于 Apache Pinot 容量规划的信息。

## 先决条件 📝

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

## 部署 ⚙️

### 使用 Apache Pinot 部署 EKS 集群

首先，克隆存储库。

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到 apache pinot 文件夹并创建 `terraform.tfvars` 以为所有变量提供所需的值。这也是更新任何其他输入变量或对 terraform 模板进行任何其他更改的时候。

```bash
cd data-on-eks/distributed-databases/pinot
touch terraform.tfvars
```

#### 示例 `terraform.tfvars`
```terraform
name                = "pinot-on-eks"
region              = "us-west-2"
eks_cluster_version = "1.25"
...
```

更新变量后，您可以运行安装脚本来部署预配置的 EKS 集群和 Apache Pinot。

```
./install.sh
```

### 验证部署

验证 Amazon EKS 集群

```bash
aws eks describe-cluster --name pinot-on-eks
```

更新本地 kubeconfig，以便我们可以访问 kubernetes 集群。

```bash
aws eks update-kubeconfig --name pinot-on-eks --region us-west-2
```

首先，让我们验证集群中有工作节点正在运行。

```bash
kubectl get nodes
```
#### 输出
```bash
NAME                                         STATUS   ROLES    AGE   VERSION
ip-10-1-189-200.us-west-2.compute.internal   Ready    <none>   12d   v1.24.17-eks-43840fb
ip-10-1-46-117.us-west-2.compute.internal    Ready    <none>   12d   v1.24.17-eks-43840fb
ip-10-1-84-80.us-west-2.compute.internal     Ready    <none>   12d   v1.24.17-eks-43840fb
```

接下来，让我们验证所有 Pod 都在运行。

```bash
kubectl get pods -n pinot
```
#### 输出
```bash
NAME                                                   READY   STATUS      RESTARTS   AGE
pinot-broker-0                                         1/1     Running     0          11d
pinot-broker-1                                         1/1     Running     0          11d
pinot-broker-2                                         1/1     Running     0          11d
pinot-controller-0                                     1/1     Running     0          11d
pinot-controller-1                                     1/1     Running     0          11d
pinot-controller-2                                     1/1     Running     0          11d
pinot-minion-stateless-86cf65f89-rlpwn                 1/1     Running     0          12d
pinot-minion-stateless-86cf65f89-tkbjf                 1/1     Running     0          12d
pinot-minion-stateless-86cf65f89-twp8n                 1/1     Running     0          12d
pinot-server-0                                         1/1     Running     0          11d
pinot-server-1                                         1/1     Running     0          11d
pinot-server-2                                         1/1     Running     0          11d
pinot-zookeeper-0                                      1/1     Running     0          12d
pinot-zookeeper-1                                      1/1     Running     0          12d
pinot-zookeeper-2                                      1/1     Running     0          12d
```

我们还在 `monitoring` 命名空间下部署了 `prometheus` 和 `grafana`。因此，还要确保 `monitoring` 的所有 Pod 也在运行。

```bash
kubectl get pods -n monitoring
```
#### 输出
```bash
prometheus-grafana-85b4584dbf-4l72l                    3/3     Running   0          12d
prometheus-kube-prometheus-operator-84dcddccfc-pv8nv   1/1     Running   0          12d
prometheus-kube-state-metrics-57f6b6b4fd-txjtb         1/1     Running   0          12d
prometheus-prometheus-kube-prometheus-prometheus-0     2/2     Running   0          4d3h
prometheus-prometheus-node-exporter-4jh8q              1/1     Running   0          12d
prometheus-prometheus-node-exporter-f5znb              1/1     Running   0          12d
prometheus-prometheus-node-exporter-f9xrz              1/1     Running   0          12d
```

现在让我们使用以下命令访问 Apache Pinot 控制台。控制台包含**集群管理器**、**查询浏览器**、**Zookeeper 浏览器**和 **Swagger REST API 浏览器**。

```bash
kubectl port-forward service/pinot-controller 9000:9000 -n pinot
```

这将允许您使用 `http://localhost:9000` 访问如下所示的 Apache Pinot 控制台

![Apache Pinot Web 控制台](../../../../../../docs/blueprints/distributed-databases/img/pinot-console.png)

Apache Pinot 支持使用 Apache Pinot docker 镜像中打包的 Prometheus JMX exporter 导出指标。让我们确保所有 Apache Pinot 组件的指标都发布到 `prometheus`。

```bash
kubectl port-forward service/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring
```

导航到 `http://localhost:9090` 的 prometheus UI，在搜索框中输入 `pinot`，您应该能够看到所有指标。

![Prometheus](../../../../../../docs/blueprints/distributed-databases/img/prometheus.png)

接下来，让我们使用 Grafana 来可视化 Apache Pinot 指标。为了访问 Grafana，我们需要从 AWS Secrets Manager 获取 grafana 密码。

```bash
aws secretsmanager get-secret-value --secret-id pinot-on-eks-grafana | jq '.SecretString' --raw-output
```

现在使用端口转发在端口 `8080` 访问 Grafana

```bash
kubectl port-forward service/prometheus-grafana 8080:80 -n monitoring
```

使用 `admin` 和在上一步中检索的密码登录 grafana 仪表板，然后导航到 Dashboard 并单击 New，然后单击 Import。使用 `data-on-eks/distributed-database/pinot/dashboard` 下的文件 `pinot.json` 创建 pinot 仪表板。

![Pinot 的 Grafana 仪表板](../../../../../../docs/blueprints/distributed-databases/img/grafana.png)

要了解更多关于使用 Prometheus 和 Grafana 监控 Apache Pinot 的信息，请使用[官方指南](https://docs.pinot.apache.org/operators/tutorials/monitor-pinot-using-prometheus-and-grafana)。

## 附加部署（可选）🏆

### 为流数据部署 Apache Kafka

Apache Pinot 可以从流数据源（实时）以及批处理数据源（离线）摄取数据。在此示例中，我们将利用 [Apache Kafka](https://kafka.apache.org/) 将实时数据推送到主题。

如果您已经在 EKS 集群中运行 Apache Kafka 或您正在利用 Amazon Managed Streaming for Apache Kafka (MSK)，您可以跳过此步骤。否则，请按照以下步骤在您的 EKS 集群中安装 Kafka。

> 注意：以下部署为简化部署配置了带有 PLAINTEXT 监听器的 Kafka Brokers。为生产部署修改 `kafka-values.yaml` 文件

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install -n pinot pinot-kafka bitnami/kafka --values ./helm/kafka-values.yaml
```

#### 输出
```bash
NAME: pinot-kafka
LAST DEPLOYED: Tue Oct 24 01:10:25 2023
NAMESPACE: pinot
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
CHART NAME: kafka
CHART VERSION: 26.2.0
APP VERSION: 3.6.0

** Please be patient while the chart is being deployed **

Kafka can be accessed by consumers via port 9092 on the following DNS name from within your cluster:

    pinot-kafka.pinot.svc.cluster.local

Each Kafka broker can be accessed by producers via port 9092 on the following DNS name(s) from within your cluster:

    pinot-kafka-controller-0.pinot-kafka-controller-headless.pinot.svc.cluster.local:9092
    pinot-kafka-controller-1.pinot-kafka-controller-headless.pinot.svc.cluster.local:9092
    pinot-kafka-controller-2.pinot-kafka-controller-headless.pinot.svc.cluster.local:9092

To create a pod that you can use as a Kafka client run the following commands:

    kubectl run pinot-kafka-client --restart='Never' --image docker.io/bitnami/kafka:3.6.0-debian-11-r0 --namespace pinot --command -- sleep infinity
    kubectl exec --tty -i pinot-kafka-client --namespace pinot -- bash

    PRODUCER:
        kafka-console-producer.sh \
            --broker-list pinot-kafka-controller-0.pinot-kafka-controller-headless.pinot.svc.cluster.local:9092,pinot-kafka-controller-1.pinot-kafka-controller-headless.pinot.svc.cluster.local:9092,pinot-kafka-controller-2.pinot-kafka-controller-headless.pinot.svc.cluster.local:9092 \
            --topic test

    CONSUMER:
        kafka-console-consumer.sh \
            --bootstrap-server pinot-kafka.pinot.svc.cluster.local:9092 \
            --topic test \
            --from-beginning
```

使用上面提到的命令在您的命名空间内创建 **Kafka Client** Pod。

```bash
kubectl run pinot-kafka-client --restart='Never' --image docker.io/bitnami/kafka:3.6.0-debian-11-r0 --namespace pinot --command -- sleep infinity
```

然后连接到容器 shell

```bash
kubectl exec --tty -i pinot-kafka-client --namespace pinot -- bash
```

使用以下命令创建 Kafka 主题，然后将用于发布消息。

```bash
kafka-topics.sh --bootstrap-server pinot-kafka-controller-0.pinot-kafka-controller-headless.pinot.svc.cluster.local:9092 --topic flights-realtime --create --partitions 1 --replication-factor 1

kafka-topics.sh --bootstrap-server pinot-kafka-controller-0.pinot-kafka-controller-headless.pinot.svc.cluster.local:9092 --topic flights-realtime-avro --create --partitions 1 --replication-factor 1
```

然后从容器 shell `exit`

```bash
exit
```

使用提供的 `example/pinot-realtime-quickstart.yml` 创建表并将示例数据发布到上述主题，然后将被摄取到表中。

```bash
kubectl apply -f example/pinot-realtime-quickstart.yml
```

现在，让我们导航回**查询控制台**，然后单击其中一个表。您应该能够看到新创建的表和进入表的数据。
```bash
kubectl port-forward service/pinot-controller 9000:9000 -n pinot
```

![Pinot 示例](../../../../../../docs/blueprints/distributed-databases/img/pinot-example.png)

## 清理 🧹

要删除作为此蓝图一部分配置的所有组件，请使用以下命令销毁所有资源。

```bash
./cleanup.sh
```

:::caution

为避免对您的 AWS 账户产生不必要的费用，请删除在此部署期间创建的所有 AWS 资源

例如：删除 kafka-on-eks EBS 卷
:::
