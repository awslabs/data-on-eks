---
sidebar_position: 3
sidebar_label: 带Spark Operator的EMR运行时
---
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

# 带Spark Operator的EMR运行时

## 介绍
在本文中，我们将学习部署带有EMR Spark Operator的EKS，并使用EMR运行时执行示例Spark作业。

在这个[示例](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/emr-eks-karpenter)中，您将配置使用Spark Operator和EMR运行时运行Spark应用程序所需的以下资源。

- 创建带有公共端点的EKS集群控制平面（仅用于演示目的）
- 两个托管节点组
  - 跨3个可用区的核心节点组，用于运行系统关键pod。例如，Cluster Autoscaler、CoreDNS、可观测性、日志记录等。
  - 单一可用区的Spark节点组，用于运行Spark作业
- 创建一个数据团队（`emr-data-team-a`）
  - 为团队创建新的命名空间
  - 为团队执行角色创建新的IAM角色
- `emr-data-team-a`的IAM策略
- 配置了Spark History Server实时UI，通过NLB和NGINX入口控制器监控运行中的Spark作业
- 部署以下Kubernetes附加组件
    - 托管附加组件
        - VPC CNI、CoreDNS、KubeProxy、AWS EBS CSi驱动程序
    - 自管理附加组件
        - 具有HA的Metrics server、CoreDNS集群比例自动扩缩器、Cluster Autoscaler、Prometheus Server和Node Exporter、AWS for FluentBit、CloudWatchMetrics for EKS


<CollapsibleContent header={<h2><span>EMR Spark Operator</span></h2>}>

Kubernetes Operator for Apache Spark旨在使指定和运行Spark应用程序与在Kubernetes上运行其他工作负载一样简单和符合习惯。要将Spark应用程序提交给Spark Operator并利用EMR运行时，我们使用托管在EMR on EKS ECR仓库中的Helm图表。图表存储在以下路径下：`ECR_URI/spark-operator`。可以从此[链接](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/setting-up-emr-runtime.html)获取ECR仓库。

* SparkApplication控制器，监视SparkApplication对象的创建、更新和删除事件，并对监视事件采取行动，
* 提交运行器，为从控制器接收的提交运行spark-submit，
* Spark pod监视器，监视Spark pod并将pod状态更新发送给控制器，
* 变更准入Webhook，根据控制器添加的pod注释处理Spark驱动程序和执行器pod的自定义设置

</CollapsibleContent>

<CollapsibleContent header={<h2><span>部署解决方案</span></h2>}>
### 先决条件：

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### 部署

克隆仓库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到`analytics/terraform/emr-eks-karpenter`并运行`terraform init`

```bash
cd ./data-on-eks/analytics/terraform/emr-eks-karpenter
terraform init
```

:::info
要部署EMR Spark Operator附加组件。您需要在`variables.tf`文件中将以下值设置为`true`。

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

输入`yes`以应用。

## 验证资源

让我们验证由`terraform apply`创建的资源。

验证Spark Operator和Amazon Managed service for Prometheus。

```bash

helm list --namespace spark-operator -o yaml

aws amp list-workspaces --alias amp-ws-emr-eks-karpenter

```

验证命名空间`emr-data-team-a`和`Prometheus`、`Vertical Pod Autoscaler`、`Metrics Server`和`Cluster Autoscaler`的Pod状态。

```bash
aws eks --region us-west-2 update-kubeconfig --name spark-operator-doeks # 创建k8s配置文件以与EKS集群进行身份验证

kubectl get nodes # 输出显示EKS托管节点组节点

kubectl get ns | grep emr-data-team # 输出显示数据团队的emr-data-team-a

kubectl get pods --namespace=vpa  # 输出显示Vertical Pod Autoscaler pod

kubectl get pods --namespace=kube-system | grep  metrics-server # 输出显示Metric Server pod

kubectl get pods --namespace=kube-system | grep  cluster-autoscaler # 输出显示Cluster Autoscaler pod
```

</CollapsibleContent>

<CollapsibleContent header={<h2><span>使用Karpenter执行示例Spark作业</span></h2>}>

导航到示例目录并提交Spark作业。

```bash
cd data-on-eks/analytics/terraform/emr-eks-karpenter/examples/emr-spark-operator
kubectl apply -f pyspark-pi-job.yaml
```

使用以下命令监控作业状态。
您应该看到由karpenter触发的新节点，YuniKorn将在此节点上调度一个驱动程序pod和2个执行器pod。

```bash
kubectl get pods -n spark-team-a -w
```
</CollapsibleContent>

<CollapsibleContent header={<h2><span>清理</span></h2>}>

此脚本将使用`-target`选项清理环境，以确保所有资源按正确顺序删除。

```bash
cd analytics/terraform/emr-eks-karpenter && chmod +x cleanup.sh
./cleanup.sh
```
</CollapsibleContent>

:::caution

为避免对您的AWS账户产生不必要的费用，请删除在此部署期间创建的所有AWS资源

:::
