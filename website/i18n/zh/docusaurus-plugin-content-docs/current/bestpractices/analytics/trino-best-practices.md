---
sidebar_position: 2
sidebar_label: Trino on EKS最佳实践
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

# Trino on EKS最佳实践
[Trino](https://trino.io/)在[Amazon Elastic Kubernetes Service](https://aws.amazon.com/eks/) (EKS)上的部署提供了具有云原生可扩展性的分布式查询处理。组织可以通过选择与其工作负载需求相匹配的特定计算实例和存储解决方案来优化成本，同时使用[Karpenter](https://karpenter.sh/)将Trino的强大功能与EKS的可扩展性和灵活性相结合。

本指南为在EKS上部署Trino提供了规范性指导。它专注于通过最佳配置、有效的资源管理和成本节约策略来实现高可扩展性和低成本。我们涵盖了流行文件格式（如Hive和Iceberg）的详细配置。这些配置确保了无缝的数据访问并优化了性能。我们的目标是帮助您设置既高效又经济的Trino部署。

我们有一个[可直接部署的蓝图](https://awslabs.github.io/data-on-eks/docs/blueprints/distributed-databases/trino)用于在EKS上部署Trino，其中包含了此处讨论的最佳实践。

参考这些最佳实践以了解原理和进一步的优化/微调。

<CollapsibleContent header={<h2><span>Trino基础</span></h2>}>
本节涵盖Trino的核心架构、功能、用例和生态系统，并提供参考。

### 核心架构

Trino是一个强大的分布式SQL查询引擎，专为高性能分析和大数据处理而设计。一些关键组件包括

- 分布式协调器-工作节点模型
- 内存处理架构
- MPP（大规模并行处理）执行
- 动态查询优化引擎
- 更多详细信息可在[此处](https://trino.io/docs/current/overview/concepts.html#architecture)找到

### 关键功能

Trino提供了几个增强数据处理能力的功能。

- 查询联合
- 跨多个数据源的同时查询
- 支持异构数据环境
- 实时数据处理能力
- 为多样化数据源提供统一的SQL接口

### 连接器生态系统

Trino通过配置具有适当连接器的目录并通过标准SQL客户端连接，使得可以对多样化的数据源进行SQL查询。

- 50多个[生产就绪连接器](https://trino.io/ecosystem/data-source)，包括：
  - 云存储（AWS S3）
  - 关系数据库（PostgreSQL、MySQL、SQL Server）
  - NoSQL存储（MongoDB、Cassandra）
  - 数据湖（Apache Hive、Apache Iceberg、Delta Lake）
  - 流平台（Apache Kafka）

### 查询优化

- 高级基于成本的优化器
- 动态过滤
- 自适应查询执行
- 复杂的内存管理
- 列式处理支持
- 在[此处](https://trino.io/docs/current/optimizer.html)阅读更多

### 用例

Trino解决了这些关键用例：

- 交互式分析
- 数据湖查询
- ETL处理
- 即席分析
- 实时仪表板
- 跨平台数据联合

</CollapsibleContent>
<CollapsibleContent header={<h2><span>EKS集群配置</span></h2>}>

## 创建EKS集群

- 集群范围：将EKS集群部署在多个可用区以实现冗余。
- 控制平面日志：启用控制平面日志以进行审计和诊断。
- Kubernetes版本：使用最新的EKS版本

### EKS附加组件

使用[Amazon EKS托管附加组件](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)通过EKS API，而不是开源Helm图表。EKS团队维护这些附加组件，并自动更新它们以与您的EKS集群版本保持一致。
- VPC CNI：安装并配置[Amazon VPC CNI](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html)插件，使用自定义设置优化IP地址使用。
- CoreDNS：确保部署CoreDNS用于内部DNS解析。
- KubeProxy：部署KubeProxy以实现Kubernetes网络代理功能。

:::tip
当您计划启动EKS集群并部署Trino时，请遵循这些配置详细信息
:::

### 配置
您可以使用Karpenter或[托管节点组](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html) (MNG)配置和扩展底层计算资源

#### 用于基本组件的托管节点组
MNG使用启动模板，利用自动扩展组，并与Kubernetes集群自动扩展器集成。

#### 按需节点组
- 设置一个托管节点组用于按需实例，以运行关键组件，如Trino协调器和至少一个工作节点。此设置确保核心操作的稳定性和可靠性。
  - **用例**：非常适合运行Trino协调器和基本工作节点。

#### 竞价实例节点组
- 配置一个托管节点组用于竞价实例，以经济高效地添加额外的工作节点。竞价实例适合处理可变工作负载，同时降低费用。
  - **用例**：最适合为非SLA绑定、对成本敏感的任务扩展工作节点。

#### 其他配置
- **单一可用区部署**：在单一可用区内部署节点组，以最小化数据传输成本并减少延迟。
- **实例类型**：选择与您工作负载需求相匹配的实例类型，如r6g.4xlarge用于内存密集型工作负载。

### Karpenter用于节点扩展
Karpenter在60秒内配置节点，支持混合实例/架构，利用原生EC2 API，并提供动态资源分配。

#### 节点池设置
使用Karpenter创建一个包含竞价和按需实例的动态节点池。应用标签以确保Trino工作节点和协调器根据需要在适当的实例类型（按需或竞价）上启动。
<details>
  <summary> 使用EC2 Graviton实例的Karpenter节点池示例</summary>
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

Karpenter节点池设置的示例也可以在[DoEKS仓库](https://github.com/awslabs/data-on-eks/blob/f8dda1ae530902b77ee123661265caa09d97969b/distributed-databases/trino/karpenter.tf#L100)和[EC2节点类配置](https://github.com/awslabs/data-on-eks/blob/f8dda1ae530902b77ee123661265caa09d97969b/distributed-databases/trino/karpenter.tf#L65)中查看。

### 混合实例
在同一实例池中配置混合实例类型，以增强灵活性并确保根据工作负载需求访问从小到大的各种实例大小。


:::tip[关键建议]
:::
- 使用Karpenter：为了更好地扩展和简化Trino集群的管理，优先使用Karpenter。它提供更快的节点配置、增强的混合实例类型灵活性和更好的资源效率。与MNG相比，Karpenter提供了卓越的扩展能力，使其成为扩展分析应用程序中的辅助（工作）节点的首选。
- 专用节点：每个节点部署一个Trino pod，以充分利用可用资源。
- DaemonSet资源分配：为基本系统DaemonSet保留足够的CPU和内存，以维持节点稳定性。
- 协调器放置：始终在按需节点上运行Trino协调器，以保证可靠性。
- 工作节点分布：对工作节点使用按需和竞价实例的混合，以平衡成本效益和可用性。
- 托管节点组使用：MNG应用于工作负载的弹性组件和集群的其他组件，如可观测性工具。
</CollapsibleContent>
<CollapsibleContent header={<span><h2>Trino on EKS设置</h2></span>}>
Helm简化了您在Trino on EKS部署。我们建议使用[官方Helm图表](https://github.com/trinodb/charts)或社区图表通过Helm安装，以进行配置管理。

## 设置

* 使用官方Helm图表或社区图表安装Trino
* 为每个集群创建不同的Helm发布（ETL、交互式、BI）

### 配置步骤

* 为每个集群定义唯一的`values.yaml`文件
* 配置pod资源：
  * 设置CPU/内存请求
  * 设置CPU/内存限制
  * 指定协调器资源
  * 指定工作节点资源
* 设置pod调度：
  * 配置nodeSelector
  * 配置亲和性规则

### 部署

为每种工作负载类型使用单独的Helm配置，以及它们各自的值文件。例如
```
# ETL集群
helm install etl-trino trino-chart -f etl-values.yaml

# 交互式集群
helm install interactive-trino trino-chart -f interactive-values.yaml

# BI集群
helm install analytics-trino trino-chart -f analytics-values.yaml
```

Trino作为具有大规模并行处理(MPP)架构的分布式查询引擎运行。系统由两个主要组件组成：一个协调器和多个工作节点。

#### 协调器作为中央管理节点，它：

- 处理传入的查询
- 解析和规划查询执行
- 调度和监控工作负载
- 管理工作节点
- 为最终用户整合结果

#### 工作节点是执行节点，它们：

- 执行分配的任务
- 处理来自各种来源的数据
- 共享中间结果
- 与数据源连接器通信
- 通过发现服务向协调器注册

在EKS上部署时，协调器和工作节点组件都作为pod在EKS集群内运行。系统在目录中存储模式和引用，这使得可以通过专门的连接器访问各种数据源。这种架构使Trino能够在多个节点上分布查询处理，从而提高大规模数据操作的性能和可扩展性。


### Trino协调器配置

协调器处理查询规划和编排，比工作节点需要更少的资源。协调器pod需要比工作节点更少的资源，因为它们专注于查询规划而不是数据处理。以下是高可用性和高效资源使用的关键配置设置。

#### 足够用于查询规划和协调任务的资源配置

* 内存：40Gi
* CPU：4-6核

#### 高可用性设置

* 副本：2个协调器实例
* Pod中断预算：确保维护期间协调器的可用性
* Pod反亲和性：将协调器调度在不同的节点上
* 始终配置Pod反亲和性，以防止多个协调器在同一节点上运行，提高容错能力。

### 交换管理器配置

- 处理查询执行期间的中间数据。
- 将数据卸载到外部存储，以提高容错能力和可扩展性。

#### 使用S3配置交换管理器

#### S3设置
- 设置为`s3://your-exchange-bucket`
- `exchange.s3.region`：设置为您的AWS区域
- `exchange.s3.iam-role`：使用IAM角色进行S3访问
- `exchange.s3.max-error-retries`：增加以提高弹性
- `exchange.s3.upload.part-size`：调整以优化性能（例如，64MB）
#### 建议
- 安全性 - 确保IAM角色具有必要的最低权限
- 性能 - 调整`upload.part-size`和并发连接
- 成本管理 - 监控S3成本并实施生命周期策略

## Trino Pod资源请求与限制

Kubernetes使用资源请求和限制来有效管理容器资源。以下是如何为不同的Trino pod类型优化它们：

### 工作节点Pod

- 将resources.requests设置为略低于resources.limits（例如，相差10-20%）。
- 这种方法确保了高效的资源分配，同时防止资源耗尽。

### 协调器Pod

- 将资源限制配置为比请求高20-30%。
- 这种策略可以适应偶尔的使用峰值，提供突发容量，同时保持可预测的调度。

### 此策略的好处

- 改进调度：Kubernetes根据准确的资源请求做出明智的决策，优化pod放置。
- 保护资源：明确定义的限制防止资源耗尽，保护其他集群工作负载。
- 处理突发：更高的限制允许平稳管理瞬时资源峰值。
- 增强稳定性：适当的资源分配减少了pod驱逐的风险，提高了整体集群稳定性。


### 自动扩展配置

我们建议在Trino集群中实施[KEDA](https://keda.sh/)进行事件驱动的扩展，以实现动态工作负载管理。KEDA和Karpenter在Amazon EKS上的组合创建了一个强大的自动扩展解决方案，消除了扩展挑战。KEDA管理基于实时指标的细粒度pod扩展，而Karpenter处理高效的节点配置。它们共同取代了手动扩展过程，提供了改进的性能和成本优化。

#### 配置Keda
- 向集群添加Keda helm发布
- 向Trino Helm值添加JVM / JMX Exporter配置，启用serviceMonitor
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
- 为trino部署KEDA scaledObject，跟踪CPU和QueuedQueries。这里的'target' CPU百分比设置为85%，以利用Graviton实例的物理核心。
```
triggers:
  - type: cpu
    metricType: Utilization
    metadata:
      value: '85'  # 目标CPU利用率百分比
  - type: prometheus
    metricType: Value
    metadata:
      serverAddress: http://kube-prometheus-stack-prometheus.kube-prometheus-stack.svc.cluster.local:9090
      threshold: '1'
      metricName: queued_queries
      query: sum by (job) (avg_over_time(trino_execution_QueryManager_QueuedQueries{job="trino"}[1m]))
```

## 文件缓存

文件缓存为存储系统和查询操作提供三大主要好处。首先，它通过防止重复检索相同的文件来减少存储负载，因为缓存的文件可以在同一工作节点上的多个查询中重复使用。其次，它可以显著提高查询性能，消除重复的网络传输并允许访问本地文件副本，特别是当原始存储位于不同的网络或区域时。最后，它通过最小化网络流量和存储访问来降低查询成本。

这是实现文件缓存的基本配置。

```
fs.cache.enabled=true
fs.cache.directories=/tmp/cache/
fs.cache.preferred-hosts-count=10 # 集群大小决定了主机数量。我们建议保持主机数量较小以维持最佳性能。
```

:::note
为缓存目录配置具有本地SSD存储的实例，以显著提高I/O速度和整体查询性能。
:::

</CollapsibleContent>
<CollapsibleContent header={<h2><span>计算、存储和网络最佳实践</span></h2>}>

<CollapsibleContent header={<span><h2>计算最佳实践</h2></span>}>

## 计算选择

Amazon Elastic Compute Cloud (EC2)通过其实例系列和处理器提供多样化的计算选项，包括标准、计算优化、内存优化和I/O优化配置。您可以通过[灵活的定价模型](https://aws.amazon.com/ec2/pricing/)购买这些实例：按需、计算节省计划、预留或竞价实例。选择适当的实例类型可以优化您的成本，最大化性能，并支持可持续性目标。EKS使您能够将这些计算资源精确匹配到您的工作负载需求。特别是对于Trino分布式集群，您的计算选择直接影响集群性能。

:::tip[关键建议]
:::
- 使用[AWS Graviton基础实例](https://aws.amazon.com/ec2/graviton/)：Graviton实例降低了实例成本，同时提高了性能，它还有助于实现可持续性目标
- 使用Karpenter：为了更好地扩展和简化Trino集群的管理，优先使用Karpenter。
- 多样化竞价实例以最大化您的节约。[更多详情可在EC2竞价最佳实践中找到](https://aws.amazon.com/blogs/compute/best-practices-to-optimize-your-amazon-ec2-spot-instances-usage/)。将[容错执行](http://localhost:3000/data-on-eks/docs/blueprints/distributed-databases/trino#example-3-optional-fault-tolerant-execution-in-trino)与EC2竞价实例一起使用

</CollapsibleContent>

<CollapsibleContent header={<span><h2>网络最佳实践</h2></span>}>

## 网络规划

Trino在pod之间的分布式特性需要实施网络最佳实践以确保最佳性能。正确的实施可以提高弹性，防止IP耗尽，减少pod初始化错误，并最小化延迟。Pod网络构成了Kubernetes操作的核心。Amazon EKS使用VPC CNI插件，在底层模式下运行，其中pod和主机共享网络层。这确保了集群和VPC环境中一致的IP寻址。

### VPC CNI附加组件
Amazon VPC CNI插件可以自定义以高效管理IP地址分配。默认情况下，Amazon VPC CNI为每个节点分配两个弹性网络接口(ENI)。这些ENI保留了大量IP地址，特别是在较大的实例类型上。由于Trino通常每个节点只需要一个pod加上几个用于DaemonSet pod（用于日志记录和网络）的IP地址，您可以配置CNI以限制IP地址分配并减少开销。

以下VPC CNI附加组件设置可以使用EKS API、Terraform或任何其他基础设施即代码(IaC)工具应用。有关更深入的详细信息，请参阅官方文档：VPC CNI前缀和IP目标。

### 配置VPC CNI附加组件

通过调整配置以仅分配所需数量的IP来限制每个节点的IP地址：
- MINIMUM_IP_TARGET：将此设置为每个节点的预期pod数量（例如，30）。
- WARM_IP_TARGET：设置为1以保持预热IP池最小。
- ENABLE_PREFIX_DELEGATION：通过向工作节点分配IP前缀而不是单个辅助IP地址来提高IP地址效率。这种方法通过利用更小、更集中的IP地址池来减少VPC内的网络地址使用(NAU)。

#### VPC CNI配置示例

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
<b>启用前缀委托：</b> VPC CNI插件支持前缀委托，它为每个节点分配16个IPv4地址的块（/28前缀）。此功能减少了每个节点所需的ENI数量。通过使用前缀委托，您可以降低EC2网络地址使用(NAU)，减少网络管理复杂性，并降低运营成本。

#### 有关网络的更多最佳实践，[请参阅我们的网络指南](../networking/networking.md)

</CollapsibleContent>

<CollapsibleContent header={<span><h2>存储最佳实践</h2></span>}>

本节重点介绍AWS服务，用于在EKS上使用Trino进行最佳存储管理。

## Amazon S3作为主要存储

- 对Trino查询中频繁访问的数据使用S3标准存储
- 对具有不同访问模式的数据实施S3智能分层
- 为静态数据启用S3服务器端加密（SSE-S3或SSE-KMS）
- 配置适当的存储桶策略并通过IAM角色进行访问
- 战略性地使用S3存储桶前缀以提高查询性能
- 将Trino与S3 Select一起使用以提高查询性能
-

### 协调器和工作节点的EBS存储

- 使用gp3 EBS卷以获得更好的性能/成本比
- 使用KMS启用EBS加密
- 根据溢出目录需求调整EBS卷大小
- 考虑使用EBS快照进行备份策略

### 性能优化

- 对特定工作负载实施S3 Select以提高查询性能
- 对大型数据集使用AWS分区索引
- 在CloudWatch中启用S3请求指标进行监控
- 为gp3卷配置适当的读/写IOPS
- 使用S3前缀有效地分区数据

### 数据生命周期管理

- 实施S3生命周期策略进行自动数据管理
- 适当使用S3存储类：
    - 标准用于热数据
    - 智能分层用于可变访问模式
    - 标准-IA用于不太频繁访问的数据
- 为关键数据集配置版本控制

### 成本优化

- 使用S3存储类分析优化存储成本
- 监控和优化S3请求模式
- 实施S3生命周期策略将较旧的数据移至更便宜的存储层
- 使用成本浏览器跟踪存储支出

### 安全和合规

- 实施VPC端点进行S3访问
- 使用AWS KMS进行加密密钥管理
- 启用S3访问日志进行审计
- 配置适当的IAM角色和策略
- 启用AWS CloudTrail进行API活动监控

:::note
请记住根据您的特定工作负载特性和需求调整这些实践。
:::

#### 有关S3相关最佳实践的详细了解，[请参阅Trino与Amazon S3的最佳实践](https://trino.io/assets/blog/trino-fest-2024/aws-s3.pdf)

</CollapsibleContent>

</CollapsibleContent>
<CollapsibleContent header={<span><h2>配置Trino连接器</h2></span>}>
Trino通过称为连接器的专用适配器连接到数据源。Hive和Iceberg连接器使Trino能够读取列式文件格式，如Parquet和ORC（优化行列式）。正确的连接器配置确保最佳查询性能和系统兼容性。

:::tip[关键建议]
:::
- **隔离**：为不同的数据源或环境使用单独的目录
- **安全**：实施适当的身份验证和授权机制
- **性能**：根据数据格式和查询模式优化连接器设置
- **资源管理**：调整内存和CPU设置以匹配每个连接器的工作负载需求

在Amazon EKS上将Trino与Hive和Iceberg等文件格式集成需要仔细配置并遵循最佳实践。正确设置连接器并优化资源分配以确保数据访问效率。微调查询性能设置以实现高可扩展性，同时保持低成本。这些步骤对于最大化Trino在EKS上的功能至关重要。根据您的特定工作负载定制配置，关注数据量和查询复杂性等因素。持续监控系统性能并根据需要调整设置以保持最佳结果。

<CollapsibleContent header={<span><h2>Hive</h2></span>}>

## Hive连接器配置

Hive连接器允许Trino查询存储在Hive数据仓库中的数据，通常使用存储在HDFS或Amazon S3上的Parquet、ORC或Avro等文件格式。

### Hive配置参数

- **连接器名称**：`hive`
- **元存储**：使用AWS Glue数据目录作为元存储。
- **文件格式**：支持Parquet、ORC、Avro等。
- **S3集成**：配置S3权限进行数据访问。

### Hive目录配置示例

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
### 元存储配置

- 使用AWS Glue作为Hive元存储以实现可扩展性和易于管理
- 设置`hive.metastore=glue`并指定区域

### 身份验证

- 使用IAM角色（`hive.s3.iam-role`）安全访问S3
- 确保IAM角色具有必要的最低权限

### 性能优化

- **Parquet和ORC**：使用列式文件格式如Parquet或ORC以获得更好的压缩和查询性能
- **分区**：基于经常过滤的列对表进行分区，以减少查询扫描时间
- **缓存**：
  - 启用元数据缓存，使用`hive.metastore-cache-ttl`减少元存储调用
  - 配置`hive.file-status-cache-size`和`hive.file-status-cache-ttl`进行文件状态缓存

### 数据压缩

- 为存储在S3中的数据启用压缩，以减少存储成本并提高I/O性能

### 安全考虑

- **加密**：对S3中的静态数据使用服务器端加密(SSE)或客户端加密

- **访问控制**：如有必要，使用Ranger或AWS Lake Formation实施细粒度访问控制

- **SSL/TLS** 确保`hive.s3.ssl.enabled=true`以加密传输中的数据
</CollapsibleContent>

<CollapsibleContent header={<span><h2>Iceberg</h2></span>}>

## Iceberg连接器配置
Iceberg连接器允许Trino与存储在Apache Iceberg表中的数据交互，这些表专为大型分析数据集设计，支持模式演化和隐藏分区等功能。

### 配置参数

- **连接器名称**：iceberg
- **目录类型**：使用AWS Glue或Hive元存储
- **文件格式**：Parquet、ORC或Avro
- **S3集成**：配置与Hive连接器类似的S3设置

### Iceberg目录配置示例

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
- 使用AWS Glue作为集中式模式管理的目录
- 设置`iceberg.catalog.type=glue`并指定区域
- 使用Iceberg REST目录协议
 `iceberg.catalog.type=rest`
  `iceberg.rest-catalog.uri=https://iceberg-with-rest:8181/'`

####   文件格式
- 使用Parquet或ORC以获得最佳性能
- 设置`iceberg.file-format=PARQUET`

#### 模式演化
- Iceberg支持无需重写表的模式演化
- 确保`iceberg.register-table-procedure.enabled=true`以允许表注册

#### 分区
- 利用Iceberg的隐藏分区功能简化查询语法并提高性能

#### 身份验证
- 使用IAM角色安全访问S3和Glue
- 确保角色具有Iceberg操作所需的权限

### 性能优化

#### 快照管理
- 定期过期旧快照以防止性能下降
- 使用`iceberg.expire-snapshots.min-snapshots-to-keep`和`iceberg.expire-snapshots.max-ref-age`设置

#### 元数据缓存
- 启用缓存以减少对元存储的调用
- 调整`iceberg.catalog.cache-ttl`以设置缓存持续时间

#### 并行性
- 配置拆分大小和并行性设置以优化读取性能
- 调整`iceberg.max-partitions-per-scan`和`iceberg.max-splits-per-node`

### 安全考虑

#### 数据加密
- 实施静态和传输中的加密

#### 访问控制
- 使用IAM策略应用细粒度权限

#### 合规性
- 使用模式演化功能时确保符合数据治理策略

</CollapsibleContent>
</CollapsibleContent>

<CollapsibleContent header={<span><h2>大规模查询优化</h2></span>}>

## 指南

下面是Trino中优化大规模查询的通用指南。有关更多详细信息，请参阅[查询优化器](https://trino.io/docs/current/optimizer.html)

### 内存管理
- 确保从容器到查询级别的适当分配
- 启用内存溢出并优化阈值

### 查询优化
- 增加initialHashPartitions以获得更好的并行性
- 使用自动连接分布和重新排序
- 优化拆分批次大小以实现高效处理

### 资源管理
- 强制每个节点一个pod以最大化资源利用
- 分配足够的CPU，同时为系统进程保留资源
- 优化垃圾收集设置

### 交换管理
- 使用S3并优化设置进行交换数据
- 增加并发连接并调整上传部分大小

:::tip[关键建议]
:::
- **监控**：使用Prometheus和Grafana等工具进行实时指标监控
- **测试**：在生产前模拟工作负载/运行POC以验证配置
- **实例选择**：考虑最新一代Graviton实例（Graviton3、Graviton4）以提高价格性能比。
- **网络带宽**：确保实例提供足够的网络带宽以防止瓶颈

</CollapsibleContent>
