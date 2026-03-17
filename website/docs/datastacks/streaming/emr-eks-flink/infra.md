---
title: Flink Infrastructure Deployment
sidebar_label: Infrastructure
sidebar_position: 2
---

## Flink on EKS Infrastructure Deployment

Complete guide for deploying and configuring the Flink on EKS infrastructure for streaming workloads.

### Prerequisites

Before deploying, ensure you have the following tools installed:

- **AWS CLI** - [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- **Terraform** (>= 1.0) - [Install Guide](https://developer.hashicorp.com/terraform/install)
- **kubectl** - [Install Guide](https://kubernetes.io/docs/tasks/tools/)
- **Helm** (>= 3.0) - [Install Guide](https://helm.sh/docs/intro/install/)
- **AWS credentials configured** - Run `aws configure` or use IAM roles

## Overview

The Flink on EKS infrastructure provides a production-ready foundation for Apache Flink streaming workloads on Amazon EKS. It includes:

- **EKS Cluster** with streaming-optimized configurations
- **Flink Operator** for native Kubernetes Flink job management
- **Kafka Cluster** for event streaming and data ingestion
- **State Backend** with S3 storage for fault tolerance
- **Monitoring Stack** with Flink-specific metrics and dashboards

## Quick Start

### 1. Clone the Repository

```bash
# Clone the repository
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/data-stacks/emr-on-eks
```

### 2. Review Configuration

Edit `terraform/data-stack.tfvars` to customize your deployment:

```hcl
# EMR on EKS Data Stack Configuration
# This file enables EMR on EKS Virtual Clusters for running Spark jobs

name          = "emr-on-eks"
region        = "us-west-2"
deployment_id = "your-unique-id"

# Enable EMR on EKS Virtual Clusters
enable_emr_on_eks = true

# Enable EMR Spark Operator for declarative Spark job management
enable_emr_spark_operator = true

# Enable EMR Flink Kubernetes Operator, replacing the opensource 
enable_emr_flink_operator = true

# Optional: Enable additional addons as needed
enable_ingress_nginx = true
enable_ipv6          = false

```

### 3. Deploy Infrastructure

```bash
./deploy.sh
```

This script will:
1. Initialize Terraform
2. Create VPC and networking (if not exists)
3. Deploy EKS cluster with managed node groups
4. Install Karpenter for autoscaling
5. Install YuniKorn scheduler
6. Create EMR virtual clusters for Team A and Team B
7. Configure IAM roles and service accounts
8. Set up S3 buckets for logs and data
9. Deploy EMR Flink Kubernetes Operator

:::info Deployment Time
Initial deployment takes approximately **30-40 minutes**. Subsequent updates are faster.
:::

### 4. View Terraform Outputs

After deployment completes, view the infrastructure details:

```bash
cd terraform/_local
terraform output
```

You should see output similar to:

```hcl
cluster_arn = "arn:aws:eks:us-west-2:123456789:cluster/emr-on-eks"
cluster_name = "emr-on-eks"
configure_kubectl = "aws eks --region us-west-2 update-kubeconfig --name emr-on-eks"
deployment_id = "abcdefg"
emr_on_eks = {
  "emr-data-team-a" = {
    "cloudwatch_log_group_name" = "/emr-on-eks-logs/emr-on-eks/emr-data-team-a"
    "job_execution_role_arn" = "arn:aws:iam::123456789:role/emr-on-eks-emr-data-team-a"
    "virtual_cluster_id" = "hclg71zute4fm4fpm3m2cobv0"
  }
  "emr-data-team-b" = {
    "cloudwatch_log_group_name" = "/emr-on-eks-logs/emr-on-eks/emr-data-team-b"
    "job_execution_role_arn" = "arn:aws:iam::123456789:role/emr-on-eks-emr-data-team-b"
    "virtual_cluster_id" = "cqt781jwn4vq1wh4jlqdhpj5h"
  }
}
emr_s3_bucket_name = "emr-on-eks-spark-logs-123456789"
region = "us-west-2"
```

:::note

**If deployment fails:**
- Rerun the same command: `./deploy.sh`
- If it still fails, debug using kubectl commands or [raise an issue](https://github.com/awslabs/data-on-eks/issues)

:::


## Post-Deployment Verification

The deployment script automatically configures kubectl. Verify the cluster is ready:

```bash
source set-env.sh

# Set kubeconfig
export KUBECONFIG=kubeconfig.yaml

# Verify cluster nodes
kubectl get nodes

# Check all namespaces
kubectl get namespaces

# Verify ArgoCD applications
kubectl get applications -n argocd
```

:::tip Quick Verification

Run these commands to verify successful deployment:

```bash
# 1. Check nodes are ready
kubectl get nodes
# Expected: 4-5 nodes with STATUS=Ready

# 2. Check ArgoCD applications are synced
kubectl get applications -n argocd
# Expected: All apps showing "Synced" and "Healthy"

# 3. Check Karpenter NodePools ready
kubectl get nodepools

```

:::


## Cleanup

### Infrastructure Cleanup
```bash
# Complete cleanup
./cleanup.sh
```

## Next Steps

After deploying the infrastructure:

- [Getting Started with Flink Jobs](./getting-started)
