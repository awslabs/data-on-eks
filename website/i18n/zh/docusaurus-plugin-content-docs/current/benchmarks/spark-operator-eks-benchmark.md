---
sidebar_position: 3
sidebar_label: Kubeflow Spark Operator基准测试
---

# Kubeflow Spark Operator基准测试 🚀
本文档作为在Amazon EKS上对Kubeflow Spark Operator进行规模测试的综合指南。主要目标是通过提交数千个作业并分析其在压力下的行为，评估Spark Operator在重负载下的性能、可扩展性和稳定性。

本指南提供了以下方面的分步骤方法：

- **配置Spark Operator**以进行大规模作业提交的步骤。
- 为性能优化进行的**基础设施设置**修改。
- 使用**Locust**执行负载测试的详细信息。
- 用于监控Spark Operator指标和Kubernetes指标的**Grafana仪表板**

### ✨ 为什么我们需要基准测试
基准测试是评估Spark Operator在处理大规模作业提交时的效率和可靠性的关键步骤。这些测试提供了有价值的见解：

- **识别性能瓶颈：** 确定系统在重负载下挣扎的区域。
- **确保优化资源利用：** 确保CPU、内存和其他资源得到有效利用。
- **评估系统在重负载下的稳定性：** 测试系统在极端条件下维持性能和可靠性的能力。

通过进行这些测试，您可以确保Spark Operator能够有效处理现实世界中的高需求场景。

### 先决条件

