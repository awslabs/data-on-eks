---
sidebar_position: 3
sidebar_label: EKS上的Airflow
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

import CodeBlock from '@theme/CodeBlock';

# 在Amazon EKS上自管理Apache Airflow部署

## 介绍

此模式在EKS上部署自管理的[Apache Airflow](https://airflow.apache.org/docs/apache-airflow/stable/)。此蓝图在Amazon EKS托管节点组上部署Airflow，并利用Karpenter运行工作负载。

**架构**

![airflow-eks-architecture](../../../../../../docs/blueprints/job-schedulers/img/airflow-eks-architecture.png)

此模式使用有主见的默认值来保持部署体验简单，但也保持灵活性，以便您可以在部署期间选择必要的附加组件。我们建议保持默认值，只有在有可行的替代选项可用于替换时才进行自定义。

在基础设施方面，此模式创建的资源如下：

- 带有公共端点的EKS集群控制平面（推荐用于演示/概念验证环境）
- 一个托管节点组
  - 核心节点组，跨多个可用区有3个实例，用于运行Apache Airflow和其他系统关键pod。例如，Cluster Autoscaler、CoreDNS、可观测性、日志记录等。

- Apache Airflow核心组件（使用airflow-core.tf）：
  - 用于Airflow元数据库的Amazon RDS PostgreSQL实例和安全组。
  - Airflow命名空间
  - 用于Airflow Webserver、Airflow Scheduler和Airflow Worker的Kubernetes服务账户和AWS IAM角色服务账户(IRSA)。
  - Amazon Elastic File System (EFS)、EFS挂载、用于EFS的Kubernetes存储类和用于为Airflow pod挂载Airflow DAG的Kubernetes持久卷声明。
  - 用于Airflow日志的Amazon S3日志存储桶

AWS for FluentBit用于日志记录，Prometheus、Amazon Managed Prometheus和开源Grafana的组合用于可观测性。您可以在下面看到可用附加组件的完整列表。
:::tip
我们建议在专用EKS托管节点组（如此模式提供的`core-node-group`）上运行所有默认系统附加组件。
:::
:::danger
我们不建议移除关键附加组件（`Amazon VPC CNI`、`CoreDNS`、`Kube-proxy`）。
:::
| 附加组件 | 默认启用？ | 好处 | 链接 |
| :---  | :----: | :---- | :---- |
| Amazon VPC CNI | 是 | VPC CNI作为[EKS附加组件](https://docs.aws.amazon.com/eks/latest/userguide/eks-networking-add-ons.html)提供，负责为您的spark应用程序pod创建ENI和IPv4或IPv6地址 | [VPC CNI文档](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html) |
| CoreDNS | 是 | CoreDNS作为[EKS附加组件](https://docs.aws.amazon.com/eks/latest/userguide/eks-networking-add-ons.html)提供，负责解析spark应用程序和Kubernetes集群的DNS查询 | [EKS CoreDNS文档](https://docs.aws.amazon.com/eks/latest/userguide/managing-coredns.html) |
| Kube-proxy | 是 | Kube-proxy作为[EKS附加组件](https://docs.aws.amazon.com/eks/latest/userguide/eks-networking-add-ons.html)提供，它在您的节点上维护网络规则并启用与您的spark应用程序pod的网络通信 | [EKS kube-proxy文档](https://docs.aws.amazon.com/eks/latest/userguide/managing-kube-proxy.html) |
| Amazon EBS CSI驱动程序 | 是 | EBS CSI驱动程序作为[EKS附加组件](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)提供，它允许EKS集群管理EBS卷的生命周期 | [EBS CSI驱动程序文档](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)
| Amazon EFS CSI驱动程序 | 是 | Amazon EFS容器存储接口(CSI)驱动程序提供了CSI接口，允许在AWS上运行的Kubernetes集群管理Amazon EFS文件系统的生命周期。 | [EFS CSI驱动程序文档](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html)
| Karpenter | 是 | Karpenter是无节点组自动扩缩器，为Kubernetes集群上的spark应用程序提供及时计算容量 | [Karpenter文档](https://karpenter.sh/) |
| Cluster Autoscaler | 是 | Kubernetes Cluster Autoscaler自动调整Kubernetes集群的大小，可用于扩展集群中的节点组（如`core-node-group`） | [Cluster Autoscaler文档](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md) |
| Cluster proportional autoscaler | 是 | 这负责扩展Kubernetes集群中的CoreDNS pod | [Cluster Proportional Autoscaler文档](https://github.com/kubernetes-sigs/cluster-proportional-autoscaler) |
| Metrics server | 是 | Kubernetes metrics server负责聚合集群内的cpu、内存和其他容器资源使用情况 | [EKS Metrics Server文档](https://docs.aws.amazon.com/eks/latest/userguide/metrics-server.html) |
| Prometheus | 是 | Prometheus负责监控EKS集群，包括EKS集群中的spark应用程序。我们使用Prometheus部署来抓取和摄取指标到Amazon Managed Prometheus和Kubecost | [Prometheus文档](https://prometheus.io/docs/introduction/overview/) |
| Amazon Managed Prometheus | 是 | 这负责存储和扩展EKS集群和spark应用程序指标 | [Amazon Managed Prometheus文档](https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-Prometheus.html) |
| Kubecost | 是 | Kubecost负责提供按Spark应用程序细分的成本。您可以基于每个作业、命名空间或标签监控成本 | [EKS Kubecost文档](https://docs.aws.amazon.com/eks/latest/userguide/cost-monitoring.html) |
| CloudWatch metrics | 是 | CloudWatch容器洞察指标显示了一种简单且标准化的方式，不仅可以监控AWS资源，还可以在CloudWatch仪表板上监控EKS资源 | [CloudWatch Container Insights文档](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-EKS.html) |
|AWS for Fluent-bit | 是 | 这可用于将EKS集群和工作节点日志发布到CloudWatch Logs或第三方日志系统 | [AWS For Fluent-bit文档](https://github.com/aws/aws-for-fluent-bit) |
| AWS Load Balancer Controller | 是 | AWS Load Balancer Controller管理Kubernetes集群的AWS弹性负载均衡器。 | [AWS Load Balancer Controller文档](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html) |

## 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

## 部署解决方案

克隆仓库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到self-managed-airflow目录并运行install.sh脚本

```bash
cd data-on-eks/schedulers/terraform/self-managed-airflow
chmod +x install.sh
./install.sh
```

## 验证资源

### 创建kubectl配置

更新AWS区域的占位符并运行以下命令。

```bash
mv ~/.kube/config ~/.kube/config.bk
aws eks update-kubeconfig --region <region>  --name self-managed-airflow
```

### 描述EKS集群

```bash
aws eks describe-cluster --name self-managed-airflow
```

### 验证此部署创建的EFS PV和PVC

```bash
kubectl get pvc -n airflow

NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
airflow-dags   Bound    pvc-157cc724-06d7-4171-a14d-something   10Gi       RWX            efs-sc         73m

kubectl get pv -n airflow
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                          STORAGECLASS   REASON   AGE
pvc-157cc724-06d7-4171-a14d-something   10Gi       RWX            Delete           Bound    airflow/airflow-dags           efs-sc                  74m

```

### 验证EFS文件系统

```bash
aws efs describe-file-systems --query "FileSystems[*].FileSystemId" --output text
```
### 验证为Airflow日志创建的S3存储桶

```bashell
aws s3 ls | grep airflow-logs-
```

### 验证Airflow部署

```bashell
kubectl get deployment -n airflow

NAME                READY   UP-TO-DATE   AVAILABLE   AGE
airflow-pgbouncer   1/1     1            1           77m
airflow-scheduler   2/2     2            2           77m
airflow-statsd      1/1     1            1           77m
airflow-triggerer   1/1     1            1           77m
airflow-webserver   2/2     2            2           77m

```

### 获取Postgres RDS密码

可以从Secrets manager获取Amazon Postgres RDS数据库密码

- 登录AWS控制台并打开secrets manager
- 点击`postgres`密钥名称
- 点击检索密钥值按钮以验证Postgres DB主密码

### 登录Airflow Web UI

此部署创建了一个带有公共LoadBalancer的Ingress对象（内部#私有Load Balancer只能在VPC内访问）用于演示目的
对于生产工作负载，您可以修改`airflow-values.yaml`以选择`internal` LB。此外，还建议使用Route53作为Airflow域名和ACM生成证书以通过HTTPS端口访问Airflow。

执行以下命令获取ALB DNS名称

```bash
kubectl get ingress -n airflow

NAME                      CLASS   HOSTS   ADDRESS                                                                PORTS   AGE
airflow-airflow-ingress   alb     *       k8s-dataengineering-c92bfeb177-randomnumber.us-west-2.elb.amazonaws.com   80      88m

```

上述ALB URL对于您的部署将不同。因此使用您的URL并在浏览器中打开它

例如，在浏览器中打开URL `http://k8s-dataengineering-c92bfeb177-randomnumber.us-west-2.elb.amazonaws.com/`


默认情况下，Airflow创建一个默认用户，用户名为`admin`，密码为`admin`

使用Admin用户和密码登录，为Admin和Viewer角色创建新用户，并删除默认admin用户

### 执行示例Airflow作业

- 登录Airflow WebUI
- 点击页面顶部的`DAGs`链接。这将显示由GitSync功能预先创建的dag
- 通过点击播放按钮（`>`）执行hello_world_scheduled_dag DAG
- 从`Graph`链接验证DAG执行
- 几分钟后所有任务都会变绿
- 点击其中一个绿色任务，它会打开一个带有日志链接的弹出窗口，您可以在其中验证指向S3的日志
<CollapsibleContent header={<h2><span>使用Karpenter运行Spark工作负载的Airflow</span></h2>}>

![img.png](../../../../../../docs/blueprints/job-schedulers/img/airflow-k8sspark-example.png)

此选项利用Karpenter作为自动扩缩器，消除了对托管节点组和集群自动扩缩器的需求。在此设计中，Karpenter及其Nodepool负责创建按需和竞价实例，根据用户需求动态选择实例类型。与集群自动扩缩器相比，Karpenter提供了更好的性能，具有更高效的节点扩展和更快的响应时间。Karpenter的关键特性包括其从零扩展的能力，优化资源利用率，并在没有资源需求时降低成本。此外，Karpenter支持多个Nodepool，允许为不同工作负载类型（如计算密集型、内存密集型和GPU密集型任务）定义所需基础设施时具有更大的灵活性。此外，Karpenter与Kubernetes无缝集成，根据观察到的工作负载和扩展事件提供自动、实时的集群大小调整。这使得EKS集群设计更加高效和经济，能够适应Spark应用程序和其他工作负载不断变化的需求。

在本教程中，您将使用使用内存优化实例的Karpenter Nodepool。此模板使用带有Userdata的AWS节点模板。

<details>
<summary> 要查看用于内存优化实例的Karpenter Nodepool，请点击切换内容！</summary>

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
          cpu: 20 # 根据您的需求将此值更改为1000或更多用于生产环境
        disruption:
          consolidationPolicy: WhenEmpty
          consolidateAfter: 30s
          expireAfter: 720h
        weight: 100
```
</details>

要运行可以使用此Nodepool的Spark作业，您需要通过在Spark应用程序清单中添加`tolerations`来提交作业。此外，为确保Spark驱动程序pod仅在`On-Demand`节点上运行，Spark执行器pod仅在`Spot`节点上运行，添加`karpenter.sh/capacity-type`节点选择器。

例如，

```yaml
    # 使用Karpenter Nodepool节点选择器和容忍度
    nodeSelector:
      NodeGroupType: "SparkComputeOptimized"
      karpenter.sh/capacity-type: "on-demand"
    tolerations:
      - key: "spark-compute-optimized"
        operator: "Exists"
        effect: "NoSchedule"
```

### 从Airflow Web UI创建Kubernetes默认连接

此步骤对于编写Airflow连接到EKS集群至关重要。

- 使用ALB URL，用户名为`admin`，密码为`admin`登录Airflow WebUI
- 选择`Admin`下拉菜单并点击`Connections`
- 点击"+"按钮添加新记录
- 输入Connection Id为`kubernetes_default`，Connection Type为`Kubernetes Cluster Connection`，并勾选**In cluster configuration**复选框
- 点击保存按钮

![Airflow AWS连接](../../../../../../docs/blueprints/job-schedulers/img/kubernetes_default_conn.png)

导航到airflow目录并在**variable.tf**中将**enable_airflow_spark_example**变量更改为`true`。

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

在**addons.tf**中将**enable_spark_operator**变量更改为`true`。

```yaml
variable "enable_airflow_spark_example" {
  description = "Enable Apache Airflow and Spark Operator example"
  type        = bool
  default     = true
}
```

运行install.sh脚本
```bash
cd data-on-eks/schedulers/terraform/self-managed-airflow
chmod +x install.sh
./install.sh
```

### 执行示例Spark作业DAG

- 登录Airflow WebUI
- 点击页面顶部的`DAGs`链接。这将显示由GitSync功能预先创建的dag
- 通过点击播放按钮（`>`）执行`example_pyspark_pi_job` DAG

<details>
<summary> 要查看示例DAG，请点击切换内容！</summary>

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

- DAG有两个任务，第一个任务是`SparkKubernetesOperator`，它使用示例SparkApplication `example_pyspark_pi_job.yaml`文件。SparkKubernetesOperator任务在`airflow`命名空间中创建Airflow工作器pod。Airflow工作器触发`spark-operator`命名空间中预安装的Kubernetes Spark Operator。然后，Kubernetes Spark Operator使用`example_pyspark_pi_job.yaml`在`On-Demand`节点上启动Spark驱动程序，在`Spot`节点上启动Spark执行器，在`spark-team-a`命名空间中提交PySpark作业来计算Pi的值。

<details>
<summary> 要查看带有容忍度和节点选择器的示例SparkApplication，请点击切换内容！</summary>

```yaml
# 注意：执行作业前，此示例需要以下先决条件
# 1. 确保spark-team-a命名空间存在

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
    # 使用Karpenter Nodepool节点选择器和容忍度
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
    # 使用Karpenter Nodepool节点选择器和容忍度
    nodeSelector:
      NodeGroupType: "SparkComputeOptimized"
      karpenter.sh/capacity-type: "spot"
    tolerations:
      - key: "spark-compute-optimized"
        operator: "Exists"
        effect: "NoSchedule"

```
</details>

- 第二个任务是`SparkKubernetesSensor`，它等待Kubernetes Spark Operator完成执行。
- 从`Graph`链接验证DAG执行
- 几分钟后所有任务都会变绿
- 点击其中一个绿色任务，它会打开一个带有日志链接的弹出窗口，您可以在其中验证指向S3的日志

</CollapsibleContent>

<CollapsibleContent header={<h2><span>清理</span></h2>}>

此脚本将使用`-target`选项清理环境，以确保所有资源按正确顺序删除。

```bash
cd data-on-eks/schedulers/terraform/self-managed-airflow && chmod +x cleanup.sh
./cleanup.sh
```

</CollapsibleContent>

:::caution
为避免对您的AWS账户产生不必要的费用，请删除在此部署期间创建的所有AWS资源
:::
