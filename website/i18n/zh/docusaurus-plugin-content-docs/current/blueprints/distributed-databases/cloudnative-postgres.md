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
与Kubernetes中的任何其他部署一样，要部署PostgreSQL集群，您需要应用一个定义所需`Cluster`的配置文件。CloudNativePG operator提供两种引导新数据库的类型：

1. 引导一个空集群
2. 从另一个集群引导。

在第一个示例中，我们将使用`initdb`标志创建一个新的空数据库集群。我们将通过修改用于IRSA配置的IAM角色_1_和用于备份恢复过程和WAL归档的S3存储桶_2_来使用下面的模板。Terraform可能已经创建了这些，使用`terraform output`提取这些参数：

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
  # 选择您的PostGres数据库版本
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
    # 对于备份和恢复，我们使用IRSA作为barman工具。
    # 您将在terraform输出中找到此IAM角色。
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
    # 对于备份，我们使用S3存储桶存储数据。
    # 在此蓝图中，我们创建了一个S3，请查看terraform输出。
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

验证CloudNatvicePG operator是否创建了三个pod：一个主节点和两个备用节点。

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

 operator还创建了三个服务：

1. `-rw`：仅指向集群数据库的主实例
2. `-ro`指向热备用副本，用于只读工作负载
3. `-r`指向任何实例，用于只读工作负载

请注意，`-any`指向所有实例。

检查集群状态的另一种方法是使用CloudNativePG社区提供的[cloudnative-pg kubectl插件](https://cloudnative-pg.io/documentation/1.19/cnpg-plugin/#cloudnativepg-plugin)，

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
