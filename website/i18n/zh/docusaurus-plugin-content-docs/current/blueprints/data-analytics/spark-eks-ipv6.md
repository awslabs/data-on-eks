---
title: Spark Operator on EKS with IPv6
sidebar_position: 3
---

此示例展示了在 IPv6 模式下在 Amazon EKS 上运行的 Spark Operator 的使用。目的是展示和演示在 EKS IPv6 集群上运行 spark 工作负载。

## 部署 EKS 集群以及测试此示例所需的所有附加组件和基础设施

Terraform 蓝图将配置在 Amazon EKS IPv6 上使用开源 Spark Operator 运行 Spark 作业所需的以下资源

* 具有 3 个私有子网和 3 个公有子网的双栈 Amazon Virtual Private Cloud (Amazon VPC)
* 公有子网的互联网网关、私有子网的 NAT 网关和仅出口互联网网关
* IPv6 模式下的 Amazon EKS 集群（版本 1.30）
* Amazon EKS 核心托管节点组，用于托管我们将在集群上配置的一些附加组件
* 部署 Spark-k8s-operator、Apache Yunikorn、Karpenter、Prometheus 和 Grafana 服务器。

### 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

在安装集群之前，创建 EKS IPv6 CNI 策略。按照链接中的说明操作：
[AmazonEKS_CNI_IPv6_Policy ](https://docs.aws.amazon.com/eks/latest/userguide/cni-iam-role.html#cni-iam-role-create-ipv6-policy)

### 克隆存储库

```bash
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks
export DOEKS_HOME=$(pwd)
```

### 初始化 Terraform

导航到示例目录并运行初始化脚本 `install.sh`。

```bash
cd ${DOEKS_HOME}/analytics//terraform/spark-eks-ipv6/
chmod +x install.sh
./install.sh
```

### 导出 Terraform 输出

```bash
export CLUSTER_NAME=$(terraform output -raw cluster_name)
