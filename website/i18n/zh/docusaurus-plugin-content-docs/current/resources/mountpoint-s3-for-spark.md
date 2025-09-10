---
sidebar_position: 3
sidebar_label: Spark 工作负载的 Mountpoint-S3
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../src/components/CollapsibleContent';

import CodeBlock from '@theme/CodeBlock';

# Spark 工作负载的 Mountpoint-S3
在使用由 [SparkOperator](https://github.com/kubeflow/spark-operator) 管理的 [SparkApplication](https://www.kubeflow.org/docs/components/spark-operator/user-guide/using-sparkapplication/) 自定义资源定义 (CRD) 时，处理多个依赖 JAR 文件可能成为一个重大挑战。传统上，这些 JAR 文件被打包在容器镜像中，导致几个低效问题：

* **增加构建时间：** 在构建过程中下载和添加 JAR 文件会显著增加容器镜像的构建时间。
* **更大的镜像大小：** 直接在容器镜像中包含 JAR 文件会增加其大小，导致在拉取镜像执行作业时下载时间更长。
* **频繁重建：** 对依赖 JAR 文件的任何更新或添加都需要重建和重新部署容器镜像，进一步增加操作开销。

[Mountpoint for Amazon S3](https://aws.amazon.com/s3/features/mountpoint/) 为这些挑战提供了有效的解决方案。作为开源文件客户端，Mountpoint-S3 允许您在计算实例上挂载 S3 存储桶，使其作为本地虚拟文件系统可访问。它自动将本地文件系统 API 调用转换为 S3 对象上的 REST API 调用，为 Spark 作业提供无缝集成。

## 什么是 Mountpoint-S3？

[Mountpoint-S3](https://github.com/awslabs/mountpoint-s3) 是 AWS 开发的开源文件客户端，它将文件操作转换为 S3 API 调用，使您的应用程序能够像访问本地磁盘一样与 [Amazon S3](https://aws.amazon.com/s3/) 存储桶交互。[Mountpoint for Amazon S3](https://aws.amazon.com/s3/features/mountpoint/) 针对需要对大对象进行高读取吞吐量的应用程序进行了优化，可能同时来自多个客户端，并且一次从单个客户端顺序写入新对象。与传统的 S3 访问方法相比，它提供了显著的性能提升，使其成为数据密集型工作负载或 AI/ML 训练的理想选择。

[Mountpoint for Amazon S3](https://aws.amazon.com/s3/features/mountpoint/) 针对高吞吐量性能进行了优化，这主要归功于其基于 [AWS Common Runtime (CRT)](https://docs.aws.amazon.com/sdkref/latest/guide/common-runtime.html) 库的基础。CRT 库是专为提供高性能和低资源使用而设计的库和模块集合，专门为 AWS 服务量身定制。CRT 库实现高吞吐量性能的关键功能包括：

 * **高效的 I/O 管理：** CRT 库针对非阻塞 I/O 操作进行了优化，减少延迟并最大化网络带宽的利用率。
 * **轻量级和模块化设计：** 该库设计为轻量级，开销最小，即使在高负载下也能高效执行。其模块化架构确保只加载必要的组件，进一步提高性能。
 * **高级内存管理：** CRT 采用高级内存管理技术来最小化内存使用并减少垃圾收集开销，从而实现更快的数据处理和减少延迟。
 * **优化的网络协议：** CRT 库包括网络协议的优化实现，如 HTTP/2，专门为 AWS 环境调优。这些优化确保 S3 和您的计算实例之间的快速数据传输，这对于大规模 Spark 工作负载至关重要。

## 在 EKS 中使用 Mountpoint-S3
对于 Spark 工作负载，我们将专门关注**为 Spark 应用程序加载位于 S3 中的外部 JAR**。我们将检查 Mountpoint-S3 的两种主要部署策略：

1. 利用 [EKS 托管附加组件 CSI 驱动程序](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)与持久卷 (PV) 和持久卷声明 (PVC)
2. 使用 [USERDATA](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html) 脚本或 DaemonSet 在节点级别部署 Mountpoint-S3。

第一种方法被认为是在 *Pod* 级别挂载，因为创建的 PV 可供单个 Pod 使用。第二种方法被认为是在 *节点* 级别挂载，因为 S3 挂载在主机节点本身上。下面详细讨论每种方法，突出它们各自的优势和考虑因素，以帮助您确定最适合您特定用例的解决方案。

| 指标              | Pod 级别 | 节点级别 |
| :----------------: | :------ | :---- |
| 访问控制            |   通过服务角色和 RBAC 提供细粒度访问控制，将 PVC 访问限制为特定 Pod。这在主机级别挂载中是不可能的，其中挂载的 S3 存储桶可供节点上的所有 Pod 访问。   | 简化配置但缺乏 Pod 级别挂载提供的细粒度控制。 |
| 可扩展性和开销 |   涉及管理单个 PVC，这可能会在大规模环境中增加开销。   | 减少配置复杂性但在 Pod 之间提供较少的隔离。 |
| 性能考虑|  为单个 Pod 提供可预测和隔离的性能。   | 如果同一节点上的多个 Pod 访问同一 S3 存储桶，可能导致争用。 |
| 灵活性和用例 |  最适合不同 Pod 需要访问不同数据集或需要严格安全和合规控制的用例。   | 适用于节点上所有 Pod 可以共享相同数据集的环境，例如运行批处理作业或需要通用依赖项的 Spark 作业时。 |

## 资源分配
在能够实施提供的 Mountpoint-s3 解决方案之前，需要分配 AWS 云资源。要部署 Terraform 堆栈，请按照以下说明操作。分配资源并设置 EKS 环境后，您可以详细探索利用 Mountpoint-S3 的两种不同方法。

<CollapsibleContent header={<h2><span>部署解决方案资源</span></h2>}>

</CollapsibleContent>
