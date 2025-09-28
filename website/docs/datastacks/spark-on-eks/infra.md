---
title: Spark Infrastructure Deployment
sidebar_label: Infrastructure
sidebar_position: 0
---

# Spark on EKS Infrastructure Deployment

Complete guide for deploying production-ready Apache Spark infrastructure on Amazon EKS with ArgoCD, Karpenter, and monitoring.

## Prerequisites

Before deploying, ensure you have the following tools installed:

- **AWS CLI** - [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- **Terraform** (>= 1.0) - [Install Guide](https://developer.hashicorp.com/terraform/install)
- **kubectl** - [Install Guide](https://kubernetes.io/docs/tasks/tools/)
- **Helm** (>= 3.0) - [Install Guide](https://helm.sh/docs/intro/install/)
- **AWS credentials configured** - Run `aws configure` or use IAM roles

## Step 1: Clone Repository & Navigate

```bash
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/data-stacks/spark-on-eks
```

## Step 2: Customize Configuration

Edit the blueprint configuration file to customize addons and settings:

```bash
# Edit configuration file
vim terraform/blueprint.tfvars
```

**Key Configuration Options:**

```hcl title="terraform/blueprint.tfvars"
# info-start
# Basic settings - Customize for your environment
# info-end
region = "us-west-2"
name   = "spark-on-eks"

# highlight-start
# Core addons - Required for basic functionality
# highlight-end
enable_karpenter                    = true
enable_argocd                      = true
enable_spark_operator              = true
enable_kube_prometheus_stack       = true
enable_kubecost                    = true
enable_aws_load_balancer_controller = true

# info-start
# Optional addons - Enable based on your needs
# enable_yunikorn: Advanced scheduling
# enable_spark_history: Job history and metrics
# enable_apache_airflow: Workflow orchestration
# info-end
enable_yunikorn        = false
enable_spark_history   = true
enable_apache_airflow  = false
```

## Step 3: Deploy Infrastructure

Run the deployment script:

```bash
./deploy-blueprint.sh
```

**If deployment fails:**
- Rerun the same command: `./deploy-blueprint.sh`
- If it still fails, debug using kubectl commands or [raise an issue](https://github.com/awslabs/data-on-eks/issues)

**Expected deployment time:** 15-20 minutes

## Step 4: Configure kubectl & Verify

Update kubeconfig and verify deployment:

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-west-2 --name spark-on-eks

# Verify nodes
kubectl get nodes

# Verify core components
kubectl get namespaces
kubectl get applications -n argocd
```

<details>
<summary><strong>✅ Expected Verification Results (Click to expand)</strong></summary>

**Cluster Nodes:**
```bash
# success-start
NAME                                        STATUS   ROLES    AGE     VERSION
ip-100-64-1-137.us-west-2.compute.internal   Ready    <none>   5h57m   v1.30.4-eks-a737599
ip-100-64-2-178.us-west-2.compute.internal   Ready    <none>   5h57m   v1.30.4-eks-a737599
ip-100-64-3-67.us-west-2.compute.internal    Ready    <none>   5h57m   v1.30.4-eks-a737599
ip-100-64-64-22.us-west-2.compute.internal   Ready    <none>   5h57m   v1.30.4-eks-a737599
# success-end
```

**ArgoCD Applications Status:**
```bash
# success-start
NAME                           SYNC STATUS   HEALTH STATUS
aws-load-balancer-controller   Synced        Healthy
cert-manager                   Synced        Healthy
ingress-nginx                  Synced        Healthy
kube-prometheus-stack          Synced        Healthy
spark-operator                 Synced        Healthy
yunikorn                       Synced        Healthy
# success-end
```

**Spark Components:**
```bash
# Spark Operator
kubectl get pods -n spark-operator
# success-start
NAME                                         READY   STATUS    RESTARTS   AGE
spark-operator-controller-556ff74f5c-z6pbg   1/1     Running   0          5h52m
spark-operator-webhook-5d7ff45749-z94g4      1/1     Running   0          5h52m
# success-end

# Spark CRDs
kubectl get crds | grep spark
# success-start
scheduledsparkapplications.sparkoperator.k8s.io         2025-09-27T22:46:45Z
sparkapplications.sparkoperator.k8s.io                  2025-09-27T22:46:45Z
# success-end
```

**Karpenter Node Pools:**
```bash
kubectl get nodepools -n karpenter
# success-start
NAME                         NODECLASS   NODES   READY   AGE
compute-optimized-graviton   default     0       True    3h7m
compute-optimized-x86        default     0       True    3h7m
general-purpose              default     0       True    3h7m
memory-optimized-graviton    default     0       True    3h7m
memory-optimized-x86         default     0       True    3h7m
# success-end
```

</details>

## Step 5: Access ArgoCD & Verify Addons

Access ArgoCD web UI to verify all addons:

```bash
# Port forward to ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
```

**Login Details:**
- **URL:** https://localhost:8080
- **Username:** admin
- **Password:** Use command above

**Verify in ArgoCD UI:**
- All applications should be "Synced" and "Healthy"
- Check: karpenter, spark-operator, kube-prometheus-stack, kubecost

## Step 6: Test with Simple Spark Job

Run a test Spark job to verify everything works:

```bash
# Submit PySpark Pi job
kubectl apply -f blueprints/pyspark-pi-job.yaml

# Monitor job progress
kubectl get sparkapplications -n spark-team-a --watch

# Check logs
kubectl logs -n spark-team-a -l spark-role=driver --follow
```

**Expected Result:**
- Job completes successfully with Pi calculation
- Karpenter automatically provisions compute nodes
- Logs show successful Spark execution

## Troubleshooting

### Common Issues

**Deployment fails with permissions error:**
```bash
# Check AWS credentials
aws sts get-caller-identity

# error-next-line
# Error: Unable to locate credentials
# warning-start
# If you see permission errors, check:
# - AWS CLI is configured: aws configure
# - IAM user has required permissions for EKS, VPC, IAM
# - Region is set correctly
# warning-end
```

**Pods stuck in Pending:**
```bash
# Check node capacity
kubectl describe nodes

# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter
```

**ArgoCD applications not syncing:**
```bash
# Check ArgoCD application status
kubectl get applications -n argocd

# Check specific application
kubectl describe application spark-operator -n argocd
```

## Next Steps

With infrastructure deployed, you can now run any Spark blueprint:

- [EBS PVC Storage](/data-on-eks/docs/datastacks/spark-on-eks/ebs-pvc-storage)
- [NVMe Storage](/data-on-eks/docs/datastacks/spark-on-eks/nvme-storage)
- [Graviton Compute](/data-on-eks/docs/datastacks/spark-on-eks/graviton-compute)
- [YuniKorn Gang Scheduling](/data-on-eks/docs/datastacks/spark-on-eks/yunikorn-gang-scheduling)

## Cleanup

To remove all resources, use the dedicated cleanup script:

```bash
# Navigate to blueprint directory
cd /path/to/data-on-eks/data-stacks/spark-on-eks

# Run cleanup script
./cleanup.sh
```

**If cleanup fails:**
- Rerun the same command: `./cleanup.sh`
- Keep rerunning until all resources are deleted
- Some AWS resources may have dependencies that require multiple cleanup attempts

**⚠️ Warning:** This will delete all resources and data. Make sure to backup any important data first.