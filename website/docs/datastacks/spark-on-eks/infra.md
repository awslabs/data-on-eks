---
title: Spark Infrastructure Deployment
sidebar_label: Infrastructure
sidebar_position: 0
---

# Spark on EKS Infrastructure Deployment

Complete guide for deploying and configuring the Spark on EKS infrastructure using the data-stacks approach.

## Overview

The Spark on EKS infrastructure provides a production-ready foundation for Apache Spark workloads on Amazon EKS. It includes:

- **EKS Cluster** with managed addons and optimized configurations
- **Karpenter** for intelligent auto-scaling and cost optimization
- **Spark Operator** for native Kubernetes Spark job management
- **Monitoring Stack** with Prometheus, Grafana, and custom dashboards
- **ArgoCD** for GitOps-based infrastructure management

## Quick Start

```bash
# Clone the repository
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/data-stacks/spark-on-eks

# Deploy the infrastructure
./deploy-blueprint.sh

# Verify deployment
kubectl get nodes
kubectl get pods -n spark-operator
```

## Configuration Options

### Blueprint Configuration (`terraform/blueprint.tfvars`)

#### Basic Settings
```hcl
# Deployment configuration
region = "us-west-2"
name   = "spark-on-eks"

# Cluster settings
eks_cluster_version = "1.33"
vpc_cidr           = "10.0.0.0/16"
secondary_cidrs    = ["100.64.0.0/16"]
```

#### Spark-Specific Components
```hcl
# Spark platform
enable_spark_operator         = true   # Spark job management
enable_spark_history_server   = true   # Job monitoring
enable_yunikorn               = false  # Advanced scheduler (optional)
```

#### Monitoring & Observability
```hcl
# Monitoring stack
enable_kube_prometheus_stack  = true   # Prometheus + Grafana
enable_kubecost              = false  # Cost monitoring
enable_aws_for_fluentbit     = false  # Log aggregation
```

#### Networking & Security
```hcl
# Networking
enable_ingress_nginx         = true   # Load balancing
enable_cert_manager          = false  # TLS management
enable_external_secrets      = false  # Secret management
```

## Deployment Process

### 1. Prerequisites Check
```bash
# Required tools
- AWS CLI configured
- Terraform >= 1.0
- kubectl >= 1.28
- Git

# AWS permissions
- EKS management
- VPC and EC2 operations
- IAM role management
- S3 access for state
```

### 2. Infrastructure Deployment
```bash
# Automated deployment process
./deploy-blueprint.sh

# Manual step-by-step deployment
cd terraform/_local
terraform init
terraform plan
terraform apply
```

### 3. Post-Deployment Verification

#### **Important: Directory Navigation** 🚨
After deployment, you'll be in the main spark-on-eks directory, but Terraform state is in a subdirectory:

```bash
# Current location after deployment
pwd
# Output: /path/to/data-on-eks/data-stacks/spark-on-eks

# Navigate to Terraform directory for terraform commands
cd terraform/_local

# Now you can run terraform commands
terraform output
terraform show
terraform state list

# To return to main directory
cd ../..
# Or: cd ../../  (back to spark-on-eks root)
```

#### **Getting Deployment Information**
```bash
# From terraform/_local directory - get all outputs
cd terraform/_local
terraform output

# Get specific values
terraform output cluster_name
terraform output region
terraform output vpc_id
terraform output argocd_password

# Get cluster credentials (if needed)
aws eks update-kubeconfig --region $(terraform output -raw region) --name $(terraform output -raw cluster_name)
```

#### **Verify Infrastructure Components**
```bash
# Return to main directory first
cd ../..  # Back to spark-on-eks root

# Verify cluster (from any directory with proper kubeconfig)
kubectl get nodes
kubectl get pods --all-namespaces

# Check Spark Operator
kubectl get sparkapplications -n spark-operator

# Access monitoring
kubectl port-forward svc/kube-prometheus-stack-grafana -n kube-prometheus-stack 3000:80
```

