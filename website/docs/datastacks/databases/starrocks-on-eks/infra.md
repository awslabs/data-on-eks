---
title: StarRocks Infrastructure Deployment
sidebar_label: Infrastructure
sidebar_position: 0
---

# StarRocks on EKS Infrastructure

Deploy a production-ready StarRocks cluster on Amazon EKS with Karpenter auto-scaling, EBS CSI driver, and optimized performance for analytical workloads.

## Architecture

This stack deploys StarRocks on EKS with Karpenter for elastic node provisioning and EBS CSI driver for persistent storage. The architecture supports high-performance analytical queries with automatic scaling and fault tolerance.

**Key Components:**
- **Frontend (FE)** - Query planning, metadata management, and cluster coordination
- **Backend (BE)** - Data storage and query execution engines
- **Karpenter** - Provisions optimized EC2 instances based on workload demands
- **EBS CSI Driver** - Persistent storage with GP3 volumes for optimal I/O performance
- **S3 Integration** - External data lake connectivity for data ingestion

## Prerequisites

Before deploying, ensure you have the following tools installed:

- **AWS CLI** - [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- **Terraform** (>= 1.5.0) - [Install Guide](https://developer.hashicorp.com/terraform/install)
- **kubectl** - [Install Guide](https://kubernetes.io/docs/tasks/tools/)
- **Helm** (>= 3.0) - [Install Guide](https://helm.sh/docs/intro/install/)
- **AWS credentials configured** - Run `aws configure` or use IAM roles

## Step 1: Clone Repository & Navigate

```bash
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/data-stacks/starrocks-on-eks
```

## Step 2: Customize Stack Configuration

Edit the stack configuration file to customize deployment:

```bash
vi terraform/data-stack.tfvars
```

Review and customize the configuration:

```hcl title="terraform/data-stack.tfvars"
name   = "starrocks-on-eks"
region = "us-east-1"

# Core StarRocks component
enable_starrocks = true

# Optional: Additional data platform components
enable_ingress_nginx        = true   # Ingress controller
enable_jupyterhub           = true   # Notebooks for data exploration
enable_amazon_prometheus    = true   # Monitoring
enable_superset             = true   # BI dashboards
enable_airflow              = true   # Workflow orchestration
enable_pinot                = true   # Real-time analytics
enable_datahub              = true   # Metadata management
enable_celeborn             = true   # Remote shuffle service
enable_raydata              = true   # Ray for data processing
enable_emr_on_eks           = true   # EMR on EKS
enable_emr_spark_operator   = true   # EMR Spark Operator
enable_nvidia_device_plugin = true   # GPU workloads
```

:::tip Minimal StarRocks Deployment

For a StarRocks-only deployment, set all optional components to `false`:

```hcl
enable_starrocks = true

enable_ingress_nginx        = false
enable_jupyterhub           = false
enable_amazon_prometheus    = false
enable_superset             = false
enable_airflow              = false
enable_pinot                = false
enable_datahub              = false
enable_celeborn             = false
enable_raydata              = false
enable_emr_on_eks           = false
enable_emr_spark_operator   = false
enable_nvidia_device_plugin = false
```

This reduces deployment time and costs by ~60%.

:::

## What Gets Deployed

When you deploy the stack with StarRocks enabled, the following components are provisioned:

### StarRocks Components

| Component | Purpose | Instance Type |
|-----------|---------|---------------|
| **StarRocks Operator** | Manages StarRocks cluster lifecycle via CRD | Runs on core node group |
| **Frontend (FE)** | Query planning, metadata management, cluster coordination | General-purpose Graviton (m-family, on-demand) |
| **Compute Node (CN)** | Stateless query execution for shared-data architecture | Memory-optimized Graviton (r-family, on-demand) |
| **S3 Data Bucket** | Shared-data storage for StarRocks tables | N/A |
| **Pod Identity Role** | IAM access for CN nodes to read/write S3 | N/A |

### CN Autoscaling Configuration

Compute Nodes automatically scale based on resource utilization:

**Scaling Triggers:**
- **CPU Utilization** - Scale up when average > 60%
- **Memory Utilization** - Scale up when average > 60%
- **Min Replicas** - 1
- **Max Replicas** - 10 (configurable)

**Scale-down Policy:** 1 pod per 60 seconds
**Scale-up Policy:** 2 pods per 30 seconds

### Storage Configuration

- **FE Metadata** - Stored in-cluster via StatefulSet PVCs (GP3 EBS)
- **CN Cache** - GP3 PVC (100Gi) for local query cache
- **Table Data** - S3 bucket (shared-data mode) with AES256 encryption

## Step 3: Deploy Infrastructure

Run the deployment script:

```bash
./deploy.sh
```

:::info

**Expected deployment time:** 15-20 minutes

The deployment includes EKS cluster, all platform addons, and the StarRocks operator.

:::

## Step 4: Verify Deployment

The deployment script automatically configures kubectl. Verify the cluster and StarRocks operator:

```bash
# Set kubeconfig (done automatically by deploy.sh)
export KUBECONFIG=kubeconfig.yaml

# Verify StarRocks operator
kubectl get pods -n starrocks
```

### Expected Output

```bash
NAME                                       READY   STATUS    RESTARTS   AGE
kube-starrocks-operator-5d558f7b8b-9s5m6   1/1     Running   0          66m
```

:::info Cluster Name

The EKS cluster is named **`starrocks-on-eks`** (from `data-stack.tfvars`).

To verify:
```bash
aws eks describe-cluster --name starrocks-on-eks --region us-east-1
```

:::

## Step 5: Deploy StarRocks Cluster

Update the S3 bucket and region in the manifest, then apply:

```bash
export STARROCKS_BUCKET=$(cd terraform/_local && terraform output -raw starrocks_s3_bucket_id)
export AWS_REGION=$(cd terraform/_local && terraform output -raw region)

sed -i '' "s|aws_s3_path = s3://<STARROCKS_S3_BUCKET_ID>|aws_s3_path = s3://${STARROCKS_BUCKET}|" examples/starrocks-shared-data.yaml
sed -i '' "s|aws_s3_region = <REGION>|aws_s3_region = ${AWS_REGION}|" examples/starrocks-shared-data.yaml

kubectl apply -f examples/starrocks-shared-data.yaml
```

Wait for pods to be ready (Karpenter provisions new nodes — takes 3-5 minutes):

```bash
kubectl get pods -n starrocks -w
```

## Step 6: Verify StarRocks Deployment

```bash
# Check StarRocks pods
kubectl get pods -n starrocks
```

### Expected Output

```bash
NAME                                       READY   STATUS    RESTARTS   AGE
kube-starrocks-operator-5d558f7b8b-9s5m6   1/1     Running   0          82m
starrocks-shared-data-cn-0                 1/1     Running   0          8m
starrocks-shared-data-fe-0                 1/1     Running   0          10m
starrocks-shared-data-fe-1                 1/1     Running   0          10m
starrocks-shared-data-fe-2                 1/1     Running   0          10m
```

## Step 7: Connect to StarRocks

Connect using a MySQL client pod inside the cluster:

```bash
kubectl run mysql-client -n starrocks --rm -i --restart=Never --image=mysql:8.0 -- \
  mysql -hstarrocks-shared-data-fe-service -P9030 -uroot -e "SHOW DATABASES;"
```

### Expected Output

```bash
Database
_statistics_
information_schema
sys
```

## Next Steps

With the infrastructure deployed, you can now:
1. **[Run TPC-DS Benchmark](./tpcds-benchmark)** - Validate query performance with 1TB dataset
2. **Load Your Data** - Connect to external data sources via Stream Load
3. **Scale the Cluster** - Adjust CN replicas based on workload

## Troubleshooting

**Pods stuck in Pending state:**
```bash
kubectl describe pods -n starrocks
kubectl logs -n karpenter deployment/karpenter
```

**StarRocks connection issues:**
```bash
kubectl logs starrocks-shared-data-fe-0 -n starrocks
kubectl get endpoints -n starrocks
```

## Cleanup

To remove all resources:

```bash
cd terraform/_local
./cleanup.sh
```

:::warning

This will delete all resources including:
- EKS cluster and all workloads
- S3 buckets (StarRocks data)
- VPC and networking resources

Ensure you've backed up any important data before cleanup.

:::
