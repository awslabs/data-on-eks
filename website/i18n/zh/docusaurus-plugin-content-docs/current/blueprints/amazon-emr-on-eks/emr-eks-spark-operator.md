---
sidebar_position: 3
sidebar_label: 使用 Spark Operator 的 EMR Runtime
---
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

# 使用 Spark Operator 的 EMR Runtime

## 介绍
在这篇文章中，我们将学习如何部署带有 EMR Spark Operator 的 EKS 并使用 EMR runtime 执行示例 Spark 作业。

在这个[示例](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/emr-eks-karpenter)中，您将配置使用 Spark Operator 和 EMR runtime 运行 Spark 应用程序所需的以下资源。

- 创建具有公共端点的 EKS 集群控制平面（仅用于演示目的）
- 两个托管节点组
  - 核心节点组，包含 3 个可用区，用于运行系统关键 Pod。例如，Cluster Autoscaler、CoreDNS、可观测性、日志记录等。
  - Spark 节点组，包含单个可用区，用于运行 Spark 作业
- 创建一个数据团队（`emr-data-team-a`）
  - 为团队创建新的命名空间
  - 为团队执行角色创建新的 IAM 角色
- `emr-data-team-a` 的 IAM 策略
- Spark History Server Live UI 配置为通过 NLB 和 NGINX 入口控制器监控正在运行的 Spark 作业
- 部署以下 Kubernetes 插件
    - 托管插件
        - VPC CNI、CoreDNS、KubeProxy、AWS EBS CSI 驱动程序
    - 自管理插件
        - 具有 HA 的 Metrics server、CoreDNS 集群比例自动扩展器、Cluster Autoscaler、Prometheus Server 和 Node Exporter、AWS for FluentBit、EKS 的 CloudWatchMetrics

<CollapsibleContent header={<h2><span>EMR Spark Operator</span></h2>}>

Apache Spark 的 Kubernetes Operator 旨在使指定和运行 Spark 应用程序像在 Kubernetes 上运行其他工作负载一样简单和惯用。要向 Spark Operator 提交 Spark 应用程序并利用 EMR Runtime，我们使用托管在 EMR on EKS ECR 存储库中的 Helm Chart。图表存储在以下路径下：`ECR_URI/spark-operator`。ECR 存储库可以从此[链接](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/setting-up-emr-runtime.html)获取。

* SparkApplication 控制器，监视 SparkApplication 对象的创建、更新和删除事件并对监视事件采取行动，
* 提交运行器，为从控制器接收的提交运行 spark-submit，
* Spark Pod 监视器，监视 Spark Pod 并向控制器发送 Pod 状态更新，
* 变异准入 Webhook，根据控制器添加的 Pod 上的注释处理 Spark 驱动程序和执行器 Pod 的自定义

</CollapsibleContent>

<CollapsibleContent header={<h2><span>部署解决方案</span></h2>}>
### 先决条件：

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### 部署

克隆存储库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到 `analytics/terraform/emr-eks-karpenter` 并运行 `terraform init`

```bash
cd ./data-on-eks/analytics/terraform/emr-eks-karpenter
terraform init
```

:::info
要部署 EMR Spark Operator 插件。您需要在 `variables.tf` 文件中将以下值设置为 `true`。

```hcl
variable "enable_emr_spark_operator" {
  description = "Enable the Spark Operator to submit jobs with EMR Runtime"
  default     = true
  type        = bool
}
```

:::

部署模式

```bash
terraform apply
```

输入 `yes` 以应用。

## 验证资源

让我们验证 `terraform apply` 创建的资源。

验证 Spark Operator 和 Amazon Managed service for Prometheus。

```bash

helm list --namespace spark-operator -o yaml

aws amp list-workspaces --alias amp-ws-emr-eks-karpenter

```

验证命名空间 `emr-data-team-a` 以及 `Prometheus`、`Vertical Pod Autoscaler`、`Metrics Server` 和 `Cluster Autoscaler` 的 Pod 状态。

```bash
aws eks --region us-west-2 update-kubeconfig --name spark-operator-doeks # 创建 k8s 配置文件以与 EKS 集群进行身份验证

kubectl get nodes # 输出显示 EKS 托管节点组节点

kubectl get ns | grep emr-data-team # 输出显示数据团队的 emr-data-team-a

kubectl get pods --namespace=vpa  # 输出显示 Vertical Pod Autoscaler Pod

kubectl get pods --namespace=kube-system | grep  metrics-server # 输出显示 Metric Server Pod

kubectl get pods --namespace=kube-system | grep  cluster-autoscaler # 输出显示 Cluster Autoscaler Pod
```

</CollapsibleContent>

<CollapsibleContent header={<h2><span>使用 Karpenter 执行示例 Spark 作业</span></h2>}>

导航到示例目录并提交 Spark 作业。

```bash
cd data-on-eks/analytics/terraform/emr-eks-karpenter/examples/emr-spark-operator
kubectl apply -f pyspark-pi-job.yaml
```

使用以下命令监控作业状态。
您应该看到由 karpenter 触发的新节点，YuniKorn 将在此节点上调度一个驱动程序 Pod 和 2 个执行器 Pod。

```bash
kubectl get pods -n spark-team-a -w
```
</CollapsibleContent>

<CollapsibleContent header={<h2><span>清理</span></h2>}>

此脚本将使用 `-target` 选项清理环境，以确保所有资源按正确顺序删除。

```bash
cd analytics/terraform/emr-eks-karpenter && chmod +x cleanup.sh
./cleanup.sh
```
</CollapsibleContent>

:::caution

为避免对您的 AWS 账户产生不必要的费用，请删除在此部署期间创建的所有 AWS 资源

:::
