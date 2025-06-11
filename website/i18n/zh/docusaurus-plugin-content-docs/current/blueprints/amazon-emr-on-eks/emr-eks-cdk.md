---
sidebar_position: 5
sidebar_label: 使用 CDK 的 EMR on EKS
---

:::danger
**弃用通知**

此蓝图将被弃用，并最终于 **2024年10月27日** 从此 GitHub 仓库中移除。不会修复任何错误，也不会添加新功能。弃用决定基于对此蓝图的需求和兴趣不足，以及难以分配资源维护一个没有被任何用户或客户积极使用的蓝图。

如果您在生产环境中使用此蓝图，请将自己添加到 [adopters.md](https://github.com/awslabs/data-on-eks/blob/main/ADOPTERS.md) 页面并在仓库中提出问题。这将帮助我们重新考虑并可能保留并继续维护该蓝图。否则，您可以创建本地副本或使用现有标签访问它。
:::


# EMR on EKS with CDK

## 介绍
在本文中，我们将学习如何使用 `cdk-eks-blueprints` 中的 EMR on EKS AddOn 和 Teams 来部署 EKS 基础设施以提交 Spark 作业。`cdk-eks-blueprints` 允许您部署 EKS 集群并使其能够被 EMR on EKS 服务使用，只需最少的设置。下面的架构图展示了您将通过此蓝图部署的基础设施的概念视图。

![EMR on EKS CDK](../../../../../../docs/blueprints/amazon-emr-on-eks/img/emr-eks-cdk.png)

## 部署解决方案

在这个[示例](https://github.com/awslabs/data-on-eks/tree/main/analytics/cdk/emr-eks)中，您将配置以下内容：

- 创建带有公共端点的 EKS 集群控制平面（仅用于演示目的）
- 两个托管节点组
  - 具有 3 个可用区的核心节点组，用于运行系统关键 Pod。例如，Cluster Autoscaler、CoreDNS、日志记录等。
  - 具有单个可用区的 Spark 节点组，用于运行 Spark 作业
- 启用 EMR on EKS 并创建一个数据团队（`emr-data-team-a`）
  - 为每个团队创建新的命名空间
  - 为上述命名空间创建 Kubernetes 角色和角色绑定（`emr-containers` 用户）
  - 为团队执行角色创建新的 IAM 角色
  - 使用 emr-containers 用户和 AWSServiceRoleForAmazonEMRContainers 角色更新 AWS_AUTH 配置映射
  - 在作业执行角色和 EMR 托管服务账户的身份之间创建信任关系
- 为 `emr-data-team-a` 创建 EMR 虚拟集群
- 为 `emr-data-team-a` 创建 IAM 策略
- 部署以下 Kubernetes 附加组件
    - 托管附加组件
        - VPC CNI、CoreDNS、KubeProxy、AWS EBS CSi Driver
    - 自管理附加组件
        - 具有高可用性的指标服务器、集群自动扩缩器、CertManager 和 AwsLoadBalancerController

此蓝图还可以使用您使用 `cdk-blueprints-library` 定义的 EKS 集群。

### 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [CDK](https://docs.aws.amazon.com/cdk/v2/guide/getting_started.html#getting_started_install)

**注意：** 您需要拥有一个已被 AWS CDK [引导](https://docs.aws.amazon.com/cdk/v2/guide/getting_started.html#getting_started_bootstrap)的 AWS 账户和区域。

### 自定义

此 CDK 蓝图的入口点是 `/bin/emr-eks.ts`，它实例化了 `lib/emr-eks-blueprint-stack.ts` 中定义的堆栈。此堆栈必须提供一个 VPC 和一个 EMR on EKS 团队定义列表以及将成为 EKS 集群管理员的角色。它还可以选择接受通过 `cdk-blueprints-library` 定义的 EKS 集群和 EKS 集群名称。

传递给 EMR on EKS 蓝图堆栈的属性定义如下：

```typescript
export interface EmrEksBlueprintProps extends StackProps {
  clusterVpc: IVpc,
  clusterAdminRoleArn: ArnPrincipal
  dataTeams: EmrEksTeamProps[],
  eksClusterName?: string, /默认 eksBlueprintCluster
  eksCluster?: GenericClusterProvider,

}
```

在此示例中，我们在 `lib/vpc.ts` 中定义了一个 VPC，并在 `bin/emr-eks.ts` 中实例化它。我们还定义了一个名为 `emr-data-team-a` 的团队，该团队具有一个名为 `myBlueprintExecRole` 的执行角色。
默认情况下，蓝图将部署一个 EKS 集群，其中包含[部署解决方案](#部署解决方案)部分中定义的托管节点组。

### 部署

在运行解决方案之前，您**必须**更改 `lib/emr-eks.ts` 中 `props` 对象的 `clusterAdminRoleArn`。此角色允许您管理 EKS 集群，并且至少应允许 IAM 操作 `eks:AccessKubernetesApi`。

克隆仓库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到示例目录之一并运行 `cdk synth`

```bash
cd analytics/cdk/emr-eks
npm install
cdk synth --profile YOUR-AWS-PROFILE
```

部署模式

```bash
cdk deploy --all
```

输入 `yes` 进行部署。

## 验证资源

让我们验证由 `cdk deploy` 创建的资源。

验证 Amazon EKS 集群

```bash
aws eks describe-cluster --name eksBlueprintCluster # 如果您提供了自己的集群名称，请更新集群名称

```

验证 EMR on EKS 命名空间 `batchjob` 和 `Metrics Server` 与 `Cluster Autoscaler` 的 Pod 状态。

```bash
aws eks --region <输入您的区域> update-kubeconfig --name eksBlueprintCluster # 创建 k8s 配置文件以与 EKS 集群进行身份验证。如果您提供了自己的集群名称，请更新集群名称

kubectl get nodes # 输出显示 EKS 托管节点组节点

kubectl get ns | grep batchjob # 输出显示 batchjob

kubectl get pods --namespace=kube-system | grep  metrics-server # 输出显示 Metric Server pod

kubectl get pods --namespace=kube-system | grep  cluster-autoscaler # 输出显示 Cluster Autoscaler pod
```

## 在 EMR 虚拟集群上执行示例 Spark 作业
使用以下 shell 脚本执行 Spark 作业。

- 部署蓝图后，您将获得虚拟集群 ID 作为输出。您可以使用该 ID 和您提供了策略的执行角色来提交作业。下面您可以找到一个可以使用 AWS CLI 提交的作业示例。

```bash

export EMR_ROLE_ARN=arn:aws:iam::<您的账户ID>:role/myBlueprintExecRole

aws emr-containers start-job-run \
  --virtual-cluster-id=<CDK输出中的虚拟集群ID> \
  --name=pi-2 \
  --execution-role-arn=$EMR_ROLE_ARN \
  --release-label=emr-6.8.0-latest \
  --job-driver='{
    "sparkSubmitJobDriver": {
      "entryPoint": "local://usr/lib/spark/examples/src/main/python/pi.py",
      "sparkSubmitParameters": "--conf spark.executor.instances=1 --conf spark.executor.memory=2G --conf spark.executor.cores=1 --conf spark.driver.cores=1 --conf spark.kubernetes.node.selector.app=spark"
    }
  }'

```

验证作业执行

```bash
kubectl get pods --namespace=batchjob -w
```

## 清理

要清理您的环境，请调用下面的命令。这将销毁 Kubernetes 附加组件、带有节点组的 EKS 集群和 VPC

```bash
cdk destroy --all
```

:::caution

为避免对您的 AWS 账户产生不必要的费用，请删除在此部署期间创建的所有 AWS 资源
:::
