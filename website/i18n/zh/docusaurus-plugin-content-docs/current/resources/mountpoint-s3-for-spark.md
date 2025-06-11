---
sidebar_position: 3
sidebar_label: 用于Spark工作负载的Mounpoint-S3
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../src/components/CollapsibleContent';

import CodeBlock from '@theme/CodeBlock';
import DaemonSetWithConfig from '!!raw-loader!../../../../../../analytics/terraform/spark-k8s-operator/examples/mountpoint-s3-spark/mountpoint-s3-daemonset.yaml';

# 用于Spark工作负载的Mountpoint-S3
在使用由[SparkOperator](https://github.com/kubeflow/spark-operator)管理的[SparkApplication](https://www.kubeflow.org/docs/components/spark-operator/user-guide/using-sparkapplication/)自定义资源定义(CRD)时，处理多个依赖JAR文件可能成为一个重大挑战。传统上，这些JAR文件被捆绑在容器镜像中，导致几个效率低下的问题：

* **增加构建时间：** 在构建过程中下载和添加JAR文件显著增加了容器镜像的构建时间。
* **更大的镜像大小：** 直接在容器镜像中包含JAR文件增加了其大小，导致在拉取镜像执行作业时下载时间更长。
* **频繁重建：** 对依赖JAR文件的任何更新或添加都需要重建和重新部署容器镜像，进一步增加了运营开销。

[Mountpoint for Amazon S3](https://aws.amazon.com/s3/features/mountpoint/)为这些挑战提供了一个有效的解决方案。作为一个开源文件客户端，Mountpoint-S3允许您在计算实例上挂载S3存储桶，使其作为本地虚拟文件系统可访问。它自动将本地文件系统API调用转换为S3对象上的REST API调用，提供与Spark作业的无缝集成。

## 什么是Mountpoint-S3？

[Mountpoint-S3](https://github.com/awslabs/mountpoint-s3)是由AWS开发的开源文件客户端，它将文件操作转换为S3 API调用，使您的应用程序能够与[Amazon S3](https://aws.amazon.com/s3/)存储桶交互，就像它们是本地磁盘一样。[Mountpoint for Amazon S3](https://aws.amazon.com/s3/features/mountpoint/)针对需要对大型对象进行高读取吞吐量的应用程序进行了优化，可能同时来自多个客户端，并且可以一次从单个客户端顺序写入新对象。与传统的S3访问方法相比，它提供了显著的性能提升，使其非常适合数据密集型工作负载或AI/ML训练。

[Mountpoint for Amazon S3](https://aws.amazon.com/s3/features/mountpoint/)针对高吞吐量性能进行了优化，这在很大程度上归功于其基于[AWS Common Runtime (CRT)](https://docs.aws.amazon.com/sdkref/latest/guide/common-runtime.html)库的基础。CRT库是一系列库和模块的集合，旨在提供高性能和低资源使用率，专门为AWS服务量身定制。CRT库使高吞吐量性能成为可能的关键特性包括：

 * **高效的I/O管理：** CRT库针对非阻塞I/O操作进行了优化，减少延迟并最大化网络带宽的利用率。
 * **轻量级和模块化设计：** 该库设计为轻量级，具有最小的开销，使其即使在高负载下也能高效运行。其模块化架构确保只加载必要的组件，进一步增强性能。
 * **高级内存管理：** CRT采用高级内存管理技术，最小化内存使用并减少垃圾收集开销，导致更快的数据处理和减少延迟。
 * **优化的网络协议：** CRT库包括网络协议的优化实现，如HTTP/2，专门针对AWS环境进行调整。这些优化确保S3和您的计算实例之间的快速数据传输，这对于大规模Spark工作负载至关重要。
## 在EKS上使用Mountpoint-S3
对于Spark工作负载，我们将特别关注**为Spark应用程序加载位于S3中的外部JAR**。我们将研究Mountpoint-S3的两种主要部署策略；
1. 利用[EKS托管附加组件CSI驱动程序](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)与持久卷(PV)和持久卷声明(PVC)
2. 使用[USERDATA](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html)脚本或DaemonSet在节点级别部署Mountpoint-S3。

第一种方法被视为在*Pod*级别挂载，因为创建的PV可供单个pod使用。第二种方法被视为在*节点*级别挂载，因为S3挂载在主机节点本身上。下面详细讨论了每种方法，突出了它们各自的优势和考虑因素，以帮助您确定最适合您特定用例的有效解决方案。

| 指标              | Pod级别 | 节点级别 |
| :----------------: | :------ | :---- |
| 访问控制            |   通过服务角色和RBAC提供细粒度访问控制，限制特定Pod对PVC的访问。这在主机级别挂载中是不可能的，在那里挂载的S3存储桶可供节点上的所有Pod访问。   | 简化配置但缺乏Pod级别挂载提供的细粒度控制。 |
| 可扩展性和开销 |   涉及管理单个PVC，这可能会增加大规模环境中的开销。   | 减少配置复杂性但在Pod之间提供较少的隔离。 |
| 性能考虑|  为单个Pod提供可预测和隔离的性能。   | 如果同一节点上的多个Pod访问同一S3存储桶，可能导致争用。 |
| 灵活性和用例 |  最适合不同Pod需要访问不同数据集或需要严格安全和合规控制的用例。   | 适合节点上所有Pod可以共享相同数据集的环境，例如运行批处理作业或需要共同依赖项的Spark作业。 |

## 资源分配
在能够实施提供的Mountpoint-s3解决方案之前，需要分配AWS云资源。要部署Terraform堆栈，请按照以下说明操作。分配资源并设置EKS环境后，您可以详细探索利用Mountpoint-S3的两种不同方法。

<CollapsibleContent header={<h2><span>部署解决方案资源</span></h2>}>

在这个[示例](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/spark-k8s-operator)中，您将配置以下资源，这些资源是使用开源Spark操作符运行Spark作业所必需的。

此示例将运行Spark K8s操作符的EKS集群部署到新的VPC中。

- 创建一个新的示例VPC、2个私有子网和2个公共子网
- 为公共子网创建互联网网关，为私有子网创建NAT网关
- 创建带有公共端点的EKS集群控制平面（仅用于演示目的），带有核心托管节点组、按需节点组和用于Spark工作负载的Spot节点组。
- 部署Metrics server、Cluster Autoscaler、Spark-k8s-operator、Apache Yunikorn、Karpenter、Grafana、AMP和Prometheus服务器。

### 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### 部署

克隆仓库。

```bash
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks
export DOEKS_HOME=$(pwd)
```

如果DOEKS_HOME变量被取消设置，您可以随时使用`export
DATA_ON_EKS=$(pwd)`从data-on-eks目录手动设置它。

导航到其中一个示例目录并运行`install.sh`脚本。

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator
chmod +x install.sh
./install.sh
```

现在创建一个S3_BUCKET变量，保存安装期间创建的存储桶名称。此存储桶将在后续示例中用于存储输出数据。如果S3_BUCKET变量被取消设置，您可以再次运行以下命令。

```bash
export S3_BUCKET=$(terraform output -raw s3_bucket_id_spark_history_server)
echo $S3_BUCKET
```

</CollapsibleContent>
## 方法1：在*Pod级别*在EKS上部署Mountpoint-S3

在Pod级别部署Mountpoint-S3涉及使用[EKS托管附加组件CSI驱动程序](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)与持久卷(PV)和持久卷声明(PVC)直接在Pod内挂载S3存储桶。此方法允许对哪些Pod可以访问特定S3存储桶进行细粒度控制，确保只有必要的工作负载可以访问所需的数据。

一旦启用[Mountpoint-S3](https://github.com/awslabs/mountpoint-s3)并创建PV，S3存储桶就成为集群级别资源，允许任何Pod通过创建引用PV的PVC请求访问。要实现对哪些Pod可以访问特定PVC的细粒度控制，您可以使用命名空间内的服务角色。通过将特定服务账户分配给Pod并定义基于角色的访问控制(RBAC)策略，您可以限制哪些Pod可以绑定到某些PVC。这确保只有授权的Pod可以挂载S3存储桶，与主机级别挂载相比提供更严格的安全性和访问控制，在主机级别挂载中，hostPath可供节点上的所有Pod访问。

使用此方法也可以通过使用[EKS托管附加组件CSI驱动程序](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)来简化。但是，这不支持污点/容忍，因此不能与GPU一起使用。此外，由于Pod不共享挂载，因此不共享缓存，这将导致更多的S3 API调用。

 有关如何部署此方法的更多信息，请参阅[部署说明](https://awslabs.github.io/data-on-eks/docs/resources/mountpoint-s3)

## 方法2：在*节点级别*在EKS上部署Mountpoint-S3

在节点级别挂载S3存储桶可以通过减少构建时间和加快部署来简化SparkApplications的依赖JAR文件管理。它可以使用**USERDATA**或**DaemonSet**实现。USERDATA是实施[Mountpoint-S3](https://github.com/awslabs/mountpoint-s3)的首选方法。但是，如果您的EKS集群中有无法关闭的静态节点，DaemonSet方法提供了一种替代方案。在实施DaemonSet方法之前，请确保了解需要启用的所有安全机制。

### 方法2.1：使用USERDATA

此方法推荐用于新集群或自定义自动扩展以运行工作负载的情况，因为用户数据脚本在节点初始化时运行。使用以下脚本，可以更新节点，使其在托管Pod的EKS集群中初始化时挂载S3存储桶。以下脚本概述了下载、安装和运行Mountpoint S3包。为此应用程序设置了几个参数，如下所述，可以根据用例进行更改。有关这些参数和其他参数的更多信息可以在[这里](https://github.com/awslabs/mountpoint-s3/blob/main/doc/CONFIGURATION.md#caching-configuration)找到

* metadata-ttl：这设置为无限期，因为jar文件旨在用作只读文件，不会更改。
* allow-others：这设置为使节点在使用SSM时可以访问挂载的卷
* cache：这设置为启用缓存并限制需要进行的S3 API调用，通过将文件存储在缓存中以供连续重新读取。

:::note
这些相同的参数也可以在DaemonSet方法中使用。除了此示例设置的这些参数外，还有许多其他选项用于额外的[日志记录和调试](https://github.com/awslabs/mountpoint-s3/blob/main/doc/LOGGING.md)
:::

使用[Karpenter](https://karpenter.sh/)进行自动扩展时，此方法允许更大的灵活性和性能。例如，在terraform代码中配置Karpenter时，不同类型节点的用户数据可以是唯一的，具有不同的存储桶，这取决于工作负载，因此当Pod被调度并需要某组依赖项时，污点和容忍将允许Karpenter分配具有唯一用户数据的特定实例类型，以确保正确的存储桶与依赖文件挂载在节点上，以便Pod可以访问。此外，用户脚本将取决于新分配节点配置的操作系统。

#### USERDATA脚本：

```
#!/bin/bash
yum update -y
yum install -y wget
wget https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.rpm
yum install -y mount-s3.rpm mkdir -p /mnt/s3
/opt/aws/mountpoint-s3/bin/mount-s3 --metadata-ttl indefinite --allow-other --cache /tmp <S3_BUCKET_NAME> /mnt/s3
```
### 方法2.2：使用DaemonSet

此方法推荐用于现有集群。此方法由2个资源组成，一个带有脚本的ConfigMap，该脚本将S3 Mount Point包维护到节点上，以及一个DaemonSet，它在集群中的每个节点上运行一个Pod，该Pod将在节点上执行脚本。

ConfigMap脚本将每60秒运行一个循环来检查挂载点，如果有任何问题，则重新挂载它。有多个环境变量可以更改挂载位置、缓存位置、S3存储桶名称、日志文件位置以及包安装的URL和已安装包的位置。这些变量可以保留为默认值，因为只有S3存储桶名称是运行所必需的。

DaemonSet Pod将脚本复制到节点上，更改权限以允许执行，然后最终运行脚本。Pod安装```util-linux```以便访问[nsenter](https://man7.org/linux/man-pages/man1/nsenter.1.html)，这允许Pod在节点空间中执行脚本，使Pod可以直接在节点上挂载S3存储桶。
:::danger
DaemonSet Pod需要将```securityContext```设置为privileged，并且```hostPID```、```hostIPC```和```hostNetwork```设置为true。
查看下面为什么需要为此解决方案配置这些以及它们的安全影响。
:::
1. ```securityContext: privileged```
    * **目的：** 特权模式使容器可以完全访问所有主机资源，类似于主机上的root访问。
    * 要安装软件包、配置系统并将S3存储桶挂载到主机上，您的容器可能需要提升的权限。如果没有特权模式，容器可能没有足够的权限在主机文件系统和网络接口上执行这些操作。
2. hostPID
    * **目的：** nsenter允许您进入各种命名空间，包括主机的PID命名空间。
    * 当使用nsenter进入主机的PID命名空间时，容器需要访问主机的PID命名空间。因此，启用```hostPID: true```对于与主机上的进程交互是必要的，这对于安装包或运行需要主机级进程可见性的命令（如mountpoint-s3）至关重要。
3. hostIPC
    * **目的：** hostIPC使您的容器能够共享主机的进程间通信命名空间，包括共享内存。
    * 如果nsenter命令或要运行的脚本涉及主机上的共享内存或其他IPC机制，则```hostIPC: true```将是必要的。虽然它不如hostPID常见，但当涉及nsenter时，它通常与之一起启用，特别是如果脚本需要与依赖IPC的主机进程交互。
4. hostNetwork
    * **目的：** hostNetwork允许容器使用主机的网络命名空间，使容器可以访问主机的IP地址和网络接口。
    * 在安装过程中，脚本可能需要从互联网下载包（例如，从托管mountpoint-s3包的存储库）。通过启用hostNetwork与```hostNetwork: true```，您确保下载过程可以直接访问主机的网络接口，避免网络隔离问题。
:::warning
此示例代码使用```spark-team-a```命名空间来运行作业和托管DaemonSet。这主要是因为Terraform堆栈已经为此命名空间设置了[IRSA](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/setting-up-enable-IAM.html)，并允许服务账户访问任何S3存储桶。
在生产中使用时，请确保创建自己的单独命名空间、服务账户和IAM角色，遵循最小权限策略并遵循[IAM角色最佳实践](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
:::

<details>
<summary> 要查看DaemonSet，请点击切换内容！</summary>

<CodeBlock language="yaml">{DaemonSetWithConfig}</CodeBlock>
</details>


## 执行Spark作业
以下是使用方法2与DaemonSet测试场景的步骤：

1. 部署[Spark操作符资源](#资源分配)
2. 准备S3存储桶
    1. ``` cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator/examples/mountpoint-s3-spark/ ```
    2. ``` chmod +x copy-jars-to-s3.sh ```
    3. ``` ./copy-jars-to-s3.sh ```
3. 设置Kubeconfig
    1. ```aws eks update-kubeconfig --name spark-operator-doeks```
4. 应用DaemonSet
    1. ```kubectl apply -f mountpoint-s3-daemonset.yaml ```
4. 应用Spark作业示例
    1. 1. ```kubectl apply -f mountpoint-s3-spark-job.yaml ```
4. 查看作业运行
    * 在SparkApplication CRD运行时，我们可以查看几种不同资源的日志。每个日志应该在单独的终端中，以便同时查看所有日志。
        1. **spark operator**
            1. ``` kubectl -n spark-operator get pods```
            2. 复制spark operator pod的名称
            2. ``` kubectl -n spark-operator logs -f <POD_NAME>```
        2. **spark-team-a Pods**
            1. 为了获取SparkApplication的驱动程序和执行器Pod的日志，我们首先需要验证Pod是否正在运行。使用wide输出，我们应该能够看到Pod运行的节点，使用```-w```我们可以看到每个Pod的状态更新。
            2. ``` kubectl -n spark-team-a get pods -o wide -w ```
        3. **driver Pod**
            1. 一旦驱动程序Pod处于运行状态，这将在前一个终端中可见，我们可以获取驱动程序Pod的日志
            2. ``` kubectl -n spark-team-a logs -f taxi-trip ```
        4. **exec Pod**
            1. 一旦执行器Pod处于运行状态，这将在前一个终端中可见，我们可以获取执行器Pod的日志。确保exec-1正在运行，然后再获取日志，否则使用处于运行状态的另一个执行器Pod。
            2. 2. ``` kubectl -n spark-team-a logs -f taxi-trip-exec-1 ```


## 验证
一旦作业完成运行，您可以在执行器日志中看到文件正在从节点上的本地mountpoint-s3位置复制到spark Pod以进行处理。
```
24/08/13 00:08:46 INFO Utils: Copying /mnt/s3/jars/hadoop-aws-3.3.1.jar to /var/data/spark-5eae56b3-3999-4c2f-8004-afc46d1c82ba/spark-a433e7ce-db5d-4fd5-b344-abf751f43bd3/-14716855631723507720806_cache
24/08/13 00:08:46 INFO Utils: Copying /var/data/spark-5eae56b3-3999-4c2f-8004-afc46d1c82ba/spark-a433e7ce-db5d-4fd5-b344-abf751f43bd3/-14716855631723507720806_cache to /opt/spark/work-dir/./hadoop-aws-3.3.1.jar
24/08/13 00:08:46 INFO Executor: Adding file:/opt/spark/work-dir/./hadoop-aws-3.3.1.jar to class loader
24/08/13 00:08:46 INFO Executor: Fetching file:/mnt/s3/jars/aws-java-sdk-bundle-1.12.647.jar with timestamp 1723507720806
24/08/13 00:08:46 INFO Utils: Copying /mnt/s3/jars/aws-java-sdk-bundle-1.12.647.jar to /var/data/spark-5eae56b3-3999-4c2f-8004-afc46d1c82ba/spark-a433e7ce-db5d-4fd5-b344-abf751f43bd3/14156613201723507720806_cache
24/08/13 00:08:47 INFO Utils: Copying /var/data/spark-5eae56b3-3999-4c2f-8004-afc46d1c82ba/spark-a433e7ce-db5d-4fd5-b344-abf751f43bd3/14156613201723507720806_cache to /opt/spark/work-dir/./aws-java-sdk-bundle-1.12.647.jar
```
此外，当查看spark-team-a Pod的状态时，您会注意到另一个节点上线，这个节点针对运行SparkApplication进行了优化，一旦它上线，DaemonSet Pod也将启动并开始在新节点上运行，以便在新节点上运行的任何Pod也可以访问S3存储桶。使用Systems Sessions Manager (SSM)，您可以连接到任何节点并验证mountpoint-s3包已下载并安装，方法是运行：
* ```mount-s3 --version```

在节点级别为多个Pod使用mountpoint-S3的最大优势是数据可以被缓存，允许其他Pod访问相同的数据而无需进行自己的API调用。一旦分配了*karpenter-spark-compute-optimized*优化节点，您可以使用Sessions Manager (SSM)连接到节点并验证当作业运行并挂载卷时，文件将被缓存在节点上。您可以在以下位置查看缓存：
* ```sudo ls /tmp/mountpoint-cache/```

## 结论

通过利用CRT库，Mountpoint for Amazon S3可以提供高吞吐量和低延迟，有效管理和访问存储在S3中的大量数据。这允许依赖JAR文件与容器镜像分开存储和管理，将它们与Spark作业解耦。此外，将JAR存储在S3中使多个Pod可以使用它们，与更大的容器镜像相比，S3提供了一个经济高效的存储解决方案，从而节省成本。S3还提供几乎无限的存储空间，使依赖项的扩展和管理变得容易。

Mountpoint-S3为数据和AI/ML工作负载提供了一种多功能且强大的方式，将S3存储与EKS集成。无论您选择使用PV和PVC在Pod级别部署它，还是使用USERDATA或DaemonSet在节点级别部署它，每种方法都有自己的一套优势和权衡。通过了解这些选项，您可以做出明智的决策，优化EKS上的数据和AI/ML工作流程。