## Architecture Components

### Core Infrastructure

#### Amazon EKS Cluster
- Kubernetes version: 1.33
- Managed node groups with Karpenter
- VPC with dual CIDR support
- Enhanced cluster logging
- Pod identity for secure access

#### Karpenter Auto-Scaling
- Spot and on-demand instance support
- Multi-AZ deployment
- Instance type optimization
- Automatic node termination
- Custom node pools for workloads

### Data Platform Components

#### Spark Operator
- Native Kubernetes CRDs
- Webhook validation
- Resource management
- Job lifecycle management
- History server integration

#### Monitoring Stack
- Prometheus metrics collection
- Grafana dashboards
- Spark-specific metrics
- Karpenter monitoring
- Cost tracking with Kubecost

## Security Configuration

### IAM Roles for Service Accounts (IRSA)
```yaml
# Spark service account with S3 access
apiVersion: v1
kind: ServiceAccount
metadata:
  name: spark-operator-spark
  namespace: spark-operator
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/spark-s3-access
```

### Network Policies
```yaml
# Spark pod communication
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: spark-communication
  namespace: spark-operator
spec:
  podSelector:
    matchLabels:
      app: spark
  policyTypes:
  - Ingress
  - Egress
```

## Monitoring & Observability

### Prometheus Metrics
- spark_application_duration
- spark_executor_memory_usage
- spark_driver_cpu_utilization
- spark_job_completion_rate

### Grafana Dashboards
- EKS Cluster Overview
- Spark Application Metrics
- Karpenter Node Management
- Cost Analysis (with Kubecost)
- Resource Utilization

### Alerting Rules
- SparkApplicationFailed
- KarpenterNodeProvisioningFailure
- HighMemoryUtilization
- CostThresholdExceeded

## Cost Optimization

### Spot Instance Configuration
```hcl
# Cost-optimized settings
karpenter_spot_allocation_strategy = "diversified"
karpenter_on_demand_percentage    = 20
```

### Resource Right-Sizing
```yaml
# Optimized executor configuration
spec:
  executor:
    memory: "4g"
    cores: 2
    instances: 4
  driver:
    memory: "2g"
    cores: 1
```

### Auto-Scaling Policies
```yaml
# Efficient scaling
spec:
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 30s
    expireAfter: 30m
```

## Deployment Verification

### Step-by-Step Verification Guide

#### 1. Infrastructure Components
```bash
# Verify EKS cluster is ready
kubectl get nodes
kubectl cluster-info

# Check managed addons
kubectl get pods -n kube-system | grep -E "(coredns|aws-node|kube-proxy)"

# Verify storage classes
kubectl get storageclass
```

#### 2. ArgoCD Installation and Status
```bash
# Check ArgoCD pods are running
kubectl get pods -n argocd

# Verify ArgoCD server is ready
kubectl get svc -n argocd argocd-server

# Access ArgoCD UI (in separate terminal)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

#### 3. ArgoCD Applications Verification
```bash
# Check all ArgoCD applications
kubectl get applications -n argocd

# Verify core addons are synced
kubectl get applications -n argocd -o wide

# Expected applications:
# - karpenter (core addon)
# - aws-load-balancer-controller (core addon)
# - kube-prometheus-stack (core addon)
# - spark-operator (data addon)
# - spark-history-server (data addon)

# Check application health
argocd app list

# Get detailed application status
argocd app get karpenter
argocd app get spark-operator
```

#### 4. Core Addons Verification
```bash
# Karpenter
kubectl get pods -n karpenter
kubectl get nodepools
kubectl get ec2nodeclasses

# AWS Load Balancer Controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Monitoring Stack
kubectl get pods -n kube-prometheus-stack
kubectl get svc -n kube-prometheus-stack | grep grafana

# Spark Operator
kubectl get pods -n spark-operator
kubectl get customresourcedefinitions | grep sparkoperator

