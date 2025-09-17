---
sidebar_position: 3
sidebar_label: Kubeflow Spark Operator 基准测试
---

# Kubeflow Spark Operator 基准测试 🚀
本文档作为在 Amazon EKS 上对 Kubeflow Spark Operator 进行规模测试的综合指南。主要目标是通过提交数千个作业并分析其在压力下的行为来评估 Spark Operator 在重负载下的性能、可扩展性和稳定性。

本指南提供了以下分步方法：

- **配置 Spark Operator** 以进行高规模作业提交的步骤。
- 性能优化的**基础设施设置**修改。
- 使用 **Locust** 的负载测试执行详细信息。
- 用于监控 Spark Operator 指标和 Kubernetes 指标的 **Grafana 仪表板**

### ✨ 为什么我们需要基准测试
基准测试是评估 Spark Operator 在处理大规模作业提交时的效率和可靠性的关键步骤。这些测试提供了以下有价值的见解：

- **识别性能瓶颈：** 确定系统在重负载下遇到困难的区域。
- **确保优化的资源利用：** 确保 CPU、内存和其他资源得到有效使用。
- **评估重负载下的系统稳定性：** 测试系统在极端条件下维持性能和可靠性的能力。

通过进行这些测试，您可以确保 Spark Operator 能够有效处理现实世界的高需求场景。

### 先决条件

