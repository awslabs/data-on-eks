---
sidebar_position: 2
sidebar_label: CloudNativePG PostgreSQL
---

# 使用 CloudNativePG Operator 在 EKS 上部署 PostgreSQL 数据库

## 介绍

**CloudNativePG** 是一个开源
[操作器](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)，
专为管理 [Kubernetes](https://kubernetes.io) 上的 [PostgreSQL](https://www.postgresql.org/) 工作负载而设计。

它定义了一个名为 `Cluster` 的新 Kubernetes 资源，表示由单个主节点和可选数量的副本组成的 PostgreSQL 集群，这些副本在选定的 Kubernetes 命名空间中共存，以实现高可用性和只读查询的卸载。

驻留在同一 Kubernetes 集群中的应用程序可以使用完全由操作器管理的服务访问 PostgreSQL 数据库，而无需担心故障转移或切换后主角色的更改。驻留在 Kubernetes 集群外部的应用程序需要配置 Service 或 Ingress 对象以通过 TCP 公开 Postgres。Web 应用程序可以利用基于 PgBouncer 的原生连接池。

CloudNativePG 最初由 [EDB](https://www.enterprisedb.com) 构建，然后在 Apache License 2.0 下发布开源，并于 2022 年 4 月提交给 CNCF Sandbox。
[源代码存储库在 Github 中](https://github.com/cloudnative-pg/cloudnative-pg)。

有关该项目的更多详细信息可以在此[链接](https://cloudnative-pg.io)中找到

## 部署解决方案

让我们来看看部署步骤

### 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [psql](https://formulae.brew.sh/formula/libpq)

### 使用 CloudNativePG Operator 部署 EKS 集群

首先，克隆存储库

```bash
git clone https://github.com/awslabs/data-on-eks.git
