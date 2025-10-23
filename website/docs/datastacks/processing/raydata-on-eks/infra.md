---
title: Infrastructure Deployment
sidebar_position: 1
---

# Ray Data on EKS - Infrastructure Deployment

Deploy production-ready Ray infrastructure on Amazon EKS for distributed computing, machine learning, and data processing workloads.

## Architecture Overview

The deployment provisions a complete Ray platform on EKS with automatic scaling, monitoring, and GitOps-based management.

### Components

| Layer | Components | Purpose |
|-------|------------|---------|
| **AWS Infrastructure** | VPC (dual CIDR), EKS v1.31+, S3, KMS | Network isolation, managed Kubernetes, storage, encryption |
| **Platform** | Karpenter, ArgoCD, Prometheus Stack | Node autoscaling, GitOps deployment, monitoring |
| **Security** | Pod Identity, cert-manager, external-secrets | IAM authentication, TLS, secrets management |
| **Ray** | KubeRay Operator v1.4.2, RayCluster/Job/Service CRDs | Cluster management, job orchestration |

### Network Design

```
VPC 10.0.0.0/16
├── Public Subnets (3 AZs)   → NAT Gateways, Load Balancers
├── Private Subnets (3 AZs)  → EKS control plane, Ray workloads
└── Secondary 100.64.0.0/16  → Karpenter-managed node pools
```

## Prerequisites

| Requirement | Version | Purpose |
|-------------|---------|---------|
| AWS CLI | v2.x | AWS resource management |
| Terraform | ≥ 1.0 | Infrastructure as Code |
| kubectl | ≥ 1.28 | Kubernetes management |
| Git | Latest | Repository cloning |

**IAM Permissions Required:**
- EKS: Cluster management
- EC2: VPC, Security Groups, Instances
- IAM: Roles, Policies, Pod Identity
- S3: Bucket operations
- CloudWatch: Logs and metrics
- KMS: Encryption keys

## Deployment

### 1. Clone Repository

```bash
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/data-stacks/ray-on-eks
```

### 2. Configure Stack

Edit `terraform/data-stack.tfvars`:

```hcl
name                      = "ray-on-eks"      # Unique cluster name
region                    = "us-west-2"       # AWS region
enable_raydata            = true              # Deploy KubeRay operator
enable_ingress_nginx      = true              # Ray Dashboard access (optional)
enable_jupyterhub         = false             # Interactive notebooks (optional)
enable_amazon_prometheus  = false             # AWS Managed Prometheus (optional)
```

### 3. Deploy Infrastructure

```bash
./deploy.sh
```

**Deployment Process** (~25-30 minutes):
1. ✅ Provision VPC, EKS cluster, S3 bucket
2. ✅ Configure Karpenter for node autoscaling
3. ✅ Deploy ArgoCD for GitOps
4. ✅ Install KubeRay operator and platform addons
5. ✅ Configure kubectl access

### 4. Verify Deployment

```bash
source set-env.sh

# Verify cluster
kubectl get nodes

# Check KubeRay operator
kubectl get pods -n kuberay-operator

# Verify ArgoCD applications
kubectl get applications -n argocd | grep -E "kuberay|karpenter"
```

**Expected Output:**
```
NAME               READY   STATUS    AGE
kuberay-operator   1/1     Running   5m
```

## Access Dashboards

### Ray Dashboard

```bash
# After deploying a RayCluster (see examples below)
kubectl port-forward -n raydata service/<raycluster-name>-head-svc 8265:8265

# Access: http://localhost:8265
```

### ArgoCD UI

```bash
# Get password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port forward
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Access: https://localhost:8080 (admin / <password>)
```

### Grafana Monitoring

```bash
# Get password
kubectl get secret -n kube-prometheus-stack kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d

# Port forward
kubectl port-forward -n kube-prometheus-stack svc/kube-prometheus-stack-grafana 3000:80

# Access: http://localhost:3000 (admin / <password>)
```

## Pod Identity for AWS Access

The infrastructure automatically configures EKS Pod Identity for Ray workloads to securely access AWS services.

### Automatic Configuration

**IAM Role** (`raydata` namespace):
- **S3 Access**: Read/write to data buckets and Iceberg warehouse
- **AWS Glue**: Create and manage Iceberg catalog tables
- **CloudWatch**: Write logs and metrics
- **S3 Tables**: Access S3 Tables API

**Configuration Location**: `/infra/terraform/teams.tf` and `/infra/terraform/ray-operator.tf`

### Usage in Ray Jobs

Enable Pod Identity by specifying the service account:

```yaml
apiVersion: ray.io/v1
kind: RayJob
metadata:
  name: my-ray-job
  namespace: raydata
spec:
  submitterPodTemplate:
    spec:
      serviceAccountName: raydata  # ← Enables Pod Identity

  rayClusterSpec:
    headGroupSpec:
      template:
        spec:
          serviceAccountName: raydata  # ← Enables Pod Identity

    workerGroupSpecs:
      - template:
          spec:
            serviceAccountName: raydata  # ← Enables Pod Identity
```

