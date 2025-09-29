---
sidebar_position: 3
sidebar_label: 用于 Spark 工作负载的 Mountpoint-S3
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../src/components/CollapsibleContent';

import CodeBlock from '@theme/CodeBlock';
import DaemonSetWithConfig from '!!raw-loader!../../../../../../analytics/terraform/spark-k8s-operator/examples/mountpoint-s3-spark/mountpoint-s3-daemonset.yaml';

# 用于 Spark 工作负载的 Mountpoint-S3
在使用由 [SparkOperator](https://github.com/kubeflow/spark-operator) 管理的 [SparkApplication](https://www.kubeflow.org/docs/components/spark-operator/user-guide/using-sparkapplication/) 自定义资源定义 (CRD) 时，处理多个依赖 JAR 文件可能成为一个重大挑战。传统上，这些 JAR 文件被打包在容器镜像中，导致几个低效问题：

* **增加构建时间：** 在构建过程中下载和添加 JAR 文件显著增加了容器镜像的构建时间。
* **更大的镜像大小：** 直接在容器镜像中包含 JAR 文件会增加其大小，导致在拉取镜像执行作业时下载时间更长。
* **频繁重建：** 对依赖 JAR 文件的任何更新或添加都需要重建和重新部署容器镜像，进一步增加运营开销。

[Mountpoint for Amazon S3](https://aws.amazon.com/s3/features/mountpoint/) 为这些挑战提供了有效的解决方案。作为开源文件客户端，Mountpoint-S3 允许您在计算实例上挂载 S3 存储桶，使其作为本地虚拟文件系统可访问。它自动将本地文件系统 API 调用转换为 S3 对象上的 REST API 调用，为 Spark 作业提供无缝集成。

## 什么是 Mountpoint-S3？

[Mountpoint-S3](https://github.com/awslabs/mountpoint-s3) 是 AWS 开发的开源文件客户端，它将文件操作转换为 S3 API 调用，使您的应用程序能够像访问本地磁盘一样与 [Amazon S3](https://aws.amazon.com/s3/) 存储桶交互。[Mountpoint for Amazon S3](https://aws.amazon.com/s3/features/mountpoint/) 针对需要对大型对象进行高读取吞吐量的应用程序进行了优化，可能同时来自多个客户端，并且一次从单个客户端顺序写入新对象。与传统的 S3 访问方法相比，它提供了显著的性能提升，使其成为数据密集型工作负载或 AI/ML 训练的理想选择。

[Mountpoint for Amazon S3](https://aws.amazon.com/s3/features/mountpoint/) 针对高吞吐量性能进行了优化，这主要归功于其基于 [AWS Common Runtime (CRT)](https://docs.aws.amazon.com/sdkref/latest/guide/common-runtime.html) 库的基础。CRT 库是专为提供高性能和低资源使用而设计的库和模块集合，专门为 AWS 服务量身定制。CRT 库实现高吞吐量性能的关键特性包括：

 * **高效的 I/O 管理：** CRT 库针对非阻塞 I/O 操作进行了优化，减少延迟并最大化网络带宽的利用。
 * **轻量级和模块化设计：** 该库设计为轻量级，开销最小，即使在高负载下也能高效执行。其模块化架构确保只加载必要的组件，进一步提高性能。
 * **高级内存管理：** CRT 采用高级内存管理技术来最小化内存使用并减少垃圾收集开销，从而实现更快的数据处理和减少延迟。
 * **优化的网络协议：** CRT 库包括专门为 AWS 环境调优的网络协议（如 HTTP/2）的优化实现。这些优化确保 S3 和您的计算实例之间的快速数据传输，这对于大规模 Spark 工作负载至关重要。

## 在 EKS 中使用 Mountpoint-S3
对于 Spark 工作负载，我们将专门关注**为 Spark 应用程序加载位于 S3 中的外部 JAR**。我们将检查 Mountpoint-S3 的两种主要部署策略：
1. 利用 [EKS 托管插件 CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html) 与持久卷 (PV) 和持久卷声明 (PVC)
2. 使用 [USERDATA](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html) 脚本或 DaemonSet 在节点级别部署 Mountpoint-S3。

第一种方法被认为是在 *Pod* 级别挂载，因为创建的 PV 可供单个 Pod 使用。第二种方法被认为是在 *节点* 级别挂载，因为 S3 挂载在主机节点本身上。下面详细讨论每种方法，突出它们各自的优势和考虑因素，以帮助您确定适合您特定用例的最有效解决方案。

| 指标              | Pod 级别 | 节点级别 |
| :----------------: | :------ | :---- |
| 访问控制            |   通过服务角色和 RBAC 提供细粒度访问控制，限制特定 Pod 对 PVC 的访问。这在主机级别挂载中是不可能的，其中挂载的 S3 存储桶可供节点上的所有 Pod 访问。   | 简化配置但缺乏 Pod 级别挂载提供的细粒度控制。 |
| 可扩展性和开销 |   涉及管理单个 PVC，这可能会在大规模环境中增加开销。   | 减少配置复杂性但在 Pod 之间提供较少隔离。 |
| 性能考虑|  为单个 Pod 提供可预测和隔离的性能。   | 如果同一节点上的多个 Pod 访问同一 S3 存储桶，可能导致争用。 |
| 灵活性和用例 |  最适合不同 Pod 需要访问不同数据集或需要严格安全和合规控制的用例。   | 适用于节点上所有 Pod 可以共享相同数据集的环境，例如运行批处理作业或需要公共依赖项的 Spark 作业时。 |

## 资源分配
在能够实施提供的 Mountpoint-s3 解决方案之前，需要分配 AWS 云资源。要部署 Terraform 堆栈，请按照以下说明操作。分配资源并设置 EKS 环境后，您可以详细探索利用 Mountpoint-S3 的两种不同方法。

<CollapsibleContent header={<h2><span>部署解决方案资源</span></h2>}>

在此[示例](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/spark-k8s-operator)中，您将配置运行带有开源 Spark Operator 的 Spark 作业所需的以下资源。

此示例将运行 Spark K8s Operator 的 EKS 集群部署到新的 VPC 中。

- 创建新的示例 VPC、2 个私有子网和 2 个公有子网
- 为公有子网创建互联网网关，为私有子网创建 NAT 网关
- 创建具有公共端点的 EKS 集群控制平面（仅用于演示目的），具有核心托管节点组、按需节点组和用于 Spark 工作负载的 Spot 节点组。
- 部署 Metrics server、Cluster Autoscaler、Spark-k8s-operator、Apache Yunikorn、Karpenter、Grafana、AMP 和 Prometheus server。

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

如果 DOEKS_HOME 被取消设置，您始终可以从 data-on-eks 目录使用 `export DATA_ON_EKS=$(pwd)` 手动设置它。

导航到示例目录之一并运行 `install.sh` 脚本。

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator
chmod +x install.sh
./install.sh
```

现在创建一个 S3_BUCKET 变量，该变量保存在安装期间创建的存储桶的名称。此存储桶将在后续示例中用于存储输出数据。如果 S3_BUCKET 被取消设置，您可以再次运行以下命令。

```bash
export S3_BUCKET=$(terraform output -raw s3_bucket_id_spark_history_server)
echo $S3_BUCKET
```

</CollapsibleContent>

## 方法 1：在 *Pod 级别*在 EKS 上部署 Mountpoint-S3

在 Pod 级别部署 Mountpoint-S3 涉及使用 [EKS 托管插件 CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html) 与持久卷 (PV) 和持久卷声明 (PVC) 直接在 Pod 内挂载 S3 存储桶。此方法允许对哪些 Pod 可以访问特定 S3 存储桶进行细粒度控制，确保只有必要的工作负载才能访问所需的数据。

一旦启用 [Mountpoint-S3](https://github.com/awslabs/mountpoint-s3) 并创建 PV，S3 存储桶就成为集群级别的资源，允许任何 Pod 通过创建引用 PV 的 PVC 来请求访问。要实现对哪些 Pod 可以访问特定 PVC 的细粒度控制，您可以在命名空间内使用服务角色。通过为 Pod 分配特定的服务账户并定义基于角色的访问控制 (RBAC) 策略，您可以限制哪些 Pod 可以绑定到某些 PVC。这确保只有授权的 Pod 可以挂载 S3 存储桶，与主机级别挂载相比提供更严格的安全性和访问控制，在主机级别挂载中，hostPath 可供节点上的所有 Pod 访问。

使用 [EKS 托管插件 CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html) 也可以简化此方法的使用。但是，这不支持污点/容忍，因此不能与 GPU 一起使用。此外，由于 Pod 不共享挂载，因此不共享缓存，这将导致更多的 S3 API 调用。

 有关如何部署此方法的更多信息，请参考[部署说明](https://awslabs.github.io/data-on-eks/docs/resources/mountpoint-s3)

## 方法 2：在 *节点级别*在 EKS 上部署 Mountpoint-S3

在节点级别挂载 S3 存储桶可以通过减少构建时间和加快部署来简化 SparkApplication 的依赖 JAR 文件管理。它可以使用 **USERDATA** 或 **DaemonSet** 来实现。USERDATA 是实施 [Mountpoint-S3](https://github.com/awslabs/mountpoint-s3) 的首选方法。但是，如果您的 EKS 集群中有无法关闭的静态节点，DaemonSet 方法提供了一个替代方案。在实施 DaemonSet 方法之前，请确保了解需要启用的所有安全机制。

### 方法 2.1：使用 USERDATA

此方法推荐用于新集群或自动扩展被定制为运行工作负载的情况，因为用户数据脚本在节点初始化时运行。使用以下脚本，可以更新节点以在托管 Pod 的 EKS 集群中初始化时挂载 S3 存储桶。以下脚本概述了下载、安装和运行 Mountpoint S3 包。为此应用程序设置了几个参数，定义如下，可以根据用例进行更改。有关这些参数和其他参数的更多信息可以在[这里](https://github.com/awslabs/mountpoint-s3/blob/main/doc/CONFIGURATION.md#caching-configuration)找到

* metadata-ttl：这设置为无限期，因为 jar 文件旨在用作只读且不会更改。
* allow-others：设置此项以便节点在使用 SSM 时可以访问挂载的卷
* cache：设置此项以启用缓存并通过将文件存储在缓存中以供连续重新读取来限制需要进行的 S3 API 调用。

:::note
这些相同的参数也可以在 DaemonSet 方法中使用。除了此示例设置的这些参数外，还有许多其他选项用于额外的[日志记录和调试](https://github.com/awslabs/mountpoint-s3/blob/main/doc/LOGGING.md)
:::

当使用 [Karpenter](https://karpenter.sh/) 进行自动扩展时，此方法允许更多的灵活性和性能。例如，在 terraform 代码中配置 Karpenter 时，不同类型节点的用户数据可以是唯一的，根据工作负载使用不同的存储桶，因此当调度 Pod 并需要某组依赖项时，污点和容忍将允许 Karpenter 分配具有唯一用户数据的特定实例类型，以确保在节点上挂载具有依赖文件的正确存储桶，以便 Pod 可以访问。此外，用户脚本将取决于新分配节点配置的操作系统。

#### USERDATA 脚本：

```
#!/bin/bash
yum update -y
yum install -y wget
wget https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.rpm
yum install -y mount-s3.rpm mkdir -p /mnt/s3
/opt/aws/mountpoint-s3/bin/mount-s3 --metadata-ttl indefinite --allow-other --cache /tmp <S3_BUCKET_NAME> /mnt/s3
```

### 方法 2.2：使用 DaemonSet

此方法推荐用于现有集群。此方法由 2 个资源组成，一个包含脚本的 ConfigMap，该脚本将 S3 Mount Point 包维护到节点上，以及一个 DaemonSet，它在集群中的每个节点上运行一个 Pod，该 Pod 将在节点上执行脚本。

ConfigMap 脚本将运行一个循环，每 60 秒检查一次挂载点，如果有任何问题则重新挂载。有多个环境变量可以更改挂载位置、缓存位置、S3 存储桶名称、日志文件位置以及包安装的 URL 和已安装包的位置。这些变量可以保留为默认值，因为只需要 S3 存储桶名称即可运行。

DaemonSet Pod 将脚本复制到节点上，更改权限以允许执行，然后最终运行脚本。Pod 安装 ```util-linux``` 以便访问 [nsenter](https://man7.org/linux/man-pages/man1/nsenter.1.html)，这允许 Pod 在节点空间中执行脚本，从而允许 Pod 直接将 S3 存储桶挂载到节点上。
:::danger
DaemonSet Pod 需要 ```securityContext``` 为特权模式，以及 ```hostPID```、```hostIPC``` 和 ```hostNetwork``` 设置为 true。
请查看下面为什么需要为此解决方案配置这些以及它们的安全影响。
:::
1. ```securityContext: privileged```
    * **目的：** 特权模式为容器提供对所有主机资源的完全访问权限，类似于主机上的 root 访问权限。
    * 要安装软件包、配置系统并将 S3 存储桶挂载到主机上，您的容器可能需要提升的权限。没有特权模式，容器可能没有足够的权限在主机文件系统和网络接口上执行这些操作。
2. hostPID
    * **目的：** nsenter 允许您进入各种命名空间，包括主机的 PID 命名空间。
    * 当使用 nsenter 进入主机的 PID 命名空间时，容器需要访问主机的 PID 命名空间。因此，启用 ```hostPID: true``` 对于与主机上的进程交互是必要的，这对于安装包或运行需要主机级别进程可见性（如 mountpoint-s3）的命令等操作至关重要。
3. hostIPC
    * **目的：** hostIPC 使您的容器能够共享主机的进程间通信命名空间，其中包括共享内存。
    * 如果 nsenter 命令或要运行的脚本涉及主机上的共享内存或其他 IPC 机制，则需要 ```hostIPC: true```。虽然它不如 hostPID 常见，但当涉及 nsenter 时通常与其一起启用，特别是如果脚本需要与依赖 IPC 的主机进程交互。
4. hostNetwork
    * **目的：** hostNetwork 允许容器使用主机的网络命名空间，为容器提供对主机 IP 地址和网络接口的访问。
    * 在安装过程中，脚本可能需要从互联网下载包（例如，从托管 mountpoint-s3 包的存储库）。通过使用 ```hostNetwork: true``` 启用 hostNetwork，您确保下载过程可以直接访问主机的网络接口，避免网络隔离问题。
:::warning
此示例代码使用 ```spark-team-a``` 命名空间来运行作业和托管 DaemonSet。这主要是因为 Terraform 堆栈已经为此命名空间设置了 [IRSA](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/setting-up-enable-IAM.html)，并允许服务账户访问任何 S3 存储桶。
在生产中使用时，请确保创建您自己的单独命名空间、服务账户和遵循最小权限策略并遵循 [IAM 角色最佳实践](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)的 IAM 角色
:::

<details>
<summary> 要查看 DaemonSet，请点击切换内容！</summary>

<CodeBlock language="yaml">{DaemonSetWithConfig}</CodeBlock>
</details>

## 执行 Spark 作业
以下是使用方法 2 与 DaemonSet 测试场景的步骤：

1. 部署 [Spark Operator 资源](#资源分配)
2. 准备 S3 存储桶
    1. ``` cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator/examples/mountpoint-s3-spark/ ```
    2. ``` chmod +x copy-jars-to-s3.sh ```
    3. ``` ./copy-jars-to-s3.sh ```
3. 设置 Kubeconfig
    1. ```aws eks update-kubeconfig --name spark-operator-doeks```
4. 应用 DaemonSet
    1. ```kubectl apply -f mountpoint-s3-daemonset.yaml ```
4. 应用 Spark 作业示例
    1. ```kubectl apply -f mountpoint-s3-spark-job.yaml ```
4. 查看作业运行
    * 当此 SparkApplication CRD 运行时，我们可以查看几个不同资源的日志。这些日志中的每一个都应该在单独的终端中同时查看所有日志。
        1. **spark operator**
            1. ``` kubectl -n spark-operator get pods```
            2. 复制 spark operator Pod 的名称
            2. ``` kubectl -n spark-operator logs -f <POD_NAME>```
        2. **spark-team-a Pod**
            1. 为了获取 SparkApplication 的 driver 和 exec Pod 的日志，我们需要首先验证 Pod 正在运行。使用宽输出，我们应该能够看到 Pod 运行的节点，使用 ```-w``` 我们可以看到每个 Pod 的状态更新。
            2. ``` kubectl -n spark-team-a get pods -o wide -w ```
        3. **driver Pod**
            1. 一旦 driver Pod 处于运行状态（在上一个终端中可见），我们就可以获取 driver Pod 的日志
            2. ``` kubectl -n spark-team-a logs -f taxi-trip ```
        4. **exec Pod**
            1. 一旦 exec Pod 处于运行状态（在上一个终端中可见），我们就可以获取 exec Pod 的日志。确保 exec-1 正在运行，否则使用处于运行状态的另一个 exec Pod。
            2. ``` kubectl -n spark-team-a logs -f taxi-trip-exec-1 ```

## 验证
作业运行完成后，您可以在 exec 日志中看到文件正在从节点上的本地 mountpoint-s3 位置复制到 spark Pod 以进行处理。
```
24/08/13 00:08:46 INFO Utils: Copying /mnt/s3/jars/hadoop-aws-3.3.1.jar to /var/data/spark-5eae56b3-3999-4c2f-8004-afc46d1c82ba/spark-a433e7ce-db5d-4fd5-b344-abf751f43bd3/-14716855631723507720806_cache
24/08/13 00:08:46 INFO Utils: Copying /var/data/spark-5eae56b3-3999-4c2f-8004-afc46d1c82ba/spark-a433e7ce-db5d-4fd5-b344-abf751f43bd3/-14716855631723507720806_cache to /opt/spark/work-dir/./hadoop-aws-3.3.1.jar
24/08/13 00:08:46 INFO Executor: Adding file:/opt/spark/work-dir/./hadoop-aws-3.1.jar to class loader
24/08/13 00:08:46 INFO Executor: Fetching file:/mnt/s3/jars/aws-java-sdk-bundle-1.12.647.jar with timestamp 1723507720806
24/08/13 00:08:46 INFO Utils: Copying /mnt/s3/jars/aws-java-sdk-bundle-1.12.647.jar to /var/data/spark-5eae56b3-3999-4c2f-8004-afc46d1c82ba/spark-a433e7ce-db5d-4fd5-b344-abf751f43bd3/14156613201723507720806_cache
24/08/13 00:08:47 INFO Utils: Copying /var/data/spark-5eae56b3-3999-4c2f-8004-afc46d1c82ba/spark-a433e7ce-db5d-4fd5-b344-abf751f43bd3/14156613201723507720806_cache to /opt/spark/work-dir/./aws-java-sdk-bundle-1.12.647.jar
```
此外，在查看 spark-team-a Pod 的状态时，您会注意到另一个节点上线，此节点经过优化以运行 SparkApplication，一旦它上线，DaemonSet Pod 也会启动并开始在新节点上运行，以便在该新节点上运行的任何 Pod 也可以访问 S3 存储桶。使用系统会话管理器 (SSM)，您可以连接任何节点并通过运行以下命令验证 mountpoint-s3 包已下载并安装：
* ```mount-s3 --version```

在节点级别为多个 Pod 使用 mountpoint-S3 的最大优势是数据可以被缓存，以允许其他 Pod 访问相同的数据而无需进行自己的 API 调用。一旦分配了 *karpenter-spark-compute-optimized* 优化节点，您可以使用会话管理器 (SSM) 连接到节点并验证当作业运行并挂载卷时文件将在节点上缓存。您可以在以下位置查看缓存：
* ```sudo ls /tmp/mountpoint-cache/```

## 结论

通过利用 CRT 库，Mountpoint for Amazon S3 可以提供高效管理和访问存储在 S3 中的大量数据所需的高吞吐量和低延迟。这允许依赖 JAR 文件从容器镜像外部存储和管理，将它们与 Spark 作业解耦。此外，将 JAR 存储在 S3 中使多个 Pod 能够使用它们，从而节省成本，因为与更大的容器镜像相比，S3 提供了经济高效的存储解决方案。S3 还提供几乎无限的存储，使扩展和管理依赖项变得容易。

Mountpoint-S3 为将 S3 存储与 EKS 集成用于数据和 AI/ML 工作负载提供了一种多功能且强大的方式。无论您选择使用 PV 和 PVC 在 Pod 级别部署它，还是使用 USERDATA 或 DaemonSet 在节点级别部署它，每种方法都有其自己的优势和权衡。通过了解这些选项，您可以做出明智的决策来优化 EKS 上的数据和 AI/ML 工作流程。
