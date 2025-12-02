---
sidebar_position: 2
sidebar_label: Trino on EKS Best Practices
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

# Trino on EKS 最佳实践
在 [Amazon Elastic Kubernetes Service](https://aws.amazon.com/eks/) (EKS) 上部署 [Trino](https://trino.io/) 提供了具有云原生可扩展性的分布式查询处理。组织可以通过选择与其工作负载要求匹配的特定计算实例和存储解决方案来优化成本，同时使用 [Karpenter](https://karpenter.sh/) 将 Trino 的强大功能与 EKS 的可扩展性和灵活性相结合。

本指南为在 EKS 上部署 Trino 提供了规范性指导。它专注于通过最佳配置、有效的资源管理和成本节约策略实现高可扩展性和低成本。我们涵盖了流行文件格式（如 Hive 和 Iceberg）的详细配置。这些配置确保无缝的数据访问并优化性能。我们的目标是帮助您建立既高效又经济的 Trino 部署。

我们有一个[部署就绪的蓝图](https://awslabs.github.io/data-on-eks/docs/blueprints/distributed-databases/trino)用于在 EKS 上部署 Trino，它融合了这里讨论的最佳实践。

请参考这些最佳实践进行合理化和进一步优化/微调。

<CollapsibleContent header={<h2><span>Trino 基础知识</span></h2>}>
本节涵盖 Trino 的核心架构、功能、用例和生态系统及其参考资料。

### 核心架构

Trino 是一个强大的分布式 SQL 查询引擎，专为高性能分析和大数据处理而设计。一些关键组件包括

- 分布式 coordinator-worker 模型
- 内存处理架构
- MPP（大规模并行处理）执行
- 动态查询优化引擎
- 更多详细信息可以在[这里](https://trino.io/docs/current/overview/concepts.html#architecture)找到

### 关键功能

Trino 提供了几个增强数据处理能力的功能。

- 查询联邦
- 跨多个数据源的同时查询
- 支持异构数据环境
- 实时数据处理能力
- 多样化数据源的统一 SQL 接口

### 连接器生态系统

Trino 通过配置具有适当连接器的目录并通过标准 SQL 客户端连接，实现对多样化数据源的 SQL 查询。

- 50+ [生产就绪连接器](https://trino.io/ecosystem/data-source)包括：
  - 云存储（AWS S3）
  - 关系数据库（PostgreSQL、MySQL、SQL Server）
  - NoSQL 存储（MongoDB、Cassandra）
  - 数据湖（Apache Hive、Apache Iceberg、Delta Lake）
  - 流平台（Apache Kafka）

### 查询优化

- 高级基于成本的优化器
- 动态过滤
- 自适应查询执行
- 复杂的内存管理
- 列式处理支持
- 阅读更多[这里](https://trino.io/docs/current/optimizer.html)

### 用例

Trino 解决这些关键用例：

- 交互式分析
- 数据湖查询
- ETL 处理
- 即席分析
- 实时仪表板
- 跨平台数据联邦

</CollapsibleContent>

<CollapsibleContent header={<h2><span>EKS 集群配置</span></h2>}>

## 创建 EKS 集群

- 集群范围：跨多个可用区部署 EKS 集群以实现冗余。
- 控制平面日志记录：启用控制平面日志记录以进行审计和诊断。
- Kubernetes 版本：使用最新的 EKS 版本

### EKS 插件

通过 EKS API 使用 [Amazon EKS 管理的插件](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)，而不是开源 Helm chart。EKS 团队维护这些插件并自动更新它们以与您的 EKS 集群版本保持一致。
- VPC CNI：安装和配置 [Amazon VPC CNI](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html) 插件，使用自定义设置优化 IP 地址使用。
- CoreDNS：确保部署 CoreDNS 以进行内部 DNS 解析。
- KubeProxy：部署 KubeProxy 以实现 Kubernetes 网络代理功能。

:::tip
当您计划启动 EKS 集群并部署 Trino 时，请遵循这些配置详细信息
:::

### 配置
您可以使用 Karpenter 或[托管节点组](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html) (MNG) 来配置和扩展底层计算资源

#### 用于基本组件的托管节点组
MNG 使用启动模板，利用 Auto Scaling Groups，并与 Kubernetes Cluster Autoscaler 集成。

#### 按需节点组
- 为按需实例设置托管节点组，以运行关键组件，如 Trino coordinator 和至少一个 worker。此设置确保核心操作的稳定性和可靠性。
  - **用例**：非常适合运行 Trino coordinator 和基本 worker 节点。

#### Spot 实例节点组
- 为 Spot 实例配置托管节点组，以经济高效地添加额外的 worker 节点。Spot 实例适合处理可变工作负载，同时降低费用。
  - **用例**：最适合为非 SLA 绑定、成本敏感的任务扩展 worker 节点。

#### 其他配置
- **单可用区部署**：在单个可用区内部署节点组，以最小化数据传输成本并减少延迟。
- **实例类型**：选择与您工作负载需求匹配的实例类型，例如用于内存密集型工作负载的 r6g.4xlarge。

### 用于节点扩展的 Karpenter
Karpenter 在 60 秒内配置节点，支持混合实例/架构，利用原生 EC2 API，并提供动态资源分配。

#### 节点池设置
使用 Karpenter 创建包含 spot 和按需实例的动态节点池。应用标签以确保 Trino worker 和 coordinator 根据需要在适当的实例类型（按需或 spot）上启动。
<details>
  <summary> 使用 EC2 Graviton 实例的 Karpenter 节点池示例</summary>
  ```
  apiVersion: karpenter.sh/v1
  kind: NodePool
  metadata:
  name: trino-sql-karpenter
  spec:
  template:
  metadata:
  labels:
  NodePool: trino-sql-karpenter
  spec:
  nodeClassRef:
  group: karpenter.k8s.aws
  kind: EC2NodeClass
  name: trino-karpenter
  requirements:
  - key: "karpenter.sh/capacity-type"
  operator: In
  values: ["on-demand"]
  - key: "kubernetes.io/arch"
  operator: In
  values: ["arm64"]
  - key: "karpenter.k8s.aws/instance-category"
  operator: In
  values: ["r"]
  - key: "karpenter.k8s.aws/instance-family"
  operator: In
  values: ["r6g", "r7g", "r8g"]
  - key: "karpenter.k8s.aws/instance-size"
  operator: In
  values: ["2xlarge", "4xlarge"]
  disruption:
  consolidationPolicy: WhenEmptyOrUnderutilized
  consolidateAfter: 60s
  limits:
  cpu: "1000"
  memory: 1000Gi
  weight: 100
  ```
</details>

Karpenter 节点池设置的示例也可以在 [DoEKS 存储库](https://github.com/awslabs/data-on-eks/blob/f8dda1ae530902b77ee123661265caa09d97969b/distributed-databases/trino/karpenter.tf#L100)和 [EC2 节点类配置](https://github.com/awslabs/data-on-eks/blob/f8dda1ae530902b77ee123661265caa09d97969b/distributed-databases/trino/karpenter.tf#L65)中查看。

### 混合实例
在同一实例池中配置混合实例类型，以增强灵活性并确保根据工作负载需求访问从小到大的各种实例大小。

:::tip[关键建议]
:::
- 使用 Karpenter：为了更好地扩展和简化 Trino 集群的管理，优先使用 Karpenter。它提供更快的节点配置、混合实例类型的增强灵活性和更好的资源效率。Karpenter 提供优于 MNG 的扩展能力，使其成为在分析应用程序中扩展辅助（worker）节点的首选。
- 专用节点：每个节点部署一个 Trino Pod，以充分利用可用资源。
- DaemonSet 资源分配：为基本系统 DaemonSet 保留足够的 CPU 和内存以维持节点稳定性。
- Coordinator 放置：始终在按需节点上运行 Trino coordinator 以保证可靠性。
- Worker 分布：为 worker 节点使用按需和 Spot 实例的混合，以平衡成本效益和可用性。
- 托管节点组使用：MNG 应用于工作负载弹性目的的组件和集群的其他组件，如可观察性工具。
</CollapsibleContent>

<CollapsibleContent header={<span><h2>Trino on EKS 设置</h2></span>}>
Helm 简化了您在 EKS 上的 Trino 部署。我们建议通过 Helm 使用[官方 Helm chart](https://github.com/trinodb/charts)或社区 chart 进行配置管理来安装。

## 设置

* 使用官方 Helm chart 或社区 chart 安装 Trino
* 为每个集群（ETL、交互式、BI）创建不同的 Helm 发布

### 配置步骤

* 为每个集群定义唯一的 `values.yaml` 文件
* 配置 Pod 资源：
  * 设置 CPU/内存请求
  * 设置 CPU/内存限制
  * 指定 coordinator 资源
  * 指定 worker 资源
* 设置 Pod 调度：
  * 配置 nodeSelector
  * 配置亲和性规则

### 部署

为每种工作负载类型使用单独的 Helm 配置，使用各自的值文件。例如
```
# ETL 集群
helm install etl-trino trino-chart -f etl-values.yaml

# 交互式集群
helm install interactive-trino trino-chart -f interactive-values.yaml

# BI 集群
helm install analytics-trino trino-chart -f analytics-values.yaml
```

Trino 作为具有大规模并行处理 (MPP) 架构的分布式查询引擎运行。系统由两个主要组件组成：一个 coordinator 和多个 worker。

#### coordinator 作为中央管理节点：

- 处理传入查询
- 解析和规划查询执行
- 调度和监控工作负载
- 管理 worker 节点
- 为最终用户整合结果

#### Worker 是执行节点：

- 执行分配的任务
- 处理来自各种源的数据
- 共享中间结果
- 与数据源连接器通信
- 通过发现服务向 coordinator 注册

当部署在 EKS 上时，coordinator 和 worker 组件都作为 Pod 在 EKS 集群内运行。系统将模式和引用存储在目录中，这使得能够通过专门的连接器访问各种数据源。这种架构使 Trino 能够在多个节点之间分布查询处理，从而提高大规模数据操作的性能和可扩展性。

### Trino Coordinator 配置

Coordinator 处理查询规划和编排，需要的资源比 worker 节点少。Coordinator Pod 需要的资源比 worker 少，因为它们专注于查询规划而不是数据处理。以下是高可用性和高效资源使用的关键配置设置。

#### 足够用于查询规划和协调任务的资源配置

* 内存：40Gi
* CPU：4-6 核

#### 高可用性设置

* 副本：2 个 coordinator 实例
* Pod 中断预算：确保维护期间 coordinator 可用性
* Pod 反亲和性：在不同节点上调度 coordinator
* 始终配置 Pod 反亲和性以防止多个 coordinator 在同一节点上运行，提高容错能力。

### 交换管理器配置

- 在查询执行期间处理中间数据。
- 将数据卸载到外部存储以提高容错性和可扩展性。

#### 使用 S3 配置交换管理器

#### S3 设置
- 设置为 `s3://your-exchange-bucket`
- `exchange.s3.region`：设置为您的 AWS 区域
- `exchange.s3.iam-role`：使用 IAM 角色进行 S3 访问
- `exchange.s3.max-error-retries`：增加以提高弹性
- `exchange.s3.upload.part-size`：调整以优化性能（例如，64MB）
#### 建议
- 安全性 - 确保 IAM 角色具有必要的最小权限
- 性能 - 调整 `upload.part-size` 和并发连接
- 成本管理 - 监控 S3 成本并实施生命周期策略

## Trino Pod 资源请求与限制

Kubernetes 使用资源请求和限制来有效管理容器资源。以下是如何为不同 Trino Pod 类型优化它们：

### Worker Pod

- 将 resources.requests 设置得略低于 resources.limits（例如，10-20% 的差异）。
- 这种方法确保高效的资源分配，同时防止资源耗尽。

### Coordinator Pod

- 将资源限制配置为比请求高 20-30%。
- 这种策略适应偶尔的使用峰值，在保持可预测调度的同时提供突发容量。

### 此策略的好处

- 改善调度：Kubernetes 基于准确的资源请求做出明智决策，优化 Pod 放置。
- 保护资源：明确定义的限制防止资源耗尽，保护其他集群工作负载。
- 处理突发：更高的限制允许平滑管理瞬态资源峰值。
- 增强稳定性：适当的资源分配减少 Pod 驱逐的风险并提高整体集群稳定性。

### 自动扩展配置

我们建议在 Trino 集群中实施 [KEDA](https://keda.sh/) 进行事件驱动扩展，以实现动态工作负载管理。KEDA 和 Karpenter 在 Amazon EKS 上的组合创建了一个强大的自动扩展解决方案，消除了扩展挑战。虽然 KEDA 基于实时指标管理细粒度 Pod 扩展，Karpenter 处理高效的节点配置。它们一起取代了手动扩展过程，提供了改进的性能和成本优化。

#### 配置 Keda
- 向集群添加 Keda helm 发布
- 向 Trino Helm 值添加 JVM / JMX Exporter 配置，启用 serviceMonitor
```
configProperties: |-
      hostPort: localhost:{{- .Values.jmx.registryPort }}
      startDelaySeconds: 0
      ssl: false
      lowercaseOutputName: false
      lowercaseOutputLabelNames: false
      whitelistObjectNames: ["trino.execution:name=QueryManager","trino.execution:name=SqlTaskManager","trino.execution.executor:name=TaskExecutor","trino.memory:name=ClusterMemoryManager","java.lang:type=Runtime","trino.memory:type=ClusterMemoryPool,name=general","java.lang:type=Memory","trino.memory:type=MemoryPool,name=general"]
      autoExcludeObjectNameAttributes: true
      excludeObjectNameAttributes:
        "java.lang:type=OperatingSystem":
          - "ObjectName"
        "java.lang:type=Runtime":
          - "ClassPath"
          - "SystemProperties"
      rules:
      - pattern: ".*"
```
- 为 trino 部署 KEDA scaledObject，跟踪 CPU 和 QueuedQueries。这里的"目标"CPU 百分比设置为 85%，以利用 Graviton 实例的物理核心。
```
triggers:
  - type: cpu
    metricType: Utilization
    metadata:
      value: '85'  # 目标 CPU 利用率百分比
  - type: prometheus
    metricType: Value
    metadata:
      serverAddress: http://kube-prometheus-stack-prometheus.kube-prometheus-stack.svc.cluster.local:9090
      threshold: '1'
      metricName: queued_queries
      query: sum by (job) (avg_over_time(trino_execution_QueryManager_QueuedQueries{job="trino"}[1m]))
```

## 文件缓存

文件缓存为存储系统和查询操作提供三个主要好处。首先，它通过防止重复检索相同文件来减少存储负载，因为缓存的文件可以在同一 worker 上的多个查询中重用。其次，它可以通过消除重复的网络传输并允许访问本地文件副本来显著提高查询性能，特别是当原始存储在不同网络或区域中时。最后，它通过最小化网络流量和存储访问来降低查询成本。

这是实施文件缓存的基本配置。

```
fs.cache.enabled=true
fs.cache.directories=/tmp/cache/
fs.cache.preferred-hosts-count=10 # 集群大小决定主机数量。我们建议保持较小的主机数量以维持最佳性能。
```

:::note
为缓存目录配置具有本地 SSD 存储的实例，以显著提高 I/O 速度和整体查询性能。
:::

</CollapsibleContent>

<CollapsibleContent header={<h2><span>计算、存储和网络最佳实践</span></h2>}>

<CollapsibleContent header={<span><h2>计算最佳实践</h2></span>}>

## 计算选择

Amazon Elastic Compute Cloud (EC2) 通过其实例系列和处理器提供多样化的计算选项，包括标准、计算优化、内存优化和 I/O 优化配置。您可以通过[灵活的定价模型](https://aws.amazon.com/ec2/pricing/)购买这些实例：按需、计算节省计划、预留或 Spot 实例。选择适当的实例类型可以优化您的成本、最大化性能并支持可持续发展目标。EKS 使您能够将这些计算资源精确匹配到您的工作负载要求。对于 Trino 分布式集群，您的计算选择直接影响集群性能。

:::tip[关键建议]
:::
- 使用 [AWS Graviton 实例](https://aws.amazon.com/ec2/graviton/)：Graviton 实例降低实例成本的同时提高性能，还有助于实现可持续发展目标
- 使用 Karpenter：为了更好地扩展和简化 Trino 集群的管理，优先使用 Karpenter。
- 多样化 Spot 实例以最大化您的节省。[更多详细信息可以在 EC2 Spot 最佳实践中找到](https://aws.amazon.com/blogs/compute/best-practices-to-optimize-your-amazon-ec2-spot-instances-usage/)。将[容错执行](http://localhost:3000/data-on-eks/docs/blueprints/distributed-databases/trino#example-3-optional-fault-tolerant-execution-in-trino)与 EC2 Spot 实例一起使用

</CollapsibleContent>

<CollapsibleContent header={<span><h2>网络最佳实践</h2></span>}>

## 网络规划

Trino 跨 Pod 的分布式特性需要实施网络最佳实践以确保最佳性能。正确的实施提高弹性、防止 IP 耗尽、减少 Pod 初始化错误并最小化延迟。Pod 网络构成 Kubernetes 操作的核心。Amazon EKS 使用 VPC CNI 插件，在底层模式下运行，其中 Pod 和主机共享网络层。这确保了集群和 VPC 环境中一致的 IP 寻址。

### VPC CNI 插件
Amazon VPC CNI 插件可以自定义以有效管理 IP 地址分配。默认情况下，Amazon VPC CNI 为每个节点分配两个弹性网络接口 (ENI)。这些 ENI 保留大量 IP 地址，特别是在较大的实例类型上。由于 Trino 通常每个节点只需要一个 Pod 加上一些用于 DaemonSet Pod（用于日志记录和网络）的 IP 地址，您可以配置 CNI 来限制 IP 地址分配并减少开销。

以下设置可以使用 EKS API、Terraform 或任何其他基础设施即代码 (IaC) 工具应用于 VPC CNI 插件。有关更深入的详细信息，请参考官方文档：VPC CNI 前缀和 IP 目标。

### 配置 VPC CNI 插件

通过调整配置来限制每个节点的 IP 地址，仅分配所需数量的 IP：
- MINIMUM_IP_TARGET：将此设置为每个节点的预期 Pod 数量（例如，30）。
- WARM_IP_TARGET：设置为 1 以保持热 IP 池最小。
- ENABLE_PREFIX_DELEGATION：通过向 worker 节点分配 IP 前缀而不是单个辅助 IP 地址来提高 IP 地址效率。这种方法通过利用更小、更集中的 IP 地址池来减少 VPC 内的网络地址使用 (NAU)。

#### 示例 VPC CNI 配置

```
vpc-cni = {
  preserve = true
  configuration_values = jsonencode({
    env = {
      MINIMUM_IP_TARGET           = "30"
      WARM_IP_TARGET              = "1"
      ENABLE_PREFIX_DELEGATION    = "true"
    }
  })
}
```

:::tip[关键建议]
:::
<b>启用前缀委托：</b> VPC CNI 插件支持前缀委托，它为每个节点分配 16 个 IPv4 地址块（/28 前缀）。此功能减少每个节点所需的 ENI 数量。通过使用前缀委托，您可以降低 EC2 网络地址使用 (NAU)、减少网络管理复杂性并降低运营成本。

#### 有关网络相关的更多最佳实践，[请参考我们的网络指南](/docs/bestpractices/networking#在大型集群或具有大量流失的集群中避免使用-warm_ip_target)

</CollapsibleContent>

<CollapsibleContent header={<span><h2>存储最佳实践</h2></span>}>

本节重点介绍 AWS 服务，用于在 EKS 上使用 Trino 进行最佳存储管理。

## Amazon S3 作为主存储

- 对 Trino 查询中频繁访问的数据使用 S3 Standard
- 为具有不同访问模式的数据实施 S3 Intelligent-Tiering
- 为静态数据启用 S3 服务器端加密（SSE-S3 或 SSE-KMS）
- 通过 IAM 角色配置适当的存储桶策略和访问
- 战略性地使用 S3 存储桶前缀以获得更好的查询性能
- 将 Trino 与 S3 Select 一起使用以提高查询性能

### Coordinator 和 Worker 的 EBS 存储

- 使用 gp3 EBS 卷以获得更好的性能/成本比
- 使用 KMS 启用 EBS 加密
- 根据溢出目录要求调整 EBS 卷大小
- 考虑使用 EBS 快照进行备份策略

### 性能优化

- 在特定工作负载上实施 S3 Select 以提高查询性能
- 为大型数据集使用 AWS 分区索引
- 在 CloudWatch 中启用 S3 请求指标进行监控
- 为 gp3 卷配置适当的读/写 IOPS
- 有效使用 S3 前缀对数据进行分区

### 数据生命周期管理

- 实施 S3 生命周期策略进行自动化数据管理
- 适当使用 S3 存储类：
    - Standard 用于热数据
    - Intelligent-Tiering 用于可变访问模式
    - Standard-IA 用于较少频繁访问的数据
- 为关键数据集配置版本控制

### 成本优化

- 使用 S3 存储类分析来优化存储成本
- 监控和优化 S3 请求模式
- 实施 S3 生命周期策略将较旧数据移动到更便宜的存储层
- 使用 Cost Explorer 跟踪存储支出

### 安全性和合规性

- 实施 VPC 端点进行 S3 访问
- 使用 AWS KMS 进行加密密钥管理
- 启用 S3 访问日志记录以进行审计
- 配置适当的 IAM 角色和策略
- 启用 AWS CloudTrail 进行 API 活动监控

:::note
请记住根据您的特定工作负载特征和要求调整这些实践。
:::

#### 有关 S3 相关最佳实践的详细了解，[请参考 Trino 与 Amazon S3 的最佳实践](https://trino.io/assets/blog/trino-fest-2024/aws-s3.pdf)

</CollapsibleContent>

</CollapsibleContent>

<CollapsibleContent header={<span><h2>配置 Trino 连接器</h2></span>}>
Trino 通过称为连接器的专门适配器连接到数据源。Hive 和 Iceberg 连接器使 Trino 能够读取列式文件格式，如 Parquet 和 ORC（优化行列式）。正确的连接器配置确保最佳查询性能和系统兼容性。

:::tip[关键建议]
:::
- **隔离**：为不同的数据源或环境使用单独的目录
- **安全性**：实施适当的身份验证和授权机制
- **性能**：根据数据格式和查询模式优化连接器设置
- **资源管理**：调整内存和 CPU 设置以匹配每个连接器的工作负载要求

在 Amazon EKS 上将 Trino 与 Hive 和 Iceberg 等文件格式集成需要仔细配置和遵循最佳实践。正确设置连接器并优化资源分配以确保数据访问效率。微调查询性能设置以在保持低成本的同时实现高可扩展性。这些步骤对于最大化 Trino 在 EKS 上的能力至关重要。根据您的特定工作负载定制配置，重点关注数据量和查询复杂性等因素。持续监控系统性能并根据需要调整设置以保持最佳结果。

<CollapsibleContent header={<span><h2>Hive</h2></span>}>

## Hive 连接器配置

Hive 连接器允许 Trino 查询存储在 Hive 数据仓库中的数据，通常使用存储在 HDFS 或 Amazon S3 上的 Parquet、ORC 或 Avro 等文件格式。

### Hive 配置参数

- **连接器名称**：`hive`
- **Metastore**：使用 AWS Glue Data Catalog 作为 metastore。
- **文件格式**：支持 Parquet、ORC、Avro 等。
- **S3 集成**：配置 S3 权限进行数据访问。

### 示例 Hive 目录配置

```
connector.name=hive
hive.metastore=glue
hive.metastore.glue.region=us-west-2
hive.s3.aws-access-key=YOUR_ACCESS_KEY
hive.s3.aws-secret-key=YOUR_SECRET_KEY
hive.s3.iam-role=arn:aws:iam::123456789012:role/YourIAMRole
hive.s3.endpoint=s3.us-west-2.amazonaws.com
hive.s3.path-style-access=true
hive.s3.ssl.enabled=true
hive.security=legacy
```

:::tip[关键建议]
:::
### Metastore 配置

- 使用 AWS Glue 作为 Hive metastore 以获得可扩展性和易于管理
- 设置 `hive.metastore=glue` 并指定区域

### 身份验证

- 使用 IAM 角色（`hive.s3.iam-role`）安全访问 S3
- 确保 IAM 角色具有必要的最小权限

### 性能优化

- **Parquet 和 ORC**：使用 Parquet 或 ORC 等列式文件格式以获得更好的压缩和查询性能
- **分区**：根据经常过滤的列对表进行分区，以减少查询扫描时间
- **缓存**：
  - 使用 `hive.metastore-cache-ttl` 启用元数据缓存以减少 metastore 调用
  - 为文件状态缓存配置 `hive.file-status-cache-size` 和 `hive.file-status-cache-ttl`

### 数据压缩

- 为存储在 S3 中的数据启用压缩以降低存储成本并提高 I/O 性能

### 安全考虑

- **加密**：为 S3 中的静态数据使用服务器端加密（SSE）或客户端加密

- **访问控制**：如有必要，使用 Ranger 或 AWS Lake Formation 实施细粒度访问控制

- **SSL/TLS** 确保 `hive.s3.ssl.enabled=true` 以加密传输中的数据
</CollapsibleContent>

<CollapsibleContent header={<span><h2>Iceberg</h2></span>}>

## Iceberg 连接器配置
Iceberg 连接器允许 Trino 与存储在 Apache Iceberg 表中的数据交互，该表专为大型分析数据集而设计，支持模式演化和隐藏分区等功能。

### 配置参数

- **连接器名称**：iceberg
- **目录类型**：使用 AWS Glue 或 Hive metastore
- **文件格式**：Parquet、ORC 或 Avro
- **S3 集成**：配置类似于 Hive 连接器的 S3 设置

### 示例 Iceberg 目录配置

```properties
connector.name=iceberg
iceberg.catalog.type=glue
iceberg.file-format=PARQUET
iceberg.catalog.glue.region=us-west-2
iceberg.catalog.glue.iam-role=arn:aws:iam::123456789012:role/YourIAMRole
iceberg.register-table-procedure.enabled=true
hive.s3.aws-access-key=YOUR_ACCESS_KEY
hive.s3.aws-secret-key=YOUR_SECRET_KEY
hive.s3.iam-role=arn:aws:iam::123456789012:role/YourIAMRole
hive.s3.endpoint=s3.us-west-2.amazonaws.com
hive.s3.path-style-access=true
hive.s3.ssl.enabled=true
```

:::tip[关键建议]
:::

### 目录配置
- 使用 AWS Glue 作为目录进行集中模式管理
- 设置 `iceberg.catalog.type=glue` 并指定区域
- 使用 Iceberg REST 目录协议
 `iceberg.catalog.type=rest`
  `iceberg.rest-catalog.uri=https://iceberg-with-rest:8181/'`

####   文件格式
- 使用 Parquet 或 ORC 以获得最佳性能
- 设置 `iceberg.file-format=PARQUET`

#### 模式演化
- Iceberg 支持无需表重写的模式演化
- 确保 `iceberg.register-table-procedure.enabled=true` 以允许表注册

#### 分区
- 利用 Iceberg 的隐藏分区功能简化查询语法并提高性能

#### 身份验证
- 使用 IAM 角色安全访问 S3 和 Glue
- 确保角色具有 Iceberg 操作的必要权限

### 性能优化

#### 快照管理
- 定期过期旧快照以防止性能下降
- 使用 `iceberg.expire-snapshots.min-snapshots-to-keep` 和 `iceberg.expire-snapshots.max-ref-age` 设置

#### 元数据缓存
- 启用缓存以减少对 metastore 的调用
- 调整 `iceberg.catalog.cache-ttl` 以设置缓存持续时间

#### 并行性
- 配置拆分大小和并行性设置以优化读取性能
- 调整 `iceberg.max-partitions-per-scan` 和 `iceberg.max-splits-per-node`

### 安全考虑

#### 数据加密
- 实施静态和传输中的加密

#### 访问控制
- 使用 IAM 策略应用细粒度权限

#### 合规性
- 在使用模式演化功能时确保符合数据治理策略

</CollapsibleContent>
</CollapsibleContent>

<CollapsibleContent header={<span><h2>大规模查询优化</h2></span>}>

## 指南

可以在下面找到在 Trino 中优化大规模查询的通用指南。有关更多详细信息，请参考[查询优化器](https://trino.io/docs/current/optimizer.html)

### 内存管理
- 确保从容器到查询级别的适当分配
- 启用具有优化阈值的内存溢出

### 查询优化
- 增加 initialHashPartitions 以获得更好的并行性
- 使用自动连接分布和重新排序
- 优化拆分批处理大小以进行高效处理

### 资源管理
- 强制每个节点一个 Pod 以最大化资源利用率
- 分配足够的 CPU，同时为系统进程保留资源
- 优化垃圾收集设置

### 交换管理
- 使用具有优化设置的 S3 进行交换数据
- 增加并发连接并调整上传部分大小

:::tip[关键建议]
:::
- **监控**：使用 Prometheus 和 Grafana 等工具进行实时指标监控
- **测试**：在生产前模拟工作负载/运行 POC 以验证配置
- **实例选择**：考虑最新一代 Graviton 实例（Graviton3、Graviton4）以提高性价比。
- **网络带宽**：确保实例提供足够的网络带宽以防止瓶颈

</CollapsibleContent>