:::tip Native S3 Access
PyArrow 21.0.0+ automatically uses Pod Identity credentials via `AWS_CONTAINER_CREDENTIALS_FULL_URI`. No boto3 configuration or credential helpers needed.
:::

## Example: Basic Ray Cluster

Deploy a Ray cluster with autoscaling:

```yaml
apiVersion: ray.io/v1
kind: RayCluster
metadata:
  name: raycluster-basic
  namespace: raydata
spec:
  rayVersion: '2.47.1'
  enableInTreeAutoscaling: true

  headGroupSpec:
    rayStartParams:
      dashboard-host: '0.0.0.0'
    template:
      spec:
        serviceAccountName: raydata
        containers:
        - name: ray-head
          image: rayproject/ray:2.47.1-py310
          resources:
            requests: {cpu: "1", memory: "2Gi"}
            limits: {cpu: "2", memory: "4Gi"}

  workerGroupSpecs:
  - replicas: 2
    minReplicas: 1
    maxReplicas: 10
    groupName: workers
    template:
      spec:
        serviceAccountName: raydata
        containers:
        - name: ray-worker
          image: rayproject/ray:2.47.1-py310
          resources:
            requests: {cpu: "2", memory: "4Gi"}
            limits: {cpu: "4", memory: "8Gi"}
```

**Deploy:**
```bash
kubectl apply -f raycluster-basic.yaml

# Verify
kubectl get rayclusters -n raydata
kubectl get pods -n raydata
```

## Advanced Configuration

### Stack Addons

Configure optional components in `terraform/data-stack.tfvars`:

| Addon | Default | Purpose |
|-------|---------|---------|
| `enable_raydata` | true | KubeRay operator |
| `enable_ingress_nginx` | false | Public dashboard access |
| `enable_jupyterhub` | false | Interactive notebooks |
| `enable_amazon_prometheus` | false | AWS Managed Prometheus |

### Karpenter Autoscaling

Karpenter automatically provisions nodes for Ray workloads. Configure NodePools for specific instance types:

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: ray-compute
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          values: ["spot", "on-demand"]
        - key: node.kubernetes.io/instance-type
          values: ["m5.2xlarge", "m5.4xlarge", "c5.4xlarge"]
  limits:
    cpu: "1000"
```

## Troubleshooting

### Operator Issues

```bash
# Check operator status
kubectl get pods -n kuberay-operator
kubectl logs -n kuberay-operator deployment/kuberay-operator --tail=50

# Verify ArgoCD application
kubectl get application kuberay-operator -n argocd
```

**Common Issues:**
| Issue | Cause | Solution |
|-------|-------|----------|
| ImagePullBackOff | Network connectivity | Check VPC NAT gateway, security groups |
| CrashLoopBackOff | Configuration error | Review operator logs for details |
| Pending pods | Insufficient capacity | Check Karpenter logs, node limits |

### Ray Cluster Issues

```bash
# Describe cluster
kubectl describe raycluster <name> -n raydata

# Check pod logs
kubectl logs <ray-head-pod> -n raydata

# Verify Karpenter provisioning
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=100
```

## Cost Optimization

### Recommendations

1. **Spot Instances**: Karpenter uses spot by default (60-90% savings)
2. **Right-Sizing**: Start with smaller instances, scale based on metrics
3. **Autoscaling**: Enable Ray autoscaling to match workload demand
4. **Node Consolidation**: Karpenter automatically consolidates underutilized nodes

### Monitor Costs

```bash
# View provisioned instances
kubectl get nodes -l karpenter.sh/capacity-type

# Check instance types
kubectl get nodes -L node.kubernetes.io/instance-type
```

## Cleanup

```bash
# Delete Ray clusters
kubectl delete rayclusters --all -n raydata

# Destroy infrastructure
./cleanup.sh
```

:::warning Data Loss
This operation destroys all resources including S3 buckets. Back up important data before running cleanup.
:::

## Next Steps

1. **[Spark Logs Processing](spark-logs-processing)** - Production example processing Spark logs with Ray Data and Iceberg
2. **[KubeRay Examples](https://docs.ray.io/en/latest/cluster/kubernetes/examples/index.html)** - Official Ray on Kubernetes guides
3. **[Ray Train](https://docs.ray.io/en/latest/train/train.html)** - Distributed ML training
4. **[Ray Serve](https://docs.ray.io/en/latest/serve/index.html)** - Model serving

## Resources

- [KubeRay Documentation](https://docs.ray.io/en/latest/cluster/kubernetes/index.html)
- [Data-on-EKS GitHub](https://github.com/awslabs/data-on-eks)
- [Karpenter Documentation](https://karpenter.sh/)
