---
title: Argo Workflows on EKS
sidebar_position: 4
---
# Argo Workflows on EKS
Argo Workflows 是一个开源的容器原生工作流引擎，用于在 Kubernetes 上编排并行作业。它作为 Kubernetes CRD（自定义资源定义）实现。因此，Argo 工作流可以使用 kubectl 管理，并与其他 Kubernetes 服务（如卷、密钥和 RBAC）原生集成。

该示例演示了如何使用 [Argo Workflows](https://argoproj.github.io/argo-workflows/) 将作业分配给 Amazon EKS。

1. 使用 Argo Workflows 创建 spark 作业。
2. 使用 Argo Workflows 通过 spark operator 创建 spark 作业。
3. 通过使用 [Argo Events](https://argoproj.github.io/argo-events/) 基于 Amazon SQS 消息插入事件触发 Argo Workflows 创建 spark 作业。

此示例的[代码存储库](https://github.com/awslabs/data-on-eks/tree/main/schedulers/terraform/argo-workflow)。

## 先决条件：

确保您已在本地安装以下工具：

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [Argo WorkflowCLI](https://github.com/argoproj/argo-workflows/releases/latest)

## 部署

要配置此示例：

```bash
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/schedulers/terraform/argo-workflow

region=<your region> # 为以下命令设置区域变量
terraform init
terraform apply -var region=$region #默认为 us-west-2
```

在命令提示符处输入 `yes` 以应用

在您的环境中配置了以下组件：
- 示例 VPC、2 个私有子网和 2 个公有子网
- 公有子网的互联网网关和私有子网的 NAT 网关
- 带有一个托管节点组的 EKS 集群控制平面
- EKS 托管附加组件：VPC_CNI、CoreDNS、Kube_Proxy、EBS_CSI_Driver
- K8S 指标服务器、CoreDNS 自动扩展器、集群自动扩展器、AWS for FluentBit、Karpenter、Argo Workflows、Argo Events、Kube Prometheus Stack、Spark Operator 和 Yunikorn 调度器
- 用于 Argo Workflows 和 Argo Events 的 K8s 角色和角色绑定

![terraform-output](../../../../../../docs/blueprints/job-schedulers/img/terraform-output-argo.png)

## 验证
