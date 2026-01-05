---
title: EMR-EKS-Flink Infrastructure Deployment
sidebar_label: Infrastructure
sidebar_position: 2
---

## Flink on EMR on EKS Infrastructure Deployment

Complete guide for deploying and configuring the Flink on EMR on EKS infrastructure for streaming workloads.

### Prerequisites

Before deploying, ensure you have the following tools installed:

- **AWS CLI** - [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- **Terraform** (>= 1.0) - [Install Guide](https://developer.hashicorp.com/terraform/install)
- **kubectl** - [Install Guide](https://kubernetes.io/docs/tasks/tools/)
- **Helm** (>= 3.0) - [Install Guide](https://helm.sh/docs/intro/install/)
- **AWS credentials configured** - Run `aws configure` or use IAM roles

## Overview

The infrastructure provisions resources required to run Flink Jobs with EMR-on-EKS Flink Kubernetes Operator on an EMR-on-EKS cluster.

- **EKS Cluster** with streaming-optimized configurations
- **Flink Operator** ![EMR Flink Kubernetes operator](https://gallery.ecr.aws/emr-on-eks/flink-kubernetes-operator)
- **State Backend** with S3 storage for fault tolerance
- **Monitoring Stack** with Flink-specific metrics and dashboards

## What Gets Deployed

This stack deploys a complete data platform with **30+ components** automatically via GitOps (ArgoCD).

### EKS Managed Addons

Deployed and managed by AWS EKS:

| Component | Purpose | Managed By |
|-----------|---------|------------|
| `coredns` | DNS resolution | EKS |
| `kube-proxy` | Network proxy | EKS |
| `vpc-cni` | Pod networking with prefix delegation | EKS |
| `eks-pod-identity-agent` | IAM roles for service accounts | EKS |
| `aws-ebs-csi-driver` | Persistent block storage | EKS |
| `aws-mountpoint-s3-csi-driver` | S3 as volumes | EKS |
| `metrics-server` | Resource metrics API | EKS |
| `eks-node-monitoring-agent` | Node-level monitoring | EKS |

### Core Platform Addons

Infrastructure components deployed via ArgoCD:

| Component | Purpose | Category |
|-----------|---------|----------|
| **Karpenter** | Node autoscaling and bin-packing | Compute |
| **ArgoCD** | GitOps application deployment | Platform |
| **cert-manager** | TLS certificate automation | Security |
| **external-secrets** | AWS Secrets Manager integration | Security |
| **ingress-nginx** | Ingress controller | Networking |
| **aws-load-balancer-controller** | ALB/NLB integration | Networking |
| **kube-prometheus-stack** | Prometheus + Grafana monitoring | Observability |
| **aws-for-fluentbit** | Log aggregation to CloudWatch | Observability |

### Data Platform Addons

Data processing and analytics tools:

| Component | Purpose | Use Case |
|-----------|---------|----------|
| **spark-operator** | Apache Spark on Kubernetes | Batch Processing |
| **spark-history-server** | Spark job history and metrics | Observability |
| **yunikorn** | Gang scheduling for batch jobs | Scheduling |
| **jupyterhub** | Interactive notebooks (Python/Scala) | Data Science |
| **flink-operator** | EMR-on-EKS flink operator | Real-time Analytics |
| **strimzi-kafka** | Event streaming platform | Event Streaming |
| **trino** | Distributed SQL query engine | Data Lakehouse |
| **argo-workflows** | Workflow orchestration (DAGs) | Orchestration |
| **argo-events** | Event-driven workflow triggers | Event Processing |
| **keda** | Event-driven pod autoscaling | Autoscaling |

## Quick Start

### Clone the repository

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

### Deploy the infrastructure

```bash
cd data-on-eks/data-stacks/emr-on-eks
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

### Verify the cluster status

```bash
kubectl get nodes
kubectl get pods -n flink-kubernetes-operator
```

To list all the resources created for Flink team to run Flink jobs using this namespace

```bash
kubectl get all,role,rolebinding,serviceaccount --namespace flink-team-a-ns
```



## Cleanup

To remove all resources, use the dedicated cleanup script:

```bash
cd data-on-eks/data-stacks/emr-on-eks
./cleanup.sh
```