# Spark History Server
kubectl get pods -n spark-operator -l app.kubernetes.io/name=spark-history-server
```

#### 5. Access Monitoring Dashboards
```bash
# Grafana access
kubectl port-forward svc/kube-prometheus-stack-grafana -n kube-prometheus-stack 3000:80

# Default Grafana credentials:
# Username: admin
# Password: prom-operator

# ArgoCD access
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Username: admin
# Password: (get from secret above)
```

## Deployment Validation

### Complete Validation Checklist

#### ✅ **Phase 1: Core Infrastructure**
```bash
# 1. EKS Cluster Health
kubectl get nodes --no-headers | wc -l  # Should show managed nodes
kubectl get nodes -o wide | grep Ready   # All nodes should be Ready

# 2. Managed Addons Status
kubectl get pods -n kube-system -l k8s-app=kube-dns       # CoreDNS
kubectl get pods -n kube-system -l k8s-app=aws-node       # VPC CNI
kubectl get pods -n kube-system -l k8s-app=kube-proxy     # Kube-proxy

# 3. Storage Classes Available
kubectl get storageclass | grep -E "(gp3|gp2)"           # EBS storage

# 4. VPC Configuration
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=spark-on-eks-vpc" --query 'Vpcs[0].State'
```

#### ✅ **Phase 2: ArgoCD Setup**
```bash
# 1. ArgoCD Server Running
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# 2. ArgoCD Applications Deployed
EXPECTED_APPS=("karpenter" "aws-load-balancer-controller" "kube-prometheus-stack" "spark-operator" "spark-history-server")
for app in "${EXPECTED_APPS[@]}"; do
  kubectl get application $app -n argocd >/dev/null 2>&1 && echo "✅ $app found" || echo "❌ $app missing"
done

# 3. ArgoCD Applications Healthy
kubectl get applications -n argocd -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.health.status}{"\t"}{.status.sync.status}{"\n"}{end}'

# Expected output: All applications should show "Healthy" and "Synced"
```

#### ✅ **Phase 3: Core Addons**
```bash
# 1. Karpenter Ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=karpenter -n karpenter --timeout=300s
kubectl get nodepools -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'

# 2. AWS Load Balancer Controller
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=aws-load-balancer-controller -n kube-system --timeout=300s

# 3. Monitoring Stack
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n kube-prometheus-stack --timeout=300s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n kube-prometheus-stack --timeout=300s

# 4. Verify Prometheus Targets
kubectl port-forward svc/kube-prometheus-stack-prometheus -n kube-prometheus-stack 9090:9090 &
# Open http://localhost:9090/targets - should show healthy targets
```

#### ✅ **Phase 4: Data Platform**
```bash
# 1. Spark Operator Ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=spark-operator -n spark-operator --timeout=300s

# 2. Spark History Server Running
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=spark-history-server -n spark-operator --timeout=300s

# 3. Spark CRDs Installed
kubectl get customresourcedefinitions | grep -E "(sparkapplications|scheduledsparkapplications)"

# 4. Spark Webhook Active
kubectl get validatingwebhookconfigurations | grep spark-webhook-config
```

#### ✅ **Phase 5: End-to-End Test**
```bash
# 1. Deploy Test Spark Job
cat <<EOF | kubectl apply -f -
apiVersion: "sparkoperator.k8s.io/v1beta2"
kind: SparkApplication
metadata:
  name: spark-pi-validation
  namespace: spark-operator
spec:
  type: Scala
  mode: cluster
  image: "spark:3.5.0"
  imagePullPolicy: Always
  mainClass: org.apache.spark.examples.SparkPi
  mainApplicationFile: "local:///opt/spark/examples/jars/spark-examples_2.12-3.5.0.jar"
  sparkVersion: "3.5.0"
  driver:
    cores: 1
    memory: "512m"
    serviceAccount: spark-operator-spark
  executor:
    cores: 1
    instances: 2
    memory: "512m"
    serviceAccount: spark-operator-spark
