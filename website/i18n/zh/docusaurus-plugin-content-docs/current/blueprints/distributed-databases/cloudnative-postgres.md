---
sidebar_position: 2
sidebar_label: CloudNativePG PostgreSQL
---

# 使用 CloudNativePG Operator 在 EKS 上部署 PostgreSQL 数据库

## 介绍

**CloudNativePG** 是一个开源
[operator](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)，
专为管理 [Kubernetes](https://kubernetes.io) 上的 [PostgreSQL](https://www.postgresql.org/) 工作负载而设计。

它定义了一个名为 `Cluster` 的新 Kubernetes 资源，表示由单个主节点和可选数量的副本组成的 PostgreSQL 集群，这些副本在选定的 Kubernetes 命名空间中共存，以实现高可用性和只读查询的卸载。

驻留在同一 Kubernetes 集群中的应用程序可以使用完全由 operator 管理的服务访问 PostgreSQL 数据库，而无需担心故障转移或切换后主角色的更改。驻留在 Kubernetes 集群外部的应用程序需要配置 Service 或 Ingress 对象以通过 TCP 公开 Postgres。Web 应用程序可以利用基于 PgBouncer 的原生连接池。

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
```

导航到 cloudnative-postgres 文件夹并运行 `install.sh` 脚本。默认情况下，脚本将 EKS 集群部署到 `us-west-2` 区域。更新 `variables.tf` 以更改区域。这也是更新任何其他输入变量或对 terraform 模板进行任何其他更改的时候。

```bash
cd data-on-eks/distributed-databases/cloudnative-postgres

./install.sh
```

### 验证部署

验证 Amazon EKS 集群

```bash
aws eks describe-cluster --name cnpg-on-eks
```

更新本地 kubeconfig，以便我们可以访问 kubernetes 集群

```bash
aws eks update-kubeconfig --name cnpg-on-eks --region us-west-2
```

首先，让我们验证集群中有工作节点正在运行。

```bash
kubectl get nodes
NAME                                        STATUS   ROLES    AGE     VERSION
ip-10-1-10-192.us-west-2.compute.internal   Ready    <none>   4d17h   v1.25.6-eks-48e63af
ip-10-1-10-249.us-west-2.compute.internal   Ready    <none>   4d17h   v1.25.6-eks-48e63af
ip-10-1-11-38.us-west-2.compute.internal    Ready    <none>   4d17h   v1.25.6-eks-48e63af
ip-10-1-12-195.us-west-2.compute.internal   Ready    <none>   4d17h   v1.25.6-eks-48e63af
```

接下来，让我们验证所有 Pod 都在运行。

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

### 部署 PostgreSQL 集群

首先，我们需要使用 `ebs-csi-driver` 创建一个存储类，一个演示命名空间和用于数据库身份验证 `app-auth` 的登录/密码的 kubernetes secrets。检查示例文件夹中的所有 kubernetes 清单。

#### 存储

对于在 Kubernetes 上使用 Amazon EKS 和 EC2 运行高度可扩展和持久的自管理 PostgreSQL 数据库，建议使用提供高性能和容错性的 Amazon Elastic Block Store (EBS) 卷。此用例的首选 EBS 卷类型是：

1.预配置 IOPS SSD (io2 或 io1)：

- 专为数据库等 I/O 密集型工作负载而设计。
- 提供一致和低延迟的性能。
- 允许您根据要求预配置特定数量的 IOPS（每秒输入/输出操作）。
- 每个卷提供高达 64,000 IOPS 和 1,000 MB/s 吞吐量，适合要求苛刻的数据库工作负载。

2.通用 SSD (gp3 或 gp2)：

- 适用于大多数工作负载，在性能和成本之间提供平衡。
- 每个卷提供 3,000 IOPS 和 125 MB/s 吞吐量的基线性能，如果需要可以增加（gp3 最高可达 16,000 IOPS 和 1,000 MB/s）。
- 推荐用于较少 I/O 密集型数据库工作负载或成本是主要考虑因素时。

您可以在 `examples` 文件夹中找到两个存储类模板。

```bash
kubectl create -f examples/storageclass.yaml

kubectl create -f examples/auth-prod.yaml
```

与 Kubernetes 中的任何其他部署一样，要部署 PostgreSQL 集群，您需要应用定义所需 `Cluster` 的配置文件。CloudNativePG operator 提供两种引导新数据库的类型：

1. 引导空集群
2. 从另一个集群引导。

在第一个示例中，我们将使用 `initdb` 标志创建一个新的空数据库集群。我们将通过修改 IRSA 配置的 IAM 角色 _1_ 和用于备份恢复过程和 WAL 归档的 S3 存储桶 _2_ 来使用下面的模板。Terraform 可能已经创建了这个，使用 `terraform output` 来提取这些参数：

```bash
cd data-on-eks/distributed-databases/cloudnative-postgres

terraform output

barman_backup_irsa = "arn:aws:iam::<your_account_id>:role/cnpg-on-eks-prod-irsa"
barman_s3_bucket = "XXXX-cnpg-barman-bucket"
configure_kubectl = "aws eks --region us-west-2 update-kubeconfig --name cnpg-on-eks"
```

```yaml
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: prod
  namespace: demo
spec:
  description: "Cluster Demo for DoEKS"
  # 选择您的 PostGres 数据库版本
  imageName: ghcr.io/cloudnative-pg/postgresql:15.2
  # 副本数量
  instances: 3
  startDelay: 300
  stopDelay: 300
  replicationSlots:
    highAvailability:
      enabled: true
    updateInterval: 300
  primaryUpdateStrategy: unsupervised
  serviceAccountTemplate:
    # 对于备份和恢复，我们为 barman 工具使用 IRSA。
    # 您将在 terraform 输出中找到此 IAM 角色。
    metadata:
      annotations:
        eks.amazonaws.com/role-arn: arn:aws:iam::<<account_id>>:role/cnpg-on-eks-prod-irsa #1
  postgresql:
    parameters:
      shared_buffers: 256MB
      pg_stat_statements.max: '10000'
      pg_stat_statements.track: all
      auto_explain.log_min_duration: '10s'
    pg_hba:
      # - hostssl app all all cert
      - host app app all password
  logLevel: debug
  storage:
    storageClass: ebs-sc
    size: 1Gi
  walStorage:
    storageClass: ebs-sc
    size: 1Gi
  monitoring:
    enablePodMonitor: true
  bootstrap:
    initdb: # 部署新集群
      database: WorldDB
      owner: app
      secret:
        name: app-auth
  backup:
    barmanObjectStore:
    # 对于备份，我们使用 S3 存储桶来存储数据。
    # 在此蓝图中，我们创建了一个 S3，请检查 terraform 输出。
      destinationPath: s3://<your-s3-barman-bucket> #2
      s3Credentials:
        inheritFromIAMRole: true
      wal:
        compression: gzip
        maxParallel: 8
    retentionPolicy: "30d"

  resources: # m5large: m5xlarge 2vCPU, 8GI RAM
    requests:
      memory: "512Mi"
      cpu: "1"
    limits:
      memory: "1Gi"
      cpu: "2"

  affinity:
    enablePodAntiAffinity: true
    topologyKey: failure-domain.beta.kubernetes.io/zone

  nodeMaintenanceWindow:
    inProgress: false
    reusePVC: false


```

更新后，您可以应用您的模板。

```bash
kubectl create -f examples/prod-cluster.yaml

```

验证 CloudNativePG operator 已创建三个 Pod：一个主节点和两个备用节点。

```bash

kubectl get pods,svc -n demo
NAME         READY   STATUS    RESTARTS   AGE
pod/prod-1   1/1     Running   0          4m36s
pod/prod-2   1/1     Running   0          3m45s
pod/prod-3   1/1     Running   0          3m9s

NAME               TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
service/prod-any   ClusterIP   172.20.230.153   <none>        5432/TCP   4m54s
service/prod-r     ClusterIP   172.20.33.61     <none>        5432/TCP   4m54s
service/prod-ro    ClusterIP   172.20.96.16     <none>        5432/TCP   4m53s
service/prod-rw    ClusterIP   172.20.236.1     <none>        5432/TCP   4m53s
```

operator 还创建了三个服务：

1. `-rw`：仅指向集群数据库的主实例
2. `-ro`：仅指向用于只读工作负载的热备用副本
3. `-r`：指向任何用于只读工作负载的实例

请注意，`-any` 指向所有实例。

检查集群状态的另一种方法是使用 CloudNativePG 社区提供的 [cloudnative-pg kubectl 插件](https://cloudnative-pg.io/documentation/1.19/cnpg-plugin/#cloudnativepg-plugin)，

```bash
kubectl cnpg status prod

Cluster Summary
Name:               prod
Namespace:          demo
System ID:          7214866198623563798
PostgreSQL Image:   ghcr.io/cloudnative-pg/postgresql:15.2
Primary instance:   prod-1
Status:             Cluster in healthy state
Instances:          3
Ready instances:    3
Current Write LSN:  0/6000000 (Timeline: 1 - WAL File: 000000010000000000000005)

Certificates Status
Certificate Name  Expiration Date                Days Left Until Expiration
----------------  ---------------                --------------------------
prod-ca           2023-06-24 14:40:27 +0000 UTC  89.96
prod-replication  2023-06-24 14:40:27 +0000 UTC  89.96
prod-server       2023-06-24 14:40:27 +0000 UTC  89.96

Continuous Backup status
First Point of Recoverability:  Not Available
Working WAL archiving:          OK
WALs waiting to be archived:    0
Last Archived WAL:              000000010000000000000005   @   2023-03-26T14:52:09.24307Z
Last Failed WAL:                -

Streaming Replication status
Replication Slots Enabled
Name    Sent LSN   Write LSN  Flush LSN  Replay LSN  Write Lag  Flush Lag  Replay Lag  State      Sync State  Sync Priority  Replication Slot
----    --------   ---------  ---------  ----------  ---------  ---------  ----------  -----      ----------  -------------  ----------------
prod-2  0/6000000  0/6000000  0/6000000  0/6000000   00:00:00   00:00:00   00:00:00    streaming  async       0              active
prod-3  0/6000000  0/6000000  0/6000000  0/6000000   00:00:00   00:00:00   00:00:00    streaming  async       0              active

Unmanaged Replication Slot Status
No unmanaged replication slots found

Instances status
Name    Database Size  Current LSN  Replication role  Status  QoS         Manager Version  Node
----    -------------  -----------  ----------------  ------  ---         ---------------  ----
prod-1  29 MB          0/6000000    Primary           OK      BestEffort  1.19.0           ip-10-1-10-192.us-west-2.compute.internal
prod-2  29 MB          0/6000000    Standby (async)   OK      BestEffort  1.19.0           ip-10-1-12-195.us-west-2.compute.internal
prod-3  29 MB          0/6000000    Standby (async)   OK      BestEffort  1.19.0           ip-10-1-11-38.us-west-2.compute.internal
```

### 监控

在此示例中，我们部署了 Prometheus 和 Grafana 插件来监控 CloudNativePG 创建的所有数据库集群。让我们检查 Grafana 仪表板。

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 8080:80

```

![CloudNativePG Grafana 仪表板](../../../../../../docs/blueprints/distributed-databases/img/cnpg_garfana_dashboard.png)

### 导入示例数据库

您可以使用 ingress-controller 或 kubernetes 服务类型 `LoadBalancer` 将数据库暴露到集群外部。但是，对于 EKS 集群内部的内部使用，您可以使用 kubernetes 服务 `prod-rw` 和 `prod-ro`。
在本节中，我们将使用 `kubectl port-forward` 暴露读写服务 `-rw`。

```bash

kubectl port-forward svc/prod-rw 5432:5432 -n demo

```

现在，我们使用 `psql` cli 将 `world.sql` 导入到我们的数据库实例 WorldDB 中，使用来自 `app-auth` secrets 的凭据。

```bash

psql -h localhost --port 5432 -U app -d WorldDB < world.sql

# 快速检查数据库表。

psql -h localhost --port 5432 -U app -d WorldDB -c '\dt'
Password for user app:
            List of relations
 Schema |      Name       | Type  | Owner
--------+-----------------+-------+-------
 public | city            | table | app
 public | country         | table | app
 public | countrylanguage | table | app
(3 rows)
```

### 创建到 S3 的备份

现在我们有了一个运行中的数据库和数据，CloudNativePG operator 使用 [barman](https://pgbarman.org/) 工具提供备份恢复功能。CloudNativePG 允许数据库管理员创建按需数据库或计划备份，更多详细信息请参阅[文档](https://cloudnative-pg.io/documentation/1.19/backup_recovery/)。

在此示例中，我们将创建一个 Backup 对象来立即启动备份过程。

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: ondemand
spec:
  cluster:
    name: prod
```

```bash
 kubectl create -f examples/backup-od.yaml
```

运行需要几分钟时间，然后检查备份过程

```bash
kubectl describe backup ondemand

Events:
  Type    Reason     Age   From                   Message
  ----    ------     ----  ----                   -------
  Normal  Starting   60s   cloudnative-pg-backup  Starting backup for cluster prod
  Normal  Starting   60s   instance-manager       Backup started
  Normal  Completed  56s   instance-manager       Backup completed
```

### 恢复

对于恢复，我们使用 S3 上的备份文件引导新集群。备份工具 _barman_ 管理恢复过程，但它不支持 kubernetes secrets 的备份和恢复。这必须单独管理，比如使用 csi-secrets-driver 与 AWS SecretsManager。

首先让我们删除 prod 数据库。

```bash
kubectl delete cluster prod -n demo

```

然后，使用您的 S3 存储桶和 IAM 角色更新您的模板 `examples/cluster-restore.yaml`。请注意，在恢复模板中，CloudNativePG 使用 `externalClusters` 指向数据库。

```bash
  kubectl create -f examples/cluster-restore.yaml

  Type    Reason                       Age    From            Message
  ----    ------                       ----   ----            -------
  Normal  CreatingPodDisruptionBudget  7m12s  cloudnative-pg  Creating PodDisruptionBudget prod-primary
  Normal  CreatingPodDisruptionBudget  7m12s  cloudnative-pg  Creating PodDisruptionBudget prod
  Normal  CreatingServiceAccount       7m12s  cloudnative-pg  Creating ServiceAccount
  Normal  CreatingRole                 7m12s  cloudnative-pg  Creating Cluster Role
  Normal  CreatingInstance             7m12s  cloudnative-pg  Primary instance (from backup)
  Normal  CreatingInstance             6m33s  cloudnative-pg  Creating instance prod-2
  Normal  CreatingInstance             5m51s  cloudnative-pg  Creating instance prod-3
```

创建新集群时，operator 将创建一个带有 IRSA 配置的 ServiceAccount，如集群资源中所述。确保信任策略指向正确的 ServiceAccount。

让我们检查数据是否按预期恢复。

```bash

psql -h localhost --port 5432 -U app -d WorldDB -c '\dt'
Password for user app:
            List of relations
 Schema |      Name       | Type  | Owner
--------+-----------------+-------+-------
 public | city            | table | app
 public | country         | table | app
 public | countrylanguage | table | app
(3 rows)

psql -h localhost --port 5432 -U app -d WorldDB -c 'SELECT CURRENT_TIME;'

```

## 结论

CloudNativePG operator 提供了[Operator 能力级别](https://operatorframework.io/operator-capabilities/)的第 5 级。在此示例中，我们分享了一个蓝图，该蓝图将 operator 作为插件与其监控堆栈（Prometheus 和 grafana）一起部署。在众多功能中，我们重点介绍了创建集群、导入数据和在灾难（或集群删除）情况下恢复数据库的几个示例。更多功能可在此[文档](https://cloudnative-pg.io/documentation/1.19/)中找到
