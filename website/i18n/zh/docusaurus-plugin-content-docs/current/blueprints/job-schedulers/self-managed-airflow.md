---
sidebar_position: 3
sidebar_label: Airflow on EKS
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

import CodeBlock from '@theme/CodeBlock';

# 在 Amazon EKS 上自管理 Apache Airflow 部署

## 介绍

此模式在 EKS 上部署自管理的 [Apache Airflow](https://airflow.apache.org/docs/apache-airflow/stable/) 部署。此蓝图在 Amazon EKS 托管节点组上部署 Airflow，并利用 Karpenter 运行工作负载。

**架构**

![airflow-eks-architecture](../../../../../../docs/blueprints/job-schedulers/img/airflow-eks-architecture.png)

此模式使用有主见的默认值来保持部署体验简单，但也保持灵活性，以便您可以在部署期间选择必要的插件。我们建议保持默认值，只有在有可行的替代选项时才进行自定义。

在基础设施方面，此模式创建的资源如下：

- 具有公共端点的 EKS 集群控制平面（推荐用于演示/概念验证环境）
- 一个托管节点组
  - 核心节点组，包含跨多个可用区的 3 个实例，用于运行 Apache Airflow 和其他系统关键 Pod。例如，Cluster Autoscaler、CoreDNS、可观测性、日志记录等。

- Apache Airflow 核心组件（使用 airflow-core.tf）：
  - Amazon RDS PostgreSQL 实例和用于 Airflow 元数据库的安全组。
  - Airflow 命名空间
  - Kubernetes 服务账户和用于 Airflow Webserver、Airflow Scheduler 和 Airflow Worker 的服务账户 AWS IAM 角色（IRSA）。
  - Amazon Elastic File System (EFS)、EFS 挂载、用于 EFS 的 Kubernetes 存储类，以及用于为 Airflow Pod 挂载 Airflow DAG 的 Kubernetes 持久卷声明。
  - 用于 Airflow 日志的 Amazon S3 日志存储桶

AWS for FluentBit 用于日志记录，Prometheus、Amazon Managed Prometheus 和开源 Grafana 的组合用于可观测性。您可以在下面看到可用插件的完整列表。
:::tip
我们建议在专用的 EKS 托管节点组（如此模式提供的 `core-node-group`）上运行所有默认系统插件。
:::
:::danger
我们不建议删除关键插件（`Amazon VPC CNI`、`CoreDNS`、`Kube-proxy`）。
:::
| 插件 | 默认启用？ | 好处 | 链接 |
| :---  | :----: | :---- | :---- |
| Amazon VPC CNI | 是 | VPC CNI 作为 [EKS 插件](https://docs.aws.amazon.com/eks/latest/userguide/eks-networking-add-ons.html) 可用，负责为您的 spark 应用程序 Pod 创建 ENI 和 IPv4 或 IPv6 地址 | [VPC CNI 文档](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html) |
| CoreDNS | 是 | CoreDNS 作为 [EKS 插件](https://docs.aws.amazon.com/eks/latest/userguide/eks-networking-add-ons.html) 可用，负责解析 spark 应用程序和 Kubernetes 集群的 DNS 查询 | [EKS CoreDNS 文档](https://docs.aws.amazon.com/eks/latest/userguide/managing-coredns.html) |
| Kube-proxy | 是 | Kube-proxy 作为 [EKS 插件](https://docs.aws.amazon.com/eks/latest/userguide/eks-networking-add-ons.html) 可用，它维护节点上的网络规则并启用到 spark 应用程序 Pod 的网络通信 | [EKS kube-proxy 文档](https://docs.aws.amazon.com/eks/latest/userguide/managing-kube-proxy.html) |
| Amazon EBS CSI 驱动程序 | 是 | EBS CSI 驱动程序作为 [EKS 插件](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html) 可用，它允许 EKS 集群管理 EBS 卷的生命周期 | [EBS CSI 驱动程序文档](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)
| Amazon EFS CSI 驱动程序 | 是 | Amazon EFS 容器存储接口 (CSI) 驱动程序提供 CSI 接口，允许在 AWS 上运行的 Kubernetes 集群管理 Amazon EFS 文件系统的生命周期。 | [EFS CSI 驱动程序文档](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html)
| Karpenter | 是 | Karpenter 是无节点组的自动扩展器，为 Kubernetes 集群上的 spark 应用程序提供即时计算容量 | [Karpenter 文档](https://karpenter.sh/) |
| Cluster Autoscaler | 是 | Kubernetes Cluster Autoscaler 自动调整 Kubernetes 集群的大小，可用于扩展集群中的节点组（如 `core-node-group`） | [Cluster Autoscaler 文档](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md) |
| 集群比例自动扩展器 | 是 | 这负责在您的 Kubernetes 集群中扩展 CoreDNS Pod | [集群比例自动扩展器文档](https://github.com/kubernetes-sigs/cluster-proportional-autoscaler) |
| Metrics server | 是 | Kubernetes metrics server 负责聚合集群内的 CPU、内存和其他容器资源使用情况 | [EKS Metrics Server 文档](https://docs.aws.amazon.com/eks/latest/userguide/metrics-server.html) |
| Prometheus | 是 | Prometheus 负责监控 EKS 集群，包括 EKS 集群中的 spark 应用程序。我们使用 Prometheus 部署来抓取和摄取指标到 Amazon Managed Prometheus 和 Kubecost | [Prometheus 文档](https://prometheus.io/docs/introduction/overview/) |
| Amazon Managed Prometheus | 是 | 这负责存储和扩展 EKS 集群和 spark 应用程序指标 | [Amazon Managed Prometheus 文档](https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-Prometheus.html) |
| Kubecost | 是 | Kubecost 负责按 Spark 应用程序提供成本分解。您可以基于每个作业、命名空间或标签监控成本 | [EKS Kubecost 文档](https://docs.aws.amazon.com/eks/latest/userguide/cost-monitoring.html) |
| CloudWatch 指标 | 是 | CloudWatch 容器洞察指标显示了在 CloudWatch 仪表板上监控 AWS 资源和 EKS 资源的简单和标准化方式 | [CloudWatch 容器洞察文档](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-EKS.html) |
|AWS for Fluent-bit | 是 | 这可用于将 EKS 集群和工作节点日志发布到 CloudWatch Logs 或第三方日志系统 | [AWS For Fluent-bit 文档](https://github.com/aws/aws-for-fluent-bit) |
| AWS Load Balancer Controller | 是 | AWS Load Balancer Controller 为 Kubernetes 集群管理 AWS Elastic Load Balancers。 | [AWS Load Balancer Controller 文档](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html) |

## 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

## 部署解决方案

克隆存储库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到 self-managed-airflow 目录并运行 install.sh 脚本

```bash
cd data-on-eks/schedulers/terraform/self-managed-airflow
chmod +x install.sh
./install.sh
```

## 验证资源

### 创建 kubectl 配置

更新 AWS 区域的占位符并运行以下命令。

```bash
mv ~/.kube/config ~/.kube/config.bk
aws eks update-kubeconfig --region <region>  --name self-managed-airflow
```

### 描述 EKS 集群

```bash
aws eks describe-cluster --name self-managed-airflow
```

### 验证此部署创建的 EFS PV 和 PVC

```bash
kubectl get pvc -n airflow

NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
airflow-dags   Bound    pvc-157cc724-06d7-4171-a14d-something   10Gi       RWX            efs-sc         73m

kubectl get pv -n airflow
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                          STORAGECLASS   REASON   AGE
pvc-157cc724-06d7-4171-a14d-something   10Gi       RWX            Delete           Bound    airflow/airflow-dags           efs-sc                  74m

```

### 验证 EFS 文件系统

```bash
aws efs describe-file-systems --query "FileSystems[*].FileSystemId" --output text
```
### 验证为 Airflow 日志创建的 S3 存储桶

```bashell
aws s3 ls | grep airflow-logs-
```

### 验证 Airflow 部署

```bashell
kubectl get deployment -n airflow

NAME                READY   UP-TO-DATE   AVAILABLE   AGE
airflow-pgbouncer   1/1     1            1           77m
airflow-scheduler   2/2     2            2           77m
airflow-statsd      1/1     1            1           77m
airflow-triggerer   1/1     1            1           77m
airflow-webserver   2/2     2            2           77m

```

### 获取 Postgres RDS 密码

Amazon Postgres RDS 数据库密码可以从 Secrets manager 获取

- 登录 AWS 控制台并打开 secrets manager
- 点击 `postgres` 密钥名称
- 点击检索密钥值按钮以验证 Postgres DB 主密码

### 登录 Airflow Web UI

此部署为演示目的创建了一个带有公共 LoadBalancer 的 Ingress 对象（内部 # 私有负载均衡器只能在 VPC 内访问）
对于生产工作负载，您可以修改 `airflow-values.yaml` 以选择 `internal` LB。此外，还建议使用 Route53 作为 Airflow 域，使用 ACM 生成证书以在 HTTPS 端口上访问 Airflow。

执行以下命令获取 ALB DNS 名称

```bash
kubectl get ingress -n airflow

NAME                      CLASS   HOSTS   ADDRESS                                                                PORTS   AGE
airflow-airflow-ingress   alb     *       k8s-dataengineering-c92bfeb177-randomnumber.us-west-2.elb.amazonaws.com   80      88m

```

上述 ALB URL 对于您的部署将有所不同。因此请使用您的 URL 并在浏览器中打开它

例如，在浏览器中打开 URL `http://k8s-dataengineering-c92bfeb177-randomnumber.us-west-2.elb.amazonaws.com/`

默认情况下，Airflow 创建一个默认用户，用户名为 `admin`，密码为 `admin`

使用管理员用户和密码登录，为管理员和查看者角色创建新用户，并删除默认管理员用户

### 执行示例 Airflow 作业

- 登录 Airflow WebUI
- 点击页面顶部的 `DAGs` 链接。这将显示由 GitSync 功能预创建的 dag
- 通过点击播放按钮（`>`）执行 hello_world_scheduled_dag DAG
- 从 `Graph` 链接验证 DAG 执行
- 几分钟后所有任务都会变绿
- 点击其中一个绿色任务，这会打开一个带有日志链接的弹出窗口，您可以在其中验证指向 S3 的日志

<CollapsibleContent header={<h2><span>Airflow 使用 Karpenter 运行 Spark 工作负载</span></h2>}>

![img.png](../../../../../../docs/blueprints/job-schedulers/img/airflow-k8sspark-example.png)

此选项利用 Karpenter 作为自动扩展器，消除了对托管节点组和 Cluster Autoscaler 的需求。在此设计中，Karpenter 及其 Nodepool 负责创建按需和 Spot 实例，根据用户需求动态选择实例类型。与 Cluster Autoscaler 相比，Karpenter 提供了改进的性能，具有更高效的节点扩展和更快的响应时间。Karpenter 的关键功能包括从零扩展的能力，在没有资源需求时优化资源利用率并降低成本。此外，Karpenter 支持多个 Nodepool，允许在为不同工作负载类型（如计算、内存和 GPU 密集型任务）定义所需基础设施时具有更大的灵活性。此外，Karpenter 与 Kubernetes 无缝集成，根据观察到的工作负载和扩展事件提供自动、实时的集群大小调整。这使得 EKS 集群设计更加高效和经济，能够适应 Spark 应用程序和其他工作负载不断变化的需求。

在本教程中，您将使用使用内存优化实例的 Karpenter Nodepool。此模板使用带有 Userdata 的 AWS Node 模板。

<details>
<summary> 要查看内存优化实例的 Karpenter Nodepool，点击切换内容！</summary>

```yaml
    name: spark-compute-optimized
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          tags:
            Name: "${module.eks.cluster_name}-private*"
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        userData: |
          MIME-Version: 1.0
          Content-Type: multipart/mixed; boundary="BOUNDARY"

          --BOUNDARY
          Content-Type: text/x-shellscript; charset="us-ascii"

          cat <<-EOF > /etc/profile.d/bootstrap.sh
          #!/bin/sh


          # Configure the NVMe volumes in RAID0 configuration in the bootstrap.sh call.
          # https://github.com/awslabs/amazon-eks-ami/blob/master/files/bootstrap.sh#L35
          # This will create a RAID volume and mount it at /mnt/k8s-disks/0
          #   then mount that volume to /var/lib/kubelet, /var/lib/containerd, and /var/log/pods
          #   this allows the container daemons and pods to write to the RAID0 by default without needing PersistentVolumes
          export LOCAL_DISKS='raid0'
          EOF

          # Source extra environment variables in bootstrap script
          sed -i '/^set -o errexit/a\\nsource /etc/profile.d/bootstrap.sh' /etc/eks/bootstrap.sh

          --BOUNDARY--

      nodePool:
        labels:
          - type: karpenter
          - NodeGroupType: SparkComputeOptimized
          - multiArch: Spark
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot", "on-demand"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["amd64"]
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["c"]
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["c5d"]
          - key: "karpenter.k8s.aws/instance-cpu"
            operator: In
            values: ["4", "8", "16", "36"]
          - key: "karpenter.k8s.aws/instance-hypervisor"
            operator: In
            values: ["nitro"]
          - key: "karpenter.k8s.aws/instance-generation"
            operator: Gt
            values: ["2"]
        limits:
          cpu: 20 # Change this to 1000 or more for production according to your needs
        disruption:
          consolidationPolicy: WhenEmpty
          consolidateAfter: 30s
          expireAfter: 720h
        weight: 100
```
</details>

要运行可以使用此 Nodepool 的 Spark 作业，您需要通过向 Spark 应用程序清单添加 `tolerations` 来提交作业。此外，为了确保 Spark 驱动程序 Pod 仅在 `On-Demand` 节点上运行，Spark 执行器仅在 `Spot` 节点上运行，请添加 `karpenter.sh/capacity-type` 节点选择器。

例如，

```yaml
    # 使用 Karpenter Nodepool nodeSelectors 和 tolerations
    nodeSelector:
      NodeGroupType: "SparkComputeOptimized"
      karpenter.sh/capacity-type: "on-demand"
    tolerations:
      - key: "spark-compute-optimized"
        operator: "Exists"
        effect: "NoSchedule"
```

### 从 Airflow Web UI 创建 Kubernetes 默认连接

此步骤对于编写 Airflow 连接到 EKS 集群至关重要。

- 使用 ALB URL 以 `admin` 和密码 `admin` 登录 Airflow WebUI
- 选择 `Admin` 下拉菜单并点击 `Connections`
- 点击"+"按钮添加新记录
- 输入连接 ID 为 `kubernetes_default`，连接类型为 `Kubernetes Cluster Connection`，并勾选复选框 **In cluster configuration**
- 点击保存按钮

![Airflow AWS Connection](../../../../../../docs/blueprints/job-schedulers/img/kubernetes_default_conn.png)

导航到 airflow 目录并在 **variable.tf** 中将 **enable_airflow_spark_example** 变量更改为 `true`。

```bash
cd schedulers/terraform/self-managed-airflow
```

```yaml
variable "enable_airflow_spark_example" {
  description = "Enable Apache Airflow and Spark Operator example"
  type        = bool
  default     = true
}
```

在 **addons.tf** 中将 **enable_spark_operator** 变量更改为 `true`。

```yaml
variable "enable_airflow_spark_example" {
  description = "Enable Apache Airflow and Spark Operator example"
  type        = bool
  default     = true
}
```

运行 install.sh 脚本
```bash
cd data-on-eks/schedulers/terraform/self-managed-airflow
chmod +x install.sh
./install.sh
```

### 执行示例 Spark 作业 DAG

- 登录 Airflow WebUI
- 点击页面顶部的 `DAGs` 链接。这将显示由 GitSync 功能预创建的 dag
- 通过点击播放按钮（`>`）执行 `example_pyspark_pi_job` DAG

<details>
<summary> 要查看示例 DAG，点击切换内容！</summary>

```python
"""
from __future__ import annotations

import os
from datetime import datetime, timedelta

# [START import_module]
# The DAG object; we'll need this to instantiate a DAG
from airflow import DAG

# Operators; we need this to operate!
from airflow.providers.cncf.kubernetes.operators.spark_kubernetes import SparkKubernetesOperator
from airflow.providers.cncf.kubernetes.sensors.spark_kubernetes import SparkKubernetesSensor

# [END import_module]

# [START instantiate_dag]

DAG_ID = "example_pyspark_pi_job"

with DAG(
    DAG_ID,
    default_args={"max_active_runs": 1},
    description="submit spark-pi as sparkApplication on kubernetes",
    schedule=timedelta(days=1),
    start_date=datetime(2021, 1, 1),
    catchup=False,
) as dag:
    # [START SparkKubernetesOperator_DAG]
    t1 = SparkKubernetesOperator(
        task_id="pyspark_pi_submit",
        namespace="spark-team-a",
        application_file="example_pyspark_pi_job.yaml",
        do_xcom_push=True,
        dag=dag,
    )

    t2 = SparkKubernetesSensor(
        task_id="pyspark_pi_monitor",
        namespace="spark-team-a",
        application_name="{{ task_instance.xcom_pull(task_ids='pyspark_pi_submit')['metadata']['name'] }}",
        dag=dag,
    )
    t1 >> t2
```
</details>

- DAG 有两个任务，第一个任务是 `SparkKubernetesOperator`，它使用示例 SparkApplication `example_pyspark_pi_job.yaml` 文件。SparkKubernetesOperator 任务在 `airflow` 命名空间中创建 Airflow 工作器 Pod。Airflow 工作器触发 `spark-operator` 命名空间中预安装的 Kubernetes Spark Operator。然后 Kubernetes Spark Operator 使用 `example_pyspark_pi_job.yaml` 在 `On-Demand` 节点上启动 Spark 驱动程序，在 `Spot` 节点上启动 Spark 执行器，在 `spark-team-a` 命名空间中提交 PySpark 作业以计算 Pi 的值。

<details>
<summary> 要查看带有 tolerations 和节点选择器的示例 SparkApplication，点击切换内容！</summary>

```yaml
# NOTE: This example requires the following prerequisites before executing the jobs
# 1. Ensure spark-team-a name space exists

---
apiVersion: "sparkoperator.k8s.io/v1beta2"
kind: SparkApplication
metadata:
  name: pyspark-pi-karpenter
  namespace: spark-team-a
spec:
  type: Python
  pythonVersion: "3"
  mode: cluster
  image: "public.ecr.aws/r1l5w1y9/spark-operator:3.2.1-hadoop-3.3.1-java-11-scala-2.12-python-3.8-latest"
  imagePullPolicy: Always
  mainApplicationFile: local:///opt/spark/examples/src/main/python/pi.py
  sparkVersion: "3.1.1"
  restartPolicy:
    type: OnFailure
    onFailureRetries: 1
    onFailureRetryInterval: 10
    onSubmissionFailureRetries: 5
    onSubmissionFailureRetryInterval: 20
  driver:
    cores: 1
    coreLimit: "1200m"
    memory: "512m"
    labels:
      version: 3.1.1
    serviceAccount: spark-team-a
    # Using Karpenter Nodepool nodeSelectors and tolerations
    nodeSelector:
      NodeGroupType: "SparkComputeOptimized"
      karpenter.sh/capacity-type: "on-demand"
    tolerations:
      - key: "spark-compute-optimized"
        operator: "Exists"
        effect: "NoSchedule"
  executor:
    cores: 1
    instances: 2
    memory: "512m"
    serviceAccount: spark-team-a
    labels:
      version: 3.1.1
    # Using Karpenter Nodepool nodeSelectors and tolerations
    nodeSelector:
      NodeGroupType: "SparkComputeOptimized"
      karpenter.sh/capacity-type: "spot"
    tolerations:
      - key: "spark-compute-optimized"
        operator: "Exists"
        effect: "NoSchedule"

```
</details>

- 第二个任务是 `SparkKubernetesSensor`，它等待 Kubernetes Spark Operator 完成执行。
- 从 `Graph` 链接验证 DAG 执行
- 几分钟后所有任务都会变绿
- 点击其中一个绿色任务，这会打开一个带有日志链接的弹出窗口，您可以在其中验证指向 S3 的日志

</CollapsibleContent>

<CollapsibleContent header={<h2><span>清理</span></h2>}>

此脚本将使用 `-target` 选项清理环境，以确保所有资源按正确顺序删除。

```bash
cd data-on-eks/schedulers/terraform/self-managed-airflow && chmod +x cleanup.sh
./cleanup.sh
```

</CollapsibleContent>

:::caution
为避免对您的 AWS 账户产生不必要的费用，请删除在此部署期间创建的所有 AWS 资源
:::