EOF

# 2. Wait for Job Completion
kubectl wait --for=condition=complete sparkapplication/spark-pi-validation -n spark-operator --timeout=600s

# 3. Verify Job Success
kubectl get sparkapplication spark-pi-validation -n spark-operator -o jsonpath='{.status.applicationState.state}'
# Should output: COMPLETED

# 4. Clean up test job
kubectl delete sparkapplication spark-pi-validation -n spark-operator
```

### Validation Scripts

#### Automated Health Check Script
```bash
#!/bin/bash
# save as: validate-deployment.sh

echo "🔍 Starting Spark on EKS Deployment Validation..."

# Function to check pod readiness
check_pods() {
  local namespace=$1
  local label=$2
  local name=$3

  if kubectl get pods -n $namespace -l $label >/dev/null 2>&1; then
    local ready=$(kubectl get pods -n $namespace -l $label -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}')
    if [ "$ready" = "True" ]; then
      echo "✅ $name is ready"
      return 0
    else
      echo "❌ $name is not ready"
      return 1
    fi
  else
    echo "❌ $name pods not found"
    return 1
  fi
}

# Check ArgoCD
echo "📋 Checking ArgoCD..."
check_pods "argocd" "app.kubernetes.io/name=argocd-server" "ArgoCD Server"

# Check Core Addons
echo "📋 Checking Core Addons..."
check_pods "karpenter" "app.kubernetes.io/name=karpenter" "Karpenter"
check_pods "kube-system" "app.kubernetes.io/name=aws-load-balancer-controller" "AWS Load Balancer Controller"
check_pods "kube-prometheus-stack" "app.kubernetes.io/name=prometheus" "Prometheus"
check_pods "kube-prometheus-stack" "app.kubernetes.io/name=grafana" "Grafana"

# Check Data Platform
echo "📋 Checking Data Platform..."
check_pods "spark-operator" "app.kubernetes.io/name=spark-operator" "Spark Operator"
check_pods "spark-operator" "app.kubernetes.io/name=spark-history-server" "Spark History Server"

