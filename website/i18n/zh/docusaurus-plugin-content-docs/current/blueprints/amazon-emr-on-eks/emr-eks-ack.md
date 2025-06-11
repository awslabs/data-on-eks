---
sidebar_position: 4
sidebar_label: 带ACK控制器的EMR on EKS
---
import CollapsibleContent from '../../../../../../src/components/CollapsibleContent';

:::danger
**弃用通知**

此蓝图将于**2024年10月27日**被弃用并最终从此GitHub仓库中移除。不会修复任何错误，也不会添加新功能。弃用的决定基于对此蓝图的需求和兴趣不足，以及难以分配资源维护一个没有被任何用户或客户积极使用的蓝图。

如果您在生产环境中使用此蓝图，请将自己添加到[adopters.md](https://github.com/awslabs/data-on-eks/blob/main/ADOPTERS.md)页面并在仓库中提出问题。这将帮助我们重新考虑并可能保留并继续维护该蓝图。否则，您可以制作本地副本或使用现有标签访问它。
:::


# 用于EMR on EKS的ACK控制器

## 介绍
在本文中，我们将学习通过使用[AWS Controllers for Kubernetes (ACK)](https://aws-controllers-k8s.github.io/community/docs/tutorials/emr-on-eks-example/)构建EMR on EKS Spark工作负载。
我们还将通过利用Amazon Managed Service for Prometheus收集和存储Spark应用程序生成的指标，为Spark工作负载构建端到端可观测性，然后使用Amazon Managed Grafana为监控用例构建仪表板。

<CollapsibleContent header={<h2><span>部署解决方案</span></h2>}>

在这个[示例](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/emr-eks-ack)中，您将配置使用EMR on EKS运行Spark作业所需的以下资源，以及使用**Amazon Managed Prometheus**和**Amazon Managed Grafana**监控spark作业指标。

- 创建带有公共端点的EKS集群控制平面（仅用于演示目的）
- 两个托管节点组
  - 跨3个可用区的核心节点组，用于运行系统关键pod。例如，Cluster Autoscaler、CoreDNS、可观测性、日志记录等。
  - 单一可用区的Spark节点组，用于运行Spark作业
- 启用EMR on EKS并创建两个数据团队（`emr-data-team-a`，`emr-data-team-b`）
  - 为每个团队创建新的命名空间
  - 为上述命名空间创建Kubernetes角色和角色绑定（`emr-containers`用户）
  - 为团队执行角色创建新的IAM角色
  - 使用emr-containers用户和AWSServiceRoleForAmazonEMRContainers角色更新AWS_AUTH配置映射
  - 在作业执行角色和EMR托管服务账户的身份之间创建信任关系
- `emr-data-team-a`的EMR虚拟集群
- `emr-data-team-a`的IAM策略
- Amazon Managed Prometheus工作区，用于从Prometheus服务器远程写入指标
- 部署以下Kubernetes附加组件
    - 托管附加组件
        - VPC CNI、CoreDNS、KubeProxy、AWS EBS CSi驱动程序
    - 自管理附加组件
        - 具有HA的Metrics server、CoreDNS集群比例自动扩缩器、Cluster Autoscaler、Prometheus Server和Node Exporter、Prometheus的VPA、AWS for FluentBit、CloudWatchMetrics for EKS
 -  ACK EMR容器控制器，允许您使用yaml文件将spark作业部署到EMR on EKS。控制器通过使用[AWS EKS ACK Addons Terraform模块](https://github.com/aws-ia/terraform-aws-eks-ack-addons)安装

### 先决条件：

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

_注意：目前Amazon Managed Prometheus仅在选定区域支持。请参阅此[用户指南](https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-Prometheus.html)了解支持的区域。_

### 部署

克隆仓库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到示例目录之一并运行`terraform init`

```bash
cd data-on-eks/analytics/terraform/emr-eks-ack
terraform init
```

设置`AWS_REGION`并运行Terraform计划以验证此执行创建的资源。

```bash
export AWS_REGION="us-west-2" # 根据您的需要更改区域
terraform plan
```

部署模式

```bash
terraform apply
```

输入`yes`以应用。

## 验证资源

让我们验证由`terraform apply`创建的资源。

验证Amazon EKS集群和Amazon Managed service for Prometheus。

```bash
aws eks describe-cluster --name emr-eks-ack

aws amp list-workspaces --alias amp-ws-emr-eks-ack
```

验证EMR on EKS命名空间`emr-data-team-a`和`emr-data-team-b`以及`Prometheus`、`Vertical Pod Autoscaler`、`Metrics Server`和`Cluster Autoscaler`的Pod状态。

```bash
aws eks --region us-west-2 update-kubeconfig --name emr-eks-ack # 创建k8s配置文件以与EKS集群进行身份验证

kubectl get nodes # 输出显示EKS托管节点组节点

kubectl get ns | grep emr-data-team # 输出显示数据团队的emr-data-team-a和emr-data-team-b命名空间

kubectl get pods --namespace=prometheus # 输出显示Prometheus服务器和Node exporter pod

kubectl get pods --namespace=vpa  # 输出显示Vertical Pod Autoscaler pod

kubectl get pods --namespace=kube-system | grep  metrics-server # 输出显示Metric Server pod

kubectl get pods --namespace=kube-system | grep  cluster-autoscaler # 输出显示Cluster Autoscaler pod
```

</CollapsibleContent>

### 使用SSO设置Amazon Managed Grafana
目前，此步骤是手动的。请按照此[博客](https://aws.amazon.com/blogs/mt/monitoring-amazon-emr-on-eks-with-amazon-managed-prometheus-and-amazon-managed-grafana/)中的步骤在您的账户中创建启用了SSO的Amazon Managed Grafana。
您可以使用Amazon Managed Prometheus和Amazon Managed Grafana可视化Spark作业运行和指标。

<CollapsibleContent header={<h2><span>执行示例Spark作业 - EMR虚拟集群</span></h2>}>

我们现在可以创建EMR虚拟集群。EMR虚拟集群映射到Kubernetes命名空间。EMR使用虚拟集群来运行作业和托管端点。
为emr-data-team-a创建一个虚拟集群my-ack-vc

```bash
kubectl apply -f analytics/terraform/emr-eks-ack/examples/emr-virtualcluster.yaml

kubectl describe virtualclusters
```
您将获得如下输出 <br/>
 ![](../../../../../../docs/blueprints/amazon-emr-on-eks/img/ack-virtualcluster.png)


执行以下shell脚本来运行Spark作业。这将要求两个输入，可以从terraform输出中提取。

```bash
./analytics/terraform/emr-eks-ack/examples/sample-pyspark-job.sh

kubectl describe jobruns
```
您将获得如下输出 <br/>
 ![](../../../../../../docs/blueprints/amazon-emr-on-eks/img/ack-sparkjob.png)

</CollapsibleContent>

<CollapsibleContent header={<h2><span>清理</span></h2>}>

此脚本将使用`-target`选项清理环境，以确保所有资源按正确顺序删除。

```bash
cd analytics/terraform/emr-eks-ack && chmod +x cleanup.sh
./cleanup.sh
```
</CollapsibleContent>

:::caution

为避免对您的AWS账户产生不必要的费用，请删除在此部署期间创建的所有AWS资源

:::