- 在运行基准测试之前，请确保您已按照[此处](https://awslabs.github.io/data-on-eks/docs/blueprints/data-analytics/spark-operator-yunikorn#deploy)的说明部署了 **Spark Operator** EKS 集群。
- 访问必要的 AWS 资源和修改 EKS 配置的权限。
- 熟悉 **Terraform**、**Kubernetes** 和用于负载测试的 **Locust**。

### 集群更新

为了准备集群进行基准测试，请应用以下修改：

**步骤 1：更新 Spark Operator Helm 配置**

在文件 [analytics/terraform/spark-k8s-operator/addons.tf](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/addons.tf) 中取消注释指定的 Spark Operator Helm 值（从 `-- Start` 到 `-- End` 部分）。然后，运行 terraform apply 以应用更改。

这些更新确保：
- Spark Operator 和 webhook Pod 使用 Karpenter 部署在专用的 `c5.9xlarge` 实例上。
- 实例提供 `36 vCPU` 来处理 `6000` 个应用程序提交。
- 为 Controller Pod 和 Webhook Pod 分配高 CPU 和内存资源。

以下是更新的配置：

```yaml
enable_spark_operator = true
  spark_operator_helm_config = {
    version = "2.1.0"
    timeout = "120"
    values = [
      <<-EOT
        controller:
          replicas: 1
          # -- Reconcile concurrency, higher values might increase memory usage.
          # -- Increased from 10 to 20 to leverage more cores from the instance
          workers: 20
          # -- Change this to True when YuniKorn is deployed
          batchScheduler:
            enable: false
            # default: "yunikorn"
#  -- Start: Uncomment this section in the code for Spark Operator scale test
          # -- Spark Operator is CPU bound so add more CPU or use compute optimized instance for handling large number of job submissions
          nodeSelector:
            NodeGroupType: spark-operator-benchmark
          resources:
            requests:
              cpu: 33000m
              memory: 50Gi
        webhook:
          nodeSelector:
            NodeGroupType: spark-operator-benchmark
          resources:
            requests:
              cpu: 1000m
              memory: 10Gi
#  -- End: Uncomment this section in the code for Spark Operator scale test
        spark:
          jobNamespaces:
            - default
            - spark-team-a
            - spark-team-b
            - spark-team-c
          serviceAccount:
            create: false
          rbac:
            create: false
        prometheus:
          metrics:
            enable: true
            port: 8080
            portName: metrics
            endpoint: /metrics
            prefix: ""
          podMonitor:
            create: true
            labels: {}
            jobLabel: spark-operator-podmonitor
            podMetricsEndpoint:
              scheme: http
              interval: 5s
      EOT
    ]
  }
```

**步骤 2：大规模集群的 Prometheus 最佳实践**

- 为了有效监控跨 200 个节点的 32,000+ 个 Pod，Prometheus 应该在专用节点上运行，并增加 CPU 和内存分配。确保使用 Prometheus Helm chart 中的 NodeSelector 将 Prometheus 部署在核心节点组上。这可以防止工作负载 Pod 的干扰。
- 在规模上，**Prometheus** 可能消耗大量 CPU 和内存，因此在专用基础设施上运行它确保它不会与您的应用程序竞争。通常使用节点选择器或污点将节点或节点池专门用于监控组件（Prometheus、Grafana 等）。
- Prometheus 是内存密集型的，当监控数百或数千个 Pod 时，也会需要大量 CPU
- 分配专用资源（甚至使用 Kubernetes 优先级类或 QoS 来优先考虑 Prometheus）有助于在压力下保持监控的可靠性。
- 请注意，完整的可观察性堆栈（指标、日志、跟踪）在规模上可能消耗大约三分之一的基础设施资源，因此请相应地规划容量。
- 从一开始就分配充足的内存和 CPU，并且优先选择没有严格低限制的请求。例如，如果您估计 Prometheus 需要 `~8 GB`，不要将其限制在 `4 GB`。最好为 Prometheus 保留整个节点或节点的大部分。

**步骤 3：为高 Pod 密度配置 VPC CNI：**

修改 [analytics/terraform/spark-k8s-operator/eks.tf](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/eks.tf) 以在 `vpc-cni` 插件中启用 `prefix delegation`。这将每个节点的 Pod 容量从 `110 增加到 200`。

```hcl
cluster_addons = {
  vpc-cni = {
    configuration_values = jsonencode({
      env = {
        ENABLE_PREFIX_DELEGATION = "true"
        WARM_PREFIX_TARGET       = "1"
      }
    })
  }
}
```

**重要说明：** 进行这些更改后，运行 `terraform apply` 以更新 VPC CNI 配置。

**步骤 4：为 Spark 负载测试创建专用节点组**

我们创建了一个名为 **spark_operator_bench** 的专用托管节点组来放置 Spark 作业 Pod。配置了一个具有 `m6a.4xlarge` 实例的 `200 节点`托管节点组用于 Spark 负载测试 Pod。用户数据已被修改为允许每个节点最多 `220 个 Pod`。

**注意：** 此步骤仅供参考，无需手动应用更改。

```hcl
spark_operator_bench = {
  name        = "spark_operator_bench"
  description = "Managed node group for Spark Operator Benchmarks with EBS using x86 or ARM"

  min_size     = 0
  max_size     = 200
  desired_size = 0
  ...

  cloudinit_pre_nodeadm = [
    {
      content_type = "application/node.eks.aws"
      content      = <<-EOT
        ---
        apiVersion: node.eks.aws/v1alpha1
        kind: NodeConfig
        spec:
          kubelet:
            config:
              maxPods: 220
      EOT
    }
  ]
...

}
```

**步骤 5：手动将节点组最小大小更新为 200**

:::caution

运行 200 个节点可能产生大量成本。如果您计划独立运行此测试，请提前仔细估算费用以确保预算可行性。

:::

最初，设置 `min_size = 0`。在开始负载测试之前，在 AWS 控制台中将 `min_size` 和 `desired_size` 更新为 `200`。这会预先创建负载测试所需的所有节点，确保所有 DaemonSet 都在运行。

### 负载测试配置和执行

为了模拟高规模并发作业提交，我们开发了 **Locust** 脚本，通过模拟多个用户动态创建 Spark Operator 模板并并发提交作业。

**步骤 1：设置 Python 虚拟环境**
在您的本地机器（Mac 或桌面）上，创建 Python 虚拟环境并安装所需的依赖项：

```
cd analytics/terraform/spark-k8s-operator/examples/benchmark/spark-operator-benchmark-kit
python3.12 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

**步骤 2：运行负载测试**
执行以下命令开始负载测试：

```sh
locust --headless --only-summary -u 3 -r 1 \
--job-limit-per-user 2000 \
--jobs-per-min 1000 \
--spark-namespaces spark-team-a,spark-team-b,spark-team-c
```

此命令：
- 启动具有 **3 个并发用户**的测试。
- 每个用户以每分钟 **1000 个作业**的速率提交 **2000 个作业**。
- 此命令总共提交 **6000 个作业**。每个 Spark 作业包含 **6 个 Pod**（1 个 Driver 和 5 个 executor Pod）
- 使用 **3 个命名空间**在 **200 个节点**上生成 **36,000 个 Pod**。

- Locust 脚本使用位于以下位置的 Spark 作业模板：`analytics/terraform/spark-k8s-operator/examples/benchmark/spark-operator-benchmark-kit/spark-app-with-webhook.yaml`。

- Spark 作业使用简单的 `spark-pi-sleep.jar`，它会休眠指定的持续时间。测试镜像可在以下位置获得：`public.ecr.aws/data-on-eks/spark:pi-sleep-v0.0.2`

### 结果验证
负载测试运行大约 1 小时。在此期间，您可以使用 Grafana 监控 Spark Operator 指标、集群性能和资源利用率。按照以下步骤访问监控仪表板：

**步骤 1：端口转发 Grafana 服务**
运行以下命令创建本地端口转发，使 Grafana 可从您的本地机器访问：

```sh
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n kube-prometheus-stack
```
这将您本地系统上的端口 3000 映射到集群内的 Grafana 服务。

**步骤 2：访问 Grafana**
要登录 Grafana，请检索存储管理员凭据的密钥名称：

```bash
terraform output grafana_secret_name
```

然后，使用检索到的密钥名称从 AWS Secrets Manager 获取凭据：

```bash
aws secretsmanager get-secret-value --secret-id <grafana_secret_name_output> --region $AWS_REGION --query "SecretString" --output text
```

**步骤 3：访问 Grafana 仪表板**
1. 打开 Web 浏览器并导航到 http://localhost:3000 
2. 输入用户名为 `admin`，密码为从上一个命令检索到的密码。
3. 导航到 Spark Operator 负载测试仪表板以可视化：

- 提交的 Spark 作业数量。
- 集群范围的 CPU 和内存消耗。
- Pod 扩展行为和资源分配。

## 结果摘要

:::tip

有关详细分析，请参考 [Kubeflow Spark Operator 网站](https://www.kubeflow.org/docs/components/spark-operator/overview/)

:::

**CPU 利用率：**

- Spark Operator controller Pod 是 CPU 绑定的，在峰值处理期间利用所有 36 个核心。
- CPU 约束限制了作业处理速度，使计算能力成为可扩展性的关键因素。

**内存使用：**
- 无论处理的应用程序数量如何，内存消耗都保持稳定。
- 这表明内存不是瓶颈，增加 RAM 不会提高性能。

**作业处理速率：**
- Spark Operator 以每分钟约 130 个应用程序的速度处理应用程序。
- 处理速率受 CPU 限制的限制，在没有额外计算资源的情况下无法进一步扩展。

**处理作业的时间：**
- 处理 2,000 个应用程序约需 15 分钟。
- 处理 4,000 个应用程序约需 30 分钟。
- 这些数字与观察到的每分钟 130 个应用程序的处理速率一致。

**工作队列持续时间指标可靠性：**
- 默认工作队列持续时间指标一旦超过 16 分钟就变得不可靠。
- 在高并发下，此指标无法提供队列处理时间的准确见解。

**API 服务器性能影响：**
- 在高工作负载条件下，Kubernetes API 请求持续时间显著增加。
- 这是由于 Spark 频繁查询 executor Pod 造成的，而不是 Spark Operator 本身的限制。
- 增加的 API 服务器负载影响整个集群的作业提交延迟和监控性能。

## 清理

**步骤 1：缩减节点组**

为了避免不必要的成本，首先通过将 **spark_operator_bench** 节点组的最小和期望节点数设置为零来缩减它：

1. 登录 AWS 控制台。
2. 导航到 EKS 部分。
3. 找到并选择 **spark_operator_bench** 节点组。
4. 编辑节点组并将最小大小和期望大小更新为 0。
5. 保存更改以缩减节点。

**步骤 2：销毁集群**
节点缩减后，您可以使用以下脚本继续进行集群拆除：

```sh
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator && chmod +x cleanup.sh
./cleanup.sh
```
