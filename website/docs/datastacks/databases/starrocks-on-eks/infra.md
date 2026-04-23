---
title: StarRocks Infrastructure Deployment
sidebar_label: Infrastructure
sidebar_position: 0
---

# StarRocks on EKS Infrastructure

Deploy a production-ready StarRocks stack on Amazon EKS that supports both **shared-data** (S3 + CN cache) and **shared-nothing** (EBS + BE) cluster architectures. The stack includes KEDA-based autoscaling with scale-to-zero capability, Prometheus monitoring, and a pre-built Grafana dashboard.

## Architecture

This stack deploys a complete StarRocks platform with:

- **StarRocks Operator** (v1.11.3) deployed via ArgoCD
- **S3 bucket** for shared-data storage (via Pod Identity)
- **High-performance StorageClass** `gp3-starrocks` (6000 IOPS, 250 MB/s, xfs) for BE nodes
- **KEDA operator** for event-driven autoscaling with scale-to-zero
- **PodMonitors** that automatically discover and scrape all StarRocks clusters
- **Grafana dashboard** pre-configured for multi-cluster filtering
- **Karpenter NodePools** for elastic compute (general-purpose, memory-optimized, compute-optimized Graviton)

### Supported Cluster Types

You can deploy one or both cluster types after the stack is ready. Both use the same FE (Frontend) but differ in the storage architecture:

- **Shared-Data Cluster** — Stateless Compute Nodes (CN) read from S3 with local NVMe cache. Unlimited storage, second-scale elasticity.
- **Shared-Nothing Cluster** — Backend Nodes (BE) store data on local EBS volumes. Consistent low latency, simpler operations.

For a detailed architecture comparison, see the [Benchmark](/docs/benchmarks/starrocks-benchmark) page.

## Prerequisites

