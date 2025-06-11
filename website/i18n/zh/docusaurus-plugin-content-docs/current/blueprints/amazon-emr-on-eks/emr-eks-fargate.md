---
sidebar_position: 6
sidebar_label: 带Fargate的EMR on EKS
---

:::danger
**弃用通知**

此蓝图将于**2024年10月27日**被弃用并最终从此GitHub仓库中移除。不会修复任何错误，也不会添加新功能。弃用的决定基于对此蓝图的需求和兴趣不足，以及难以分配资源维护一个没有被任何用户或客户积极使用的蓝图。

如果您在生产环境中使用此蓝图，请将自己添加到[adopters.md](https://github.com/awslabs/data-on-eks/blob/main/ADOPTERS.md)页面并在仓库中提出问题。这将帮助我们重新考虑并可能保留并继续维护该蓝图。否则，您可以制作本地副本或使用现有标签访问它。
:::

# EKS Fargate上的EMR虚拟集群

此示例展示了如何使用Fargate配置文件配置无服务器集群（无服务器数据平面）以支持EKS上的EMR虚拟集群。

创建了两个Fargate配置文件：
1. `kube-system`，用于支持核心Kubernetes组件，如CoreDNS
2. `emr-wildcard`，支持以`emr-*`开头的任何命名空间；这允许创建多个虚拟集群，而无需为每个新集群创建额外的Fargate配置文件。

使用`emr-on-eks`模块，您可以通过将多个虚拟集群定义传递给`emr_on_eks_config`来配置任意数量的EMR虚拟集群。每个虚拟集群都将获得自己的资源集，权限仅限于该资源集。`emr-on-eks`附加组件创建的资源包括：
- Kubernetes命名空间、角色和角色绑定；也可以使用现有或外部创建的命名空间和角色
- 用于作业执行的服务账户IAM角色(IRSA)。用户可以通过`s3_bucket_arns`将访问范围限定为适当的S3存储桶和路径，既用于访问作业数据，也用于写出结果。已为作业执行角色提供了最低限度的权限；用户可以通过将其他策略传递给`iam_role_additional_policies`来附加到角色，从而提供额外的权限
- 用于任务执行日志的CloudWatch日志组。日志流由作业本身创建，而不是通过Terraform
- 虚拟集群的EMR托管安全组
- 限定在创建/提供的命名空间范围内的EMR虚拟集群

要了解有关使用Fargate运行完全无服务器EKS集群的更多信息，请参阅[`fargate-serverless`](https://github.com/aws-ia/terraform-aws-eks-blueprints/tree/main/examples/fargate-serverless#serverless-eks-cluster-using-fargate-profiles)示例。

:::info

请注意，创建EMR on EKS集群的方法已经改变，现在作为Kubernetes附加组件完成。
这与之前将EMR on EKS作为EKS集群模块的一部分部署的蓝图不同。
我们的团队正在努力简化这两种部署方法，并将很快为此目的创建一个独立的Terraform模块。
此外，所有蓝图都将使用这个新的专用EMR on EKS Terraform模块进行更新。

:::

## 先决条件：

确保您在本地安装了以下工具：

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### 部署

克隆仓库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到示例目录之一并运行`terraform init`

```bash
cd data-on-eks/analytics/emr-eks-fargate
terraform init
```

设置`AWS_REGION`并运行`terraform plan`以验证此执行创建的资源。

```bash
export AWS_REGION="us-west-2" # 根据需要更改
terraform plan
```

部署模式

```bash
terraform apply
```

在命令提示符处输入`yes`以应用

## 验证

以下命令将更新您本地机器上的`kubeconfig`，并允许您使用`kubectl`与EKS集群交互。

1. 运行`update-kubeconfig`命令：

```sh
aws eks --region <REGION> update-kubeconfig --name <CLUSTER_NAME>
```

2. 通过列出当前运行的所有pod进行测试。注意：EMR on EKS虚拟集群将根据需要创建pod来执行作业，显示的pod将根据您在部署示例后运行`kubectl get pods -A`命令的时间长短而有所不同：

```sh
kubectl get pods -A

# 输出应该如下所示
NAMESPACE      NAME                                                       READY   STATUS              RESTARTS   AGE
kube-system    cluster-proportional-autoscaler-coredns-6ccfb4d9b5-sjb8m   1/1     Running             0          8m27s
kube-system    coredns-7c8d74d658-9cmn2                                   1/1     Running             0          8m27s
kube-system    coredns-7c8d74d658-pmf5l                                   1/1     Running             0          7m38s
```

3. 执行示例EMR on EKS作业。这将使用示例PySpark作业计算Pi的值。
```sh
cd analytics/terraform/emr-eks-fargate/examples
./basic-pyspark-job '<ENTER_EMR_EMR_VIRTUAL_CLUSTER_ID>' '<EMR_JOB_EXECUTION_ROLE_ARN>'
```

4. 作业完成后，导航到CloudWatch日志控制台，找到此示例创建的日志组`/emr-on-eks-logs/emr-workload/emr-workload`。点击`搜索日志组`并在搜索字段中输入`roughly`。您应该会看到一个包含作业返回结果的日志条目。

```json
{
    "message": "Pi is roughly 3.146360",
    "time": "2022-11-20T16:46:59+00:00"
}
```

## 销毁

要拆除和移除在此示例中创建的资源：

```sh
kubectl delete all --all -n emr-workload -n emr-custom # 首先确保所有作业资源都已清理
terraform destroy -target="module.eks_blueprints_kubernetes_addons" -auto-approve
terraform destroy -target="module.eks" -auto-approve
terraform destroy -auto-approve
```

如果EMR虚拟集群无法删除并显示以下错误：
```
Error: waiting for EMR Containers Virtual Cluster (xwbc22787q6g1wscfawttzzgb) delete: unexpected state 'ARRESTED', wanted target ''. last error: %!s(<nil>)
```

您可以使用以下方法清理处于`ARRESTED`状态的任何集群：

```sh
aws emr-containers list-virtual-clusters --region us-west-2 --states ARRESTED \
--query 'virtualClusters[0].id' --output text | xargs -I{} aws emr-containers delete-virtual-cluster \
--region us-west-2 --id {}
```