- 在运行基准测试之前，确保您已按照[此处](https://awslabs.github.io/data-on-eks/docs/blueprints/data-analytics/spark-operator-yunikorn#deploy)的说明部署了**Spark Operator** EKS集群。
- 访问必要的AWS资源和修改EKS配置的权限。
- 熟悉**Terraform**、**Kubernetes**和用于负载测试的**Locust**。

### 集群更新

要为基准测试准备集群，请应用以下修改：

**步骤1：更新Spark Operator Helm配置**

在文件[analytics/terraform/spark-k8s-operator/addons.tf](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/addons.tf)中取消注释指定的Spark Operator Helm值（从`-- Start`到`-- End`部分）。然后，运行terraform apply应用更改。

这些更新确保：
- Spark Operator和webhook pod部署在使用Karpenter的专用`c5.9xlarge`实例上。
- 该实例提供`36个vCPU`来处理`6000`个应用程序提交。
- 为Controller pod和Webhook pod分配了高CPU和内存资源。

以下是更新后的配置：

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
**步骤2：大规模集群的Prometheus最佳实践**

- 要有效监控跨200个节点的32,000多个pod，Prometheus应该在专用节点上运行，并增加CPU和内存分配。确保Prometheus使用Prometheus Helm图表中的NodeSelectors部署在核心节点组上。这可以防止工作负载pod的干扰。
- 在规模上，**Prometheus**可能会消耗大量CPU和内存，因此在专用基础设施上运行它可确保它不会与您的应用程序竞争。通常使用节点选择器或污点将节点或节点池专门用于监控组件（Prometheus、Grafana等）。
- Prometheus是内存密集型的，在监控数百或数千个pod时，也会需要大量CPU​
- 分配专用资源（甚至使用Kubernetes优先级类或QoS来优先考虑Prometheus）有助于在压力下保持监控的可靠性。
- 请注意，完整的可观测性堆栈（指标、日志、跟踪）在规模上可能会消耗大约三分之一的基础设施资源​，因此相应地规划容量。
- 从一开始就分配充足的内存和CPU，并且对Prometheus优先使用没有严格低限制的请求。例如，如果您估计Prometheus需要`~8 GB`，不要将其限制在`4 GB`。最好为Prometheus保留整个节点或节点的大部分。

**步骤3：为高Pod密度配置VPC CNI：**

修改[analytics/terraform/spark-k8s-operator/eks.tf](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/eks.tf)以在`vpc-cni`附加组件中启用`前缀委托`。这将每个节点的pod容量从`110增加到200`。

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

**重要提示：** 进行这些更改后，运行`terraform apply`更新VPC CNI配置。

**步骤4：为Spark负载测试创建专用节点组**

我们创建了一个名为**spark_operator_bench**的专用托管节点组，用于放置Spark作业pod。为Spark负载测试pod配置了一个带有`m6a.4xlarge`实例的`200节点`托管节点组。用户数据已被修改，允许每个节点最多`220个pod`。

**注意：** 此步骤仅供参考，无需手动应用任何更改。

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

**步骤5：手动将节点组最小大小更新为200**

:::caution

运行200个节点可能会产生大量成本。如果您计划独立运行此测试，请提前仔细估算费用，以确保预算可行。

:::

最初，设置`min_size = 0`。在开始负载测试之前，在AWS控制台中将`min_size`和`desired_size`更新为`200`。这会预先创建负载测试所需的所有节点，确保所有DaemonSet都在运行。

### 负载测试配置和执行

为了模拟高规模并发作业提交，我们开发了**Locust**脚本，通过模拟多个用户动态创建Spark Operator模板并并发提交作业。

**步骤1：设置Python虚拟环境**
在本地机器（Mac或台式机）上，创建Python虚拟环境并安装所需的依赖项：

```
cd analytics/terraform/spark-k8s-operator/examples/benchmark/spark-operator-benchmark-kit
python3.12 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

**步骤2：运行负载测试**
执行以下命令开始负载测试：

```sh
locust --headless --only-summary -u 3 -r 1 \
--job-limit-per-user 2000 \
--jobs-per-min 1000 \
--spark-namespaces spark-team-a,spark-team-b,spark-team-c
```

此命令：
- 启动一个有**3个并发用户**的测试。
- 每个用户以每分钟**1000个作业**的速率提交**2000个作业**。
- 此命令总共提交**6000个作业**。每个Spark作业由**6个pod**组成（1个驱动程序和5个执行器pod）
- 使用**3个命名空间**在**200个节点**上生成**36,000个pod**。

- Locust脚本使用位于：`analytics/terraform/spark-k8s-operator/examples/benchmark/spark-operator-benchmark-kit/spark-app-with-webhook.yaml`的Spark作业模板。

- Spark作业使用一个简单的`spark-pi-sleep.jar`，它会睡眠指定的时间。测试镜像可在：`public.ecr.aws/data-on-eks/spark:pi-sleep-v0.0.2`获取
### 结果验证
负载测试运行大约1小时。在此期间，您可以使用Grafana监控Spark Operator指标、集群性能和资源利用率。按照以下步骤访问监控仪表板：

**步骤1：端口转发Grafana服务**
运行以下命令创建本地端口转发，使Grafana可从本地机器访问：

```sh
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n kube-prometheus-stack
```
这将本地系统上的端口3000映射到集群内的Grafana服务。

**步骤2：访问Grafana**
要登录Grafana，检索存储管理员凭据的密钥名称：

```bash
terraform output grafana_secret_name
```

然后，使用检索到的密钥名称从AWS Secrets Manager获取凭据：

```bash
aws secretsmanager get-secret-value --secret-id <grafana_secret_name_output> --region $AWS_REGION --query "SecretString" --output text
```

**步骤3：访问Grafana仪表板**
1. 打开网络浏览器并导航到 http://localhost:3000
2. 输入用户名为`admin`，密码为从上一个命令检索到的密码。
3. 导航到Spark Operator负载测试仪表板以可视化：

- 提交的Spark作业数量。
- 集群范围的CPU和内存消耗。
- Pod扩展行为和资源分配。

## 结果摘要

:::tip

有关详细分析，请参阅[Kubeflow Spark Operator网站](https://www.kubeflow.org/docs/components/spark-operator/overview/)

:::

**CPU利用率：**

- Spark Operator控制器pod受CPU限制，在峰值处理期间利用所有36个核心。
- CPU约束限制了作业处理速度，使计算能力成为可扩展性的关键因素。

**内存使用：**
- 无论处理的应用程序数量如何，内存消耗保持稳定。
- 这表明内存不是瓶颈，增加RAM不会提高性能。

**作业处理率：**
- Spark Operator以每分钟约130个应用程序的速度处理应用程序。
- 处理率受CPU限制，如果没有额外的计算资源，无法进一步扩展。

**处理作业的时间：**
- 处理2,000个应用程序约需15分钟。
- 处理4,000个应用程序约需30分钟。
- 这些数字与观察到的每分钟130个应用程序的处理率一致。

**工作队列持续时间指标可靠性：**
- 一旦默认工作队列持续时间指标超过16分钟，它就变得不可靠。
- 在高并发下，此指标无法提供关于队列处理时间的准确见解。

**API服务器性能影响：**
- 在高工作负载条件下，Kubernetes API请求持续时间显著增加。
- 这是由Spark频繁查询执行器pod引起的，而不是Spark Operator本身的限制。
- 增加的API服务器负载影响了作业提交延迟和整个集群的监控性能。

## 清理

**步骤1：缩减节点组**

为避免不必要的成本，首先通过将**spark_operator_bench**节点组的最小和所需节点数设置为零来缩减它：

1. 登录AWS控制台。
2. 导航到EKS部分。
3. 找到并选择**spark_operator_bench**节点组。
4. 编辑节点组并将最小大小和所需大小更新为0。
5. 保存更改以缩减节点。

**步骤2：销毁集群**
一旦节点已缩减，您可以使用以下脚本进行集群拆除：

```sh
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator && chmod +x cleanup.sh
./cleanup.sh
```
