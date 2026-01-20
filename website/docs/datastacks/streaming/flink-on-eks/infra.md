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

```bash
# Clone the repository
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/data-stacks/flink-on-eks

# Deploy the infrastructure
./deploy.sh

# Verify deployment
kubectl get nodes
kubectl get pods -n flink-operator
```


## Architecture Components

### Core Infrastructure

#### Apache Flink Operator
- Native Kubernetes CRDs for Flink jobs
- JobManager and TaskManager management
- State backend configuration
- Checkpoint coordination
- Recovery and scaling

#### State Management
- S3-backed state storage
- RocksDB local state
- Checkpoint configuration
- Savepoint management
- Recovery mechanisms

## Deployment Process

### 1. Infrastructure Deployment
```bash
# Automated deployment process
./deploy.sh
```

:::note

**If deployment fails:**
- Rerun the same command: `./deploy.sh`
- If it still fails, debug using kubectl commands or [raise an issue](https://github.com/awslabs/data-on-eks/issues)

:::

:::info

**Expected deployment time:** 15-20 minutes

:::


### 2. Post-Deployment Verification

The deployment script automatically configures kubectl. Verify the cluster is ready:

```bash
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
