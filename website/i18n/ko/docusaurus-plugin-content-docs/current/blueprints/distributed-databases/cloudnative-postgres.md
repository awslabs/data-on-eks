---
sidebar_position: 2
sidebar_label: CloudNativePG PostgreSQL
---

# CloudNativePG Operator를 사용하여 EKS에 PostgreSQL 데이터베이스 배포

## 소개

**CloudNativePG**는 [Kubernetes](https://kubernetes.io)에서 [PostgreSQL](https://www.postgresql.org/) 워크로드를 관리하도록 설계된 오픈소스 [operator](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)입니다.

고가용성과 읽기 전용 쿼리 오프로딩을 위해 선택한 Kubernetes 네임스페이스에 공존하는 단일 프라이머리와 선택적 수의 복제본으로 구성된 PostgreSQL 클러스터를 나타내는 `Cluster`라는 새로운 Kubernetes 리소스를 정의합니다.

동일한 Kubernetes 클러스터에 있는 애플리케이션은 operator가 전적으로 관리하는 서비스를 사용하여 PostgreSQL 데이터베이스에 액세스할 수 있으며, 장애 조치(failover) 또는 스위치오버(switchover) 후 프라이머리 역할 변경에 대해 걱정할 필요가 없습니다. Kubernetes 클러스터 외부에 있는 애플리케이션은 TCP를 통해 Postgres를 노출하도록 Service 또는 Ingress 객체를 구성해야 합니다.
웹 애플리케이션은 PgBouncer 기반의 네이티브 연결 풀러를 활용할 수 있습니다.

CloudNativePG는 원래 [EDB](https://www.enterprisedb.com)에서 구축한 후 Apache License 2.0으로 오픈소스로 출시되어 2022년 4월 CNCF Sandbox에 제출되었습니다.
[소스 코드 저장소는 GitHub에 있습니다](https://github.com/cloudnative-pg/cloudnative-pg).

프로젝트에 대한 자세한 내용은 이 [링크](https://cloudnative-pg.io)에서 확인할 수 있습니다.

## 솔루션 배포

배포 단계를 살펴보겠습니다.

### 사전 요구 사항

다음 도구가 로컬 머신에 설치되어 있는지 확인하세요.

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [psql](https://formulae.brew.sh/formula/libpq)

### CloudNativePG Operator로 EKS 클러스터 배포

먼저 저장소를 복제합니다.

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

cloudnative-postgres 폴더로 이동하고 `install.sh` 스크립트를 실행합니다. 기본적으로 스크립트는 EKS 클러스터를 `us-west-2` 리전에 배포합니다. 리전을 변경하려면 `variables.tf`를 업데이트하세요. 이때 다른 입력 변수를 업데이트하거나 terraform 템플릿에 다른 변경을 수행할 수도 있습니다.

```bash
cd data-on-eks/distributed-databases/cloudnative-postgres

./install.sh
```

### 배포 확인

Amazon EKS 클러스터 확인

```bash
aws eks describe-cluster --name cnpg
```

로컬 kubeconfig를 업데이트하여 kubernetes 클러스터에 액세스할 수 있도록 합니다.

```bash
aws eks update-kubeconfig --name cnpg --region us-west-2
```

먼저 클러스터에서 워커 노드가 실행 중인지 확인합니다.

```bash
kubectl get nodes
NAME                                        STATUS   ROLES    AGE   VERSION
ip-10-1-10-68.us-west-2.compute.internal    Ready    <none>   94m   v1.32.8-eks-99d6cc0
ip-10-1-11-124.us-west-2.compute.internal   Ready    <none>   97m   v1.32.8-eks-99d6cc0
ip-10-1-11-187.us-west-2.compute.internal   Ready    <none>   97m   v1.32.8-eks-99d6cc0
ip-10-1-12-158.us-west-2.compute.internal   Ready    <none>   97m   v1.32.8-eks-99d6cc0
```

다음으로 모든 파드가 실행 중인지 확인합니다.

```bash
kubectl get pods --namespace=monitoring
NAME                                                     READY   STATUS    RESTARTS   AGE
alertmanager-prometheus-kube-prometheus-alertmanager-0   2/2     Running   0          94m
prometheus-grafana-679d5bbf76-mvtp5                      3/3     Running   0          91m
prometheus-kube-prometheus-operator-579b8cf467-h7fwm     1/1     Running   0          83m
prometheus-kube-state-metrics-6d476dd454-p52mr           1/1     Running   0          94m
prometheus-prometheus-kube-prometheus-prometheus-0       2/2     Running   0          80m

kubectl get pods --namespace=cnpg-system
NAME                                   READY   STATUS    RESTARTS   AGE
cnpg-cloudnative-pg-85949d9bc8-dp8vq   1/1     Running   0          83m
```

### PostgreSQL 클러스터 배포

먼저 `ebs-csi-driver`를 사용하는 storageclass, demo 네임스페이스, 데이터베이스 인증을 위한 로그인/비밀번호용 kubernetes secrets `app-auth`를 생성해야 합니다. 모든 kubernetes 매니페스트는 examples 폴더를 확인하세요.

#### 스토리지

Amazon EKS 및 EC2로 Kubernetes에서 고도로 확장 가능하고 내구성 있는 자체 관리형 PostgreSQL 데이터베이스를 실행하려면 고성능과 내결함성을 제공하는 Amazon Elastic Block Store(EBS) 볼륨을 사용하는 것이 좋습니다. 이 사용 사례에 권장되는 EBS 볼륨 유형은 다음과 같습니다:

1.프로비저닝된 IOPS SSD(io2 또는 io1):

- 데이터베이스와 같은 I/O 집약적 워크로드용으로 설계되었습니다.
- 일관되고 저지연 성능을 제공합니다.
- 요구 사항에 따라 특정 수의 IOPS(초당 입출력 작업)를 프로비저닝할 수 있습니다.
- 볼륨당 최대 64,000 IOPS와 1,000 MB/s 처리량을 제공하여 까다로운 데이터베이스 워크로드에 적합합니다.

2.범용 SSD(gp3 또는 gp2):

- 대부분의 워크로드에 적합하며 성능과 비용 간의 균형을 제공합니다.
- 볼륨당 3,000 IOPS와 125 MB/s 처리량의 기준 성능을 제공하며 필요한 경우 늘릴 수 있습니다(gp3의 경우 최대 16,000 IOPS와 1,000 MB/s).
- I/O가 덜 집약적인 데이터베이스 워크로드 또는 비용이 주요 관심사인 경우에 권장됩니다.

`examples` 폴더에서 두 storageclass 템플릿을 찾을 수 있습니다.

```bash
kubectl create -f examples/storageclass.yaml

kubectl create -f examples/auth-prod.yaml
```

Kubernetes의 다른 배포와 마찬가지로 PostgreSQL 클러스터를 배포하려면 원하는 `Cluster`를 정의하는 구성 파일을 적용해야 합니다. CloudNativePG operator는 두 가지 유형의 새 데이터베이스 부트스트래핑을 제공합니다:

1. 빈 클러스터 부트스트랩
2. 다른 클러스터에서 부트스트랩

이 첫 번째 예제에서는 `initdb` 플래그를 사용하여 새 빈 데이터베이스 클러스터를 만들겠습니다. IRSA 구성용 IAM role _1_과 백업 복원 프로세스 및 WAL 아카이빙용 S3 버킷 _2_를 수정하여 아래 템플릿을 사용하겠습니다. Terraform이 이미 이를 생성했으므로 `terraform output`을 사용하여 이러한 매개변수를 추출합니다:

```bash
cd data-on-eks/distributed-databases/cloudnative-postgres

terraform output

barman_backup_irsa = "arn:aws:iam::<your_account_id>:role/cnpg-prod-irsa"
barman_s3_bucket = "XXXX-cnpg-barman-bucket"
configure_kubectl = "aws eks --region us-west-2 update-kubeconfig --name cnpg"
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
  # Choose your PostGres Database Version
  imageName: ghcr.io/cloudnative-pg/postgresql:17.2
  # Number of Replicas
  instances: 3
  startDelay: 300
  stopDelay: 300
  replicationSlots:
    highAvailability:
      enabled: true
    updateInterval: 300
  primaryUpdateStrategy: unsupervised
  serviceAccountTemplate:
    # For backup and restore, we use IRSA for barman tool.
    # You will find this IAM role on terraform outputs.
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
  # Choose the right storageclass for type of workload.
  storage:
    storageClass: storageclass-io2 # change this if you want to use a different storage class (ex: storageclass-gp3)
    size: 4Gi
  walStorage:
    storageClass: storageclass-io2 # change this if you want to use a different storage class (ex: storageclass-gp3)
    size: 4Gi
  monitoring:
    enablePodMonitor: true
  bootstrap:
    initdb: # Deploying a new cluster
      database: WorldDB
      owner: app
      secret:
        name: app-auth
  backup:
    barmanObjectStore:
    # For backup, we S3 bucket to store data.
    # On this Blueprint, we create an S3 check the terraform output for it.
      destinationPath: s3://<your-s3-barman-bucket> # ie: s3://xxxx-cnpg-barman-bucket, #2
      s3Credentials:
        inheritFromIAMRole: true
      wal:
        compression: gzip
        maxParallel: 8
    retentionPolicy: "30d"

  resources:
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

업데이트가 완료되면 템플릿을 적용할 수 있습니다.

```bash
kubectl create -f examples/cluster-prod.yaml

```

CloudNativePG operator가 세 개의 파드(하나의 프라이머리와 두 개의 스탠바이)를 생성했는지 확인합니다.

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

operator는 또한 세 개의 서비스를 생성했습니다:

1. `-rw`: 클러스터 데이터베이스의 프라이머리 인스턴스만 가리킵니다.
2. `-ro`: 읽기 전용 워크로드를 위한 핫 스탠바이 복제본만 가리킵니다.
3. `-r`: 읽기 전용 워크로드를 위한 모든 인스턴스를 가리킵니다.

`-any`는 모든 인스턴스를 가리킵니다.

클러스터 상태를 확인하는 또 다른 방법은 CloudNativePG 커뮤니티에서 제공하는 [cloudnative-pg kubectl 플러그인](https://cloudnative-pg.io/documentation/1.19/cnpg-plugin/#cloudnativepg-plugin)을 사용하는 것입니다.

```bash
kubectl cnpg status prod -n demo

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

### 모니터링

이 예제에서는 CloudNativePG가 생성한 모든 데이터베이스 클러스터를 모니터링하기 위해 Prometheus와 Grafana 애드온을 배포했습니다. Grafana 대시보드를 확인해 보겠습니다.

```bash
kubectl -n monitoring port-forward svc/prometheus-grafana 8080:80

```

다음 명령을 실행하여 사용자 이름과 비밀번호를 가져올 수 있습니다:

```bash
kubectl get secret prometheus-grafana -n monitoring -o jsonpath="{.data.admin-user}" | base64 --decode ; echo

kubectl get secret prometheus-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

이제 [http://localhost:8080](http://localhost:8080) 으로 이동하여 Grafana 대시보드에 로그인할 수 있습니다.

![CloudNativePG Grafana Dashboard](img/cnpg_garfana_dashboard.png)

### 데이터베이스 샘플 가져오기

ingress-controller 또는 kubernetes service type `LoadBalancer`를 사용하여 클러스터 외부에 데이터베이스를 노출할 수 있습니다. 그러나 EKS 클러스터 내부에서 사용하려면 kubernetes service `prod-rw`와 `prod-ro`를 사용할 수 있습니다.
이 섹션에서는 `kubectl port-forward`를 사용하여 읽기-쓰기 서비스 `-rw`를 노출하겠습니다.

```bash

kubectl port-forward svc/prod-rw 5432:5432 -n demo

```

먼저 `app-auth` secret을 가져옵니다.

```bash
kubectl get secret app-auth -n demo -o=jsonpath='{.data.password}' | base64 --decode ; echo
```

이제 `app-auth` secrets의 자격 증명을 사용하여 `psql` cli로 `world.sql`을 데이터베이스 인스턴스 WorldDB에 가져옵니다.

```bash

psql -h localhost --port 5432 -U app -d WorldDB < world.sql

# Quick check on db tables.

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

### S3로 백업 생성

이제 데이터가 있는 실행 중인 데이터베이스가 있으므로 CloudNativePG operator는 [barman](https://pgbarman.org/) 도구를 사용한 백업-복원 기능을 제공합니다. CloudNativePG를 사용하면 데이터베이스 관리자가 온디맨드 데이터베이스 또는 예약된 백업을 생성할 수 있으며, 자세한 내용은 [문서](https://cloudnative-pg.io/documentation/1.19/backup_recovery/)를 참조하세요.

이 예제에서는 Backup 객체를 생성하여 백업 프로세스를 즉시 시작합니다.

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

실행하는 데 몇 분이 걸리며, 백업 프로세스를 확인합니다.

```bash
kubectl describe backup ondemand

Events:
  Type    Reason     Age   From                   Message
  ----    ------     ----  ----                   -------
  Normal  Starting   60s   cloudnative-pg-backup  Starting backup for cluster prod
  Normal  Starting   60s   instance-manager       Backup started
  Normal  Completed  56s   instance-manager       Backup completed
```

### 복원

복원의 경우 S3의 백업 파일을 사용하여 새 클러스터를 부트스트랩합니다. 백업 도구 _barman_은 복원 프로세스를 관리하지만 kubernetes secrets의 백업 및 복원을 지원하지 않습니다. 이는 AWS SecretsManager와 함께 csi-secrets-driver를 사용하는 것처럼 별도로 관리해야 합니다.

먼저 prod 데이터베이스를 삭제합니다.

```bash
kubectl delete cluster prod -n demo

```

그런 다음 S3 버킷과 IAM role로 `examples/cluster-restore.yaml` 템플릿을 업데이트합니다. 복원 템플릿에서 CloudNativePG는 `externalClusters`를 사용하여 데이터베이스를 가리킵니다.

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

새 클러스터를 생성할 때 operator는 Cluster 리소스에 설명된 대로 IRSA 구성으로 ServiceAccount를 생성합니다. trust policy가 올바른 ServiceAccount를 가리키는지 확인하세요.

데이터가 예상대로 복구되었는지 확인합니다.

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

## 결론

CloudNativePG operator는 [Operator Capability Levels](https://operatorframework.io/operator-capabilities/)에서 Level 5를 제공합니다. 이 예제에서는 모니터링 스택(Prometheus 및 grafana)과 함께 애드온으로 operator를 배포하는 블루프린트를 공유합니다. 많은 기능 중에서 클러스터 생성, 데이터 가져오기 및 재해(또는 클러스터 삭제) 시 데이터베이스 복원에 대한 몇 가지 예제를 강조했습니다. 더 많은 기능은 이 [문서](https://cloudnative-pg.io/documentation/1.19/)에서 확인할 수 있습니다.