- **AWS CLI** — [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- **Terraform** (>= 1.5.0) — [Install Guide](https://developer.hashicorp.com/terraform/install)
- **kubectl** — [Install Guide](https://kubernetes.io/docs/tasks/tools/)
- **Helm** (>= 3.0) — [Install Guide](https://helm.sh/docs/intro/install/)
- **AWS credentials configured** — Run `aws configure` or use IAM roles
- **EKS IAM permissions** — Ability to create EKS clusters, VPCs, IAM roles, S3 buckets

## Step 1: Clone Repository

```bash
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/data-stacks/starrocks-on-eks
```

## Step 2: Customize Stack Configuration

The default `terraform/data-stack.tfvars` deploys a StarRocks-only environment. Edit if you need additional components:

```hcl title="terraform/data-stack.tfvars"
name   = "starrocks-on-eks"
region = "us-east-1"

# Core component
enable_starrocks = true

# Enable optional components if needed
enable_spark_operator       = false
enable_jupyterhub           = false
enable_raydata              = false
enable_amazon_prometheus    = false
enable_superset             = false
enable_ingress_nginx        = false
```

## Step 3: Deploy the Stack

```bash
./deploy.sh
```

:::info Expected deployment time
**15-20 minutes** — includes EKS cluster, all addons, StarRocks operator, KEDA operator, PodMonitors, and the gp3-starrocks StorageClass.
:::

## Step 4: Verify the Stack

```bash
export KUBECONFIG=kubeconfig.yaml

# Verify the StarRocks operator
kubectl get pods -n starrocks

# Verify KEDA operator
kubectl get pods -n keda

# Verify StorageClass
kubectl get storageclass gp3-starrocks

# Verify PodMonitors (Prometheus auto-discovery)
kubectl get podmonitors -n starrocks
```

Expected output:

```text
# starrocks namespace
NAME                                       READY   STATUS    RESTARTS   AGE
kube-starrocks-operator-5d558f7b8b-9s5m6   1/1     Running   0          2m

# keda namespace
NAME                                               READY   STATUS    RESTARTS
keda-operator-xxxxxxxxx                            1/1     Running   0
keda-operator-metrics-apiserver-xxxxxxxxx          1/1     Running   0

# StorageClass
NAME            PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE
gp3-starrocks   ebs.csi.aws.com         Delete          WaitForFirstConsumer

# PodMonitors
NAME           AGE
starrocks-be   2m
starrocks-cn   2m
starrocks-fe   2m
```

## What Gets Deployed

### Infrastructure Components

| Component | Purpose |
|-----------|---------|
| **StarRocks Operator** | Manages `StarRocksCluster` CRDs (FE, BE, CN lifecycle) |
| **S3 Bucket** | Shared-data storage (AES256 encrypted, Pod Identity access) |
| **KEDA Operator** | Event-driven autoscaling with scale-to-zero support |
| **PodMonitors** | Prometheus scraping for FE (port 8030), BE/CN (port 8040) |
| **gp3-starrocks StorageClass** | Production-tuned EBS: 6000 IOPS, 250 MB/s, xfs, encrypted |
| **Pod Identity Role** | IAM access for CN pods to read/write S3 |
| **Grafana Dashboard** | Multi-cluster StarRocks dashboard at `infra/terraform/grafana-dashboards/starrocks-dashboard.json` |

### Karpenter NodePools

The stack reuses existing Karpenter NodePools from the base infrastructure:

| NodePool | NodeGroupType Label | Used For | Instance Families |
|----------|---------------------|----------|-------------------|
| **general-purpose** | `general-purpose` | FE pods | m6g, m7g, m7i (on-demand) |
| **memory-optimized-graviton** | `SparkGravitonMemoryOptimized` | BE pods (shared-nothing), CN pods (shared-data) | r6g, r7g, r7gd, r8g, r8gd |
| **compute-optimized-graviton** | `SparkGravitonComputeOptimized` | Compute-heavy workloads | c6g, c7g, c7gd, c8gd |

Instance type is selected at the StarRocksCluster level via `nodeSelector` with the `karpenter.k8s.aws/instance-family` label.

### CN Autoscaling with KEDA

The stack deploys a **KEDA ScaledObject** for the shared-data CN nodes that enables:

- **Scale-to-zero** — CN replicas drop to 0 during idle periods (saves ~$1,400/month per CN instance)
- **Prometheus-based triggers** — scales on StarRocks query rate (`starrocks_fe_query_total`) and active connections
- **Fast activation** — first query (>0.1 QPS) triggers scale from 0 → 1
- **Cooldown protection** — 300s stabilization window prevents scale-down thrashing

**Scaling behavior:**

| Parameter | Value | Purpose |
|-----------|-------|---------|
| Min replicas | 0 | Scale to zero during idle |
| Max replicas | 10 | Upper bound for bursts |
| Activation threshold | 0.1 QPS | Triggers scale from 0 → 1 |
| Scale-up | 2 pods / 30s | Fast response to query bursts |
| Scale-down | 1 pod / 60s | Conservative to keep cache warm |
| Cooldown | 300s | Prevents thrashing between queries |

:::warning Replicas Field Conflict
When KEDA is managing CN replicas, the StarRocksCluster CR must **NOT** set `replicas` under `starRocksCnSpec`. KEDA creates an underlying HPA that manages the replica count. If `replicas` is set, you'll see a conflict.

The example manifest `examples/starrocks-shared-data.yaml` uses a fixed `replicas: 3` for benchmark consistency. To use KEDA autoscaling, remove that field and re-apply the manifest.
:::

:::tip Cold Cache Trade-off
Scaling CN to 0 means losing the NVMe data cache. The first query after scale-up reads from S3 (~10-50ms per read) until the cache rebuilds. For latency-sensitive workloads, consider setting `minReplicaCount: 1` in the ScaledObject to keep at least one warm CN.
:::

## Step 5: Deploy a StarRocks Cluster

The stack ships with two pre-built cluster examples. Deploy either or both.

### Option A: Shared-Data Cluster (S3 + CN)

The deploy script automatically substitutes the S3 bucket ID and region from Terraform outputs:

```bash
./examples/deploy-shared-data.sh
```

This creates a StarRocksCluster named `starrocks-shared-data` with:
- 3× FE (m6g.2xlarge) for metadata + query coordination
- 3× CN (r8gd.8xlarge) with 1.9TB local NVMe for data cache
- S3-backed storage with automatic writes

### Option B: Shared-Nothing Cluster (EBS + BE)

```bash
./examples/deploy-shared-nothing.sh
```

This creates a StarRocksCluster named `starrocks-shared-nothing` with:
- 3× FE (m6g.2xlarge)
- 3× BE (r8g.8xlarge) with 500Gi gp3-starrocks EBS PVCs per BE

### Monitor cluster creation

```bash
kubectl get pods -n starrocks -w
```

Karpenter provisions new nodes as pods are scheduled — expect 3-5 minutes for nodes to come up.

Once all pods are `Running`, verify the cluster:

```bash
kubectl get starrockscluster -n starrocks
```

Expected:

```text
NAME                       PHASE     FESTATUS   BESTATUS   CNSTATUS
starrocks-shared-data      running   running               running
starrocks-shared-nothing   running   running    running
```

## Step 6: Connect to StarRocks

### Via Port-Forward (local development)

```bash
# Shared-Data on port 9030
kubectl port-forward svc/starrocks-shared-data-fe-service 9030:9030 -n starrocks

# Shared-Nothing on port 9031 (different local port to avoid conflicts)
kubectl port-forward svc/starrocks-shared-nothing-fe-service 9031:9030 -n starrocks
```

Connect with any MySQL client:

```bash
mysql -h 127.0.0.1 -P 9030 -u root   # shared-data
mysql -h 127.0.0.1 -P 9031 -u root   # shared-nothing
```

### Via Internal NLB (in-VPC clients)

The shared-data FE service is exposed via an AWS NLB:

```bash
NLB=$(kubectl get svc starrocks-shared-data-fe-service -n starrocks \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
mysql -h $NLB -P 9030 -u root
```

### GUI Clients (Mac)

Any MySQL-compatible client works — examples:

| Tool | Install |
|------|---------|
| **DBeaver** (free) | `brew install --cask dbeaver-community` |
| **TablePlus** | `brew install --cask tableplus` |
| **Sequel Ace** (free) | `brew install --cask sequel-ace` |

Create connections as **MySQL** with host `127.0.0.1`, port `9030`/`9031`, user `root`, no password.

## Step 7: Access Grafana

```bash
# Port-forward Grafana
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring

# Get admin password
kubectl get secret grafana-admin-secret -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

Open http://localhost:3000 (user: `admin`). Import the StarRocks dashboard from `infra/terraform/grafana-dashboards/starrocks-dashboard.json`. Select your Prometheus datasource and cluster name from the dropdowns — metrics should appear immediately.

## Observing KEDA Autoscaling

```bash
# View the ScaledObject
kubectl get scaledobject -n starrocks

# View the underlying HPA that KEDA creates
kubectl get hpa -n starrocks

# View current replica count
kubectl get starrockscluster starrocks-shared-data -n starrocks \
  -o jsonpath='{.status.starRocksCnStatus.failedInstances}'

# Watch CN pods scale
kubectl get pods -n starrocks -l app.kubernetes.io/component=cn -w
```

To test scale-to-zero behavior, let the cluster sit idle for >5 minutes (cooldown period). Then run a query — you should see CN scale from 0 → 1 within ~30-60 seconds.

## Next Steps

- **[Run TPC-DS Benchmark](./tpcds-benchmark)** — validate performance with 1TB dataset
- **[Compare Shared-Data vs Shared-Nothing](/docs/benchmarks/starrocks-benchmark)** — see benchmark results
- **Load your own data** — use [Stream Load](https://docs.starrocks.io/docs/loading/StreamLoad/), Broker Load, or external catalogs
- **Connect external catalogs** — Iceberg, Hive, JDBC, Paimon sources

## Troubleshooting

### Pods stuck in Pending state

```bash
kubectl describe pods -n starrocks
kubectl logs -n karpenter deployment/karpenter
kubectl get nodeclaims
```

Common causes:
- Karpenter provisioning delay (3-5 min expected)
- Instance type unavailable in the AZ (check Karpenter logs for `InstanceTypeNotAvailable`)
- Node selector mismatch (e.g., requesting `r8gd` when Karpenter can only provision `r7gd`)

### FE not connecting to S3

```bash
# Check Pod Identity is working
kubectl describe pod starrocks-shared-data-fe-0 -n starrocks | grep -A3 "Environment"

# Verify the ServiceAccount has the role
kubectl get sa starrocks-sa -n starrocks -o yaml

# Check FE logs for S3 errors
kubectl logs starrocks-shared-data-fe-0 -n starrocks | grep -i s3
```

### KEDA ScaledObject not scaling

```bash
# Check the ScaledObject status
kubectl describe scaledobject starrocks-cn-scaler -n starrocks

# Check the HPA KEDA created
kubectl describe hpa -n starrocks

# Check KEDA operator logs
kubectl logs -n keda deployment/keda-operator

# Verify Prometheus is reachable from KEDA
kubectl exec -n keda deployment/keda-operator -- \
  wget -qO- http://kube-prometheus-kube-prome-prometheus.kube-prometheus:9090/-/healthy
```

## Cleanup

To remove all resources:

```bash
cd data-stacks/starrocks-on-eks
./cleanup.sh
```

:::warning
This will delete all resources including the EKS cluster, S3 buckets (with data), and VPC. Back up any important data before cleanup.
:::