# Check ArgoCD Applications
echo "📋 Checking ArgoCD Applications..."
APPS=("karpenter" "aws-load-balancer-controller" "kube-prometheus-stack" "spark-operator")
for app in "${APPS[@]}"; do
  status=$(kubectl get application $app -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
  if [ "$status" = "Healthy" ]; then
    echo "✅ ArgoCD Application $app is healthy"
  else
    echo "❌ ArgoCD Application $app is $status"
  fi
done

echo "🎉 Validation complete!"
```

#### Performance Baseline Test
```bash
#!/bin/bash
# save as: performance-test.sh

echo "🚀 Running Spark Performance Baseline..."

# Deploy CPU-intensive Spark job
cat <<EOF | kubectl apply -f -
apiVersion: "sparkoperator.k8s.io/v1beta2"
kind: SparkApplication
metadata:
  name: spark-performance-test
  namespace: spark-operator
spec:
  type: Scala
  mode: cluster
  image: "spark:3.5.0"
  imagePullPolicy: Always
  mainClass: org.apache.spark.examples.SparkPi
  mainApplicationFile: "local:///opt/spark/examples/jars/spark-examples_2.12-3.5.0.jar"
  arguments: ["1000"]
  sparkVersion: "3.5.0"
  driver:
    cores: 2
    memory: "2g"
    serviceAccount: spark-operator-spark
  executor:
    cores: 4
    instances: 3
    memory: "4g"
    serviceAccount: spark-operator-spark
EOF

# Monitor execution
echo "⏱️  Monitoring job execution..."
kubectl wait --for=condition=complete sparkapplication/spark-performance-test -n spark-operator --timeout=900s

# Get execution time
start_time=$(kubectl get sparkapplication spark-performance-test -n spark-operator -o jsonpath='{.status.lastSubmissionAttemptTime}')
end_time=$(kubectl get sparkapplication spark-performance-test -n spark-operator -o jsonpath='{.status.terminationTime}')

echo "📊 Performance Results:"
echo "Start: $start_time"
echo "End: $end_time"

# Check Karpenter scaling
echo "📈 Karpenter Node Scaling:"
kubectl get nodes -l karpenter.sh/nodepool --show-labels

# Cleanup
kubectl delete sparkapplication spark-performance-test -n spark-operator
```

## Troubleshooting

### Directory Structure & Navigation Issues

#### 🧭 **"terraform command not found" or "No terraform state" Errors**

**Problem**: After deployment, users try to run `terraform output` from the wrong directory.

**Root Cause**: The deployment script runs from the main directory, but Terraform state files are in `terraform/_local/`.

**Solution**:
```bash
# Check your current location
pwd
# If you see: /path/to/data-stacks/spark-on-eks

# Navigate to terraform directory
cd terraform/_local

# Verify terraform state exists
ls -la terraform.tfstate*

# Now run terraform commands
terraform output
terraform state list
terraform show
```

#### 📁 **Directory Structure Explained**
```
data-stacks/spark-on-eks/
├── terraform/_local/           # ← Terraform execution directory
│   ├── main.tf                 # Main terraform configuration
│   ├── terraform.tfstate       # ← Terraform state file (created after apply)
│   ├── terraform.tfstate.backup
│   └── .terraform/             # Terraform working directory
├── deploy-blueprint.sh         # ← Deployment script (runs from here)
├── cleanup.sh                  # Cleanup script
├── examples/                   # Spark example jobs
└── README.md
```

#### 🔄 **Common Navigation Commands**
```bash
# After deployment, you're here:
pwd  # /path/to/data-stacks/spark-on-eks

# To check terraform outputs:
cd terraform/_local && terraform output && cd ../..

# To run terraform commands:
cd terraform/_local
terraform output cluster_name
terraform output region
terraform state list
cd ../..  # Return to main directory

# To run kubectl commands (works from any directory):
kubectl get nodes
kubectl get pods -n spark-operator

# To submit Spark jobs:
# (from main spark-on-eks directory)
kubectl apply -f examples/spark-pi-job.yaml
```

#### 📋 **Quick Reference Card**
```bash
# Save this as: ~/spark-commands.sh for easy reference

# Function to get terraform outputs
get_terraform_output() {
  local current_dir=$(pwd)
  cd terraform/_local 2>/dev/null || {
    echo "Error: Not in spark-on-eks directory or terraform/_local not found"
    return 1
  }
  terraform output "$@"
  cd "$current_dir"
}

# Function to get cluster credentials
update_kubeconfig() {
  local current_dir=$(pwd)
  cd terraform/_local 2>/dev/null || {
    echo "Error: terraform/_local directory not found"
    return 1
  }

  local region=$(terraform output -raw region 2>/dev/null)
  local cluster_name=$(terraform output -raw cluster_name 2>/dev/null)

  if [ -n "$region" ] && [ -n "$cluster_name" ]; then
    aws eks update-kubeconfig --region "$region" --name "$cluster_name"
    echo "✅ Updated kubeconfig for cluster: $cluster_name in region: $region"
  else
    echo "❌ Could not get cluster information from terraform outputs"
  fi

  cd "$current_dir"
}

# Usage examples:
# get_terraform_output                    # Show all outputs
# get_terraform_output cluster_name       # Show specific output
# update_kubeconfig                       # Update kubectl credentials
```

### Critical Deployment Issues

#### 🚨 **Karpenter Helm Chart ECR Access Error**
**Error**: `Error: could not download chart: unexpected status from HEAD request to https://public.ecr.aws/v2/karpenter/karpenter/manifests/1.6.1: 403 Forbidden`

**Root Cause**: ECR public repository access restrictions or authentication issues.

**Solutions** (try in order):

**Solution 1: AWS CLI ECR Authentication**
```bash
# Re-authenticate with ECR public
aws ecr-public get-login-password --region us-east-1 | helm registry login --username AWS --password-stdin public.ecr.aws

# Retry deployment
terraform apply -auto-approve
```

**Solution 2: Alternative Chart Repository**
```bash
# Add OCI-based chart repository
helm repo add karpenter oci://public.ecr.aws/karpenter
helm repo update

# Or use GitHub releases (backup)
helm repo add karpenter https://charts.karpenter.sh/
helm repo update
```

**Solution 3: Manual Chart Download**
```bash
# Download chart manually
helm pull oci://public.ecr.aws/karpenter/karpenter --version 1.6.1
helm install karpenter ./karpenter-1.6.1.tgz -n karpenter --create-namespace
```

**Solution 4: Network/Proxy Issues**
```bash
# Check network connectivity
curl -I https://public.ecr.aws/v2/karpenter/karpenter/manifests/1.6.1

# If behind corporate proxy, configure Helm
export HTTPS_PROXY=your-proxy:port
export HTTP_PROXY=your-proxy:port

# Retry deployment
terraform apply -auto-approve
```

**Solution 5: Use ArgoCD Instead**
```bash
# Skip Helm installation, let ArgoCD manage Karpenter
# Modify terraform/karpenter.tf:
# Set: create_helm_release = false

terraform apply -auto-approve

# Karpenter will be installed via ArgoCD
kubectl get applications -n argocd | grep karpenter
```

#### ArgoCD Applications Not Syncing
```bash
# Check ArgoCD server health
kubectl get pods -n argocd -l app.kubernetes.io/component=server

# Common fixes:
# 1. Check application definitions
kubectl get applications -n argocd <app-name> -o yaml

# 2. Refresh application
argocd app refresh <app-name>

# 3. Force sync (if needed)
argocd app sync <app-name> --force

# 4. Check application events
kubectl describe application <app-name> -n argocd

# 5. Verify git repository access
argocd repo list

# 6. Check for sync policy conflicts
kubectl get applications -n argocd -o jsonpath='{.items[*].spec.syncPolicy}'
```

#### ArgoCD Sync Waves Not Working
```bash
# Check sync wave annotations
kubectl get applications -n argocd -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.argocd\.argoproj\.io/sync-wave}{"\n"}{end}'

# Expected sync order:
# Wave 1: Core addons (Karpenter, ALB Controller)
# Wave 2: Monitoring (Prometheus, Grafana)
# Wave 3: Data addons (Spark Operator, History Server)

# Force sync in correct order
argocd app sync core-addons --sync-option Prune=false
argocd app sync monitoring-stack --sync-option Prune=false
argocd app sync data-addons --sync-option Prune=false
```

#### Karpenter Nodes Not Provisioning
```bash
# Check Karpenter controller logs
kubectl logs -n karpenter deployment/karpenter -f

# Common issues and fixes:
# 1. Check NodePool configuration
kubectl get nodepools -o yaml

# 2. Verify EC2NodeClass
kubectl get ec2nodeclasses -o yaml

# 3. Check IAM permissions
kubectl describe serviceaccount karpenter -n karpenter

# 4. Verify subnet tags
aws ec2 describe-subnets --filters "Name=tag:karpenter.sh/discovery,Values=spark-on-eks"

# 5. Check security group tags
aws ec2 describe-security-groups --filters "Name=tag:karpenter.sh/discovery,Values=spark-on-eks"

# 6. Force node provisioning
kubectl scale deployment dummy-workload --replicas=5
```

#### Spark Operator Issues
```bash
# Check Spark Operator installation
kubectl get pods -n spark-operator -l app.kubernetes.io/name=spark-operator

# Verify CRDs are installed
kubectl get customresourcedefinitions | grep sparkoperator

# Check webhook configuration
kubectl get validatingwebhookconfigurations | grep spark

# Test operator functionality
kubectl apply -f examples/spark-pi-job.yaml

# Check job status
kubectl get sparkapplications -n spark-operator
kubectl describe sparkapplication spark-pi -n spark-operator
```

#### Monitoring Stack Issues
```bash
# Check Prometheus operator
kubectl get pods -n kube-prometheus-stack -l app=kube-prometheus-stack-operator

# Verify ServiceMonitors
kubectl get servicemonitors -n kube-prometheus-stack

# Check Grafana deployment
kubectl get pods -n kube-prometheus-stack -l app.kubernetes.io/name=grafana

# Access Grafana logs if failing
kubectl logs -n kube-prometheus-stack deployment/kube-prometheus-stack-grafana
```

### Network and Connectivity Issues

#### VPC/Subnet Configuration
```bash
# Verify VPC setup
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=spark-on-eks-vpc"

# Check subnet configuration
aws ec2 describe-subnets --filters "Name=vpc-id,Values=<vpc-id>"

# Verify NAT gateway for private subnets
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=<vpc-id>"

# Check route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=<vpc-id>"
```

#### Load Balancer Issues
```bash
# Check AWS Load Balancer Controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Verify IAM permissions
kubectl describe serviceaccount aws-load-balancer-controller -n kube-system

# Check for stuck load balancers
kubectl get ingress --all-namespaces
aws elbv2 describe-load-balancers --query 'LoadBalancers[?State.Code==`failed`]'
```

### Performance Issues

#### Resource Constraints
```bash
# Check node resource usage
kubectl top nodes

# Check pod resource usage
kubectl top pods --all-namespaces --sort-by=memory

# Verify resource quotas
kubectl get resourcequotas --all-namespaces

# Check for pending pods
kubectl get pods --all-namespaces --field-selector=status.phase=Pending
```

#### Storage Issues
```bash
# Check storage classes
kubectl get storageclass

# Verify EBS CSI driver
kubectl get pods -n kube-system -l app=ebs-csi-controller

# Check persistent volumes
kubectl get pv,pvc --all-namespaces

# Check for storage provisioning issues
kubectl describe storageclass gp3
```

## Cleanup

### Infrastructure Cleanup
```bash
# Complete cleanup
./cleanup.sh

# Manual cleanup
cd terraform/_local
terraform destroy -auto-approve
```

## Next Steps

### Immediate Post-Deployment Actions

#### 1. **Verify Deployment Success** 🔍
```bash
# Check you're in the right directory
pwd  # Should be: /path/to/data-stacks/spark-on-eks

# Get deployment information
cd terraform/_local
terraform output

# Example outputs you should see:
# cluster_name = "spark-on-eks-xxxxxxx"
# region = "us-west-2"
# vpc_id = "vpc-xxxxxxx"
# argocd_password = "xxxxxxx"

cd ../..  # Return to main directory
```

#### 2. **Access ArgoCD Dashboard** 🎛️
```bash
# Get ArgoCD password (from terraform/_local directory)
cd terraform/_local
ARGOCD_PASSWORD=$(terraform output -raw argocd_password)
echo "ArgoCD Password: $ARGOCD_PASSWORD"
cd ../..

# Port forward to ArgoCD (in separate terminal)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access ArgoCD UI:
# URL: https://localhost:8080
# Username: admin
# Password: (use password from above)
```

#### 3. **Access Grafana Dashboard** 📊
```bash
# Port forward to Grafana (in separate terminal)
kubectl port-forward svc/kube-prometheus-stack-grafana -n kube-prometheus-stack 3000:80

# Access Grafana UI:
# URL: http://localhost:3000
# Username: admin
# Password: prom-operator
```

#### 4. **Submit Your First Spark Job** 🚀
```bash
# Ensure you're in spark-on-eks main directory
pwd  # Should be: /path/to/data-stacks/spark-on-eks

# Submit a test job
kubectl apply -f examples/spark-pi-job.yaml

# Monitor job progress
kubectl get sparkapplications -n spark-operator -w

# Check job details
kubectl describe sparkapplication spark-pi -n spark-operator

# View logs
kubectl logs spark-pi-driver -n spark-operator
```

### Ongoing Operations

#### 5. **Set Up Your Workspace** 🛠️
```bash
# Create helper script for easy navigation
cat > ~/spark-on-eks-helper.sh << 'EOF'
#!/bin/bash

# Set base directory (adjust path as needed)
SPARK_DIR="$HOME/Documents/github/data-on-eks/data-stacks/spark-on-eks"

# Quick navigation functions
goto_spark() { cd "$SPARK_DIR"; }
goto_terraform() { cd "$SPARK_DIR/terraform/_local"; }

# Terraform wrapper functions
spark_output() {
  local current_dir=$(pwd)
  cd "$SPARK_DIR/terraform/_local"
  terraform output "$@"
  cd "$current_dir"
}

spark_status() {
  echo "🏗️  Infrastructure Status:"
  spark_output cluster_name region vpc_id
  echo ""
  echo "📊 Cluster Status:"
  kubectl get nodes --no-headers | wc -l | xargs echo "Nodes:"
  kubectl get pods -n spark-operator --no-headers | wc -l | xargs echo "Spark Pods:"
  kubectl get sparkapplications -n spark-operator --no-headers | wc -l | xargs echo "Spark Jobs:"
}

# Quick port forwards
forward_argocd() {
  echo "🔗 ArgoCD UI: https://localhost:8080"
  echo "👤 Username: admin"
  echo "🔑 Password: $(spark_output argocd_password)"
  kubectl port-forward svc/argocd-server -n argocd 8080:443
}

forward_grafana() {
  echo "🔗 Grafana UI: http://localhost:3000"
  echo "👤 Username: admin"
  echo "🔑 Password: prom-operator"
  kubectl port-forward svc/kube-prometheus-stack-grafana -n kube-prometheus-stack 3000:80
}

echo "Spark on EKS Helper Functions Loaded!"
echo "Commands: goto_spark, goto_terraform, spark_output, spark_status, forward_argocd, forward_grafana"
EOF

# Load the helper
chmod +x ~/spark-on-eks-helper.sh
source ~/spark-on-eks-helper.sh

# Test the functions
spark_status
```

#### 6. **Configure Monitoring** 📈
- **Set up custom dashboards** - Import Spark-specific Grafana dashboards
- **Create alerts** - Configure notifications for job failures and resource limits
- **Cost monitoring** - Set up budget alerts and cost optimization rules

#### 7. **Optimize Performance** ⚡
- **Tune for your workloads** - Adjust executor memory, cores, and instance types
- **Configure auto-scaling** - Set up Karpenter node pools for your usage patterns
- **Storage optimization** - Choose between EBS and local storage based on workload

#### 8. **Implement Security** 🔒
- **Apply organization policies** - Configure network policies and pod security standards
- **Set up RBAC** - Create role-based access for different teams
- **Enable audit logging** - Configure EKS audit logs for compliance

### Quick Reference Commands

```bash
# Directory navigation
cd terraform/_local          # For terraform commands
cd ../..                     # Back to main directory

# Essential commands
terraform output              # Get deployment info
kubectl get nodes            # Check cluster
kubectl get pods -A          # Check all pods
kubectl get sparkapplications -n spark-operator  # Check Spark jobs

# Access UIs
kubectl port-forward svc/argocd-server -n argocd 8080:443
kubectl port-forward svc/kube-prometheus-stack-grafana -n kube-prometheus-stack 3000:80

# Submit jobs
kubectl apply -f examples/spark-pi-job.yaml
kubectl get sparkapplications -n spark-operator -w
```

## Related Examples

- [EBS Persistent Volumes](./ebs-persistent-volumes)
- [Node Local Storage](./node-local-storage)
- [Back to Examples](/data-on-eks/docs/datastacks/spark-on-eks/)
