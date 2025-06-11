---
sidebar_position: 2
sidebar_label: CloudNativePG PostgreSQL
---

# 使用CloudNativePG operator在EKS上部署PostgreSQL数据库

## 介绍

**CloudNativePG**是一个开源[ operator](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)，旨在管理[Kubernetes](https://kubernetes.io)上的[PostgreSQL](https://www.postgresql.org/)工作负载。

它定义了一个新的Kubernetes资源，称为`Cluster`，代表由一个主节点和可选数量的副本组成的PostgreSQL集群，这些副本共存于选定的Kubernetes命名空间中，用于高可用性和分担只读查询。

位于同一Kubernetes集群中的应用程序可以使用完全由 operator管理的服务访问PostgreSQL数据库，而不必担心故障转移或切换后主角色的变化。位于Kubernetes集群外部的应用程序需要配置Service或Ingress对象，通过TCP公开Postgres。Web应用程序可以利用基于PgBouncer的原生连接池。

CloudNativePG最初由[EDB](https://www.enterprisedb.com)构建，然后在Apache License 2.0下开源，并于2022年4月提交给CNCF Sandbox。[源代码仓库在Github](https://github.com/cloudnative-pg/cloudnative-pg)。

有关该项目的更多详细信息，请访问此[链接](https://cloudnative-pg.io)

## 部署解决方案

让我们来看看部署步骤

### 先决条件

确保您已在计算机上安装了以下工具。

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [psql](https://formulae.brew.sh/formula/libpq)

### 部署带有CloudNativePG operator的EKS集群

首先，克隆仓库

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

导航到cloudnative-postgres文件夹并运行`install.sh`脚本。默认情况下，脚本将EKS集群部署到`us-west-2`区域。更新`variables.tf`以更改区域。这也是更新任何其他输入变量或对terraform模板进行任何其他更改的时机。

```bash
cd data-on-eks/distributed-databases/cloudnative-postgres

./install.sh
```

### 验证部署

验证Amazon EKS集群

```bash
aws eks describe-cluster --name cnpg-on-eks
```

更新本地kubeconfig，以便我们可以访问kubernetes集群

```bash
aws eks update-kubeconfig --name cnpg-on-eks --region us-west-2
```

首先，让我们验证集群中是否有工作节点运行。

```bash
kubectl get nodes
NAME                                        STATUS   ROLES    AGE     VERSION
ip-10-1-10-192.us-west-2.compute.internal   Ready    <none>   4d17h   v1.25.6-eks-48e63af
ip-10-1-10-249.us-west-2.compute.internal   Ready    <none>   4d17h   v1.25.6-eks-48e63af
ip-10-1-11-38.us-west-2.compute.internal    Ready    <none>   4d17h   v1.25.6-eks-48e63af
ip-10-1-12-195.us-west-2.compute.internal   Ready    <none>   4d17h   v1.25.6-eks-48e63af
```

接下来，让我们验证所有pod是否正在运行。

```bash
kubectl get pods --namespace=monitoring
NAME                                                        READY   STATUS    RESTARTS        AGE
alertmanager-kube-prometheus-stack-alertmanager-0           2/2     Running   1 (4d17h ago)   4d17h
kube-prometheus-stack-grafana-7f8b9dc64b-sb27n              3/3     Running   0               4d17h
kube-prometheus-stack-kube-state-metrics-5979d9d98c-r9fxn   1/1     Running   0               60m
kube-prometheus-stack-operator-554b6f9965-zqszr             1/1     Running   0               60m
prometheus-kube-prometheus-stack-prometheus-0               2/2     Running   0               4d17h

kubectl get pods --namespace=cnpg-system
NAME                                          READY   STATUS    RESTARTS   AGE
cnpg-on-eks-cloudnative-pg-587d5d8fc5-65z9j   1/1     Running   0          4d17h
```
### 部署PostgreSQL集群

首先，我们需要使用`ebs-csi-driver`创建一个存储类，一个演示命名空间和用于数据库身份验证的登录/密码的kubernetes密钥`app-auth`。查看examples文件夹中的所有kubernetes清单。

#### 存储

对于在具有Amazon EKS和EC2的Kubernetes上运行高度可扩展和持久的自管理PostgreSQL数据库，建议使用提供高性能和容错能力的Amazon Elastic Block Store (EBS)卷。此用例的首选EBS卷类型是：

1.预置IOPS SSD (io2或io1)：

- 专为数据库等I/O密集型工作负载设计。
- 提供一致且低延迟的性能。
- 允许您根据需求配置特定数量的IOPS（每秒输入/输出操作）。
- 每个卷提供高达64,000 IOPS和1,000 MB/s吞吐量，适合要求苛刻的数据库工作负载。

2.通用SSD (gp3或gp2)：

- 适用于大多数工作负载，在性能和成本之间提供平衡。
- 每个卷提供3,000 IOPS和125 MB/s吞吐量的基准性能，如果需要可以增加（gp3最高可达16,000 IOPS和1,000 MB/s）。
- 推荐用于I/O强度较低的数据库工作负载或当成本是主要考虑因素时。

您可以在`examples`文件夹中找到两个存储类模板。

```bash
kubectl create -f examples/storageclass.yaml

kubectl create -f examples/auth-prod.yaml
```
