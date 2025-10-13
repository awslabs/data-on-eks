# Spark on EKS Data Stack

Production-ready Apache Spark infrastructure on Amazon EKS with comprehensive monitoring, autoscaling, and enterprise features.

## 🚀 Quick Start

```bash
# Clone repository
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/data-stacks/spark-on-eks

# Deploy infrastructure
./deploy.sh
```

## 📋 Prerequisites

- **AWS CLI** configured with appropriate permissions
- **Terraform** >= 1.0
- **kubectl** >= 1.28
- **Helm** >= 3.0 (optional)

### Required AWS Permissions
- EC2, VPC, IAM management
- EKS cluster administration
- S3 bucket access for Spark jobs
- CloudWatch, ECR permissions

## 🏗️ Infrastructure Architecture

### Core Components
- **Amazon EKS** - Kubernetes cluster with managed node groups
- **Karpenter** - Dynamic node provisioning and scaling
- **Apache Spark Operator** - Native Kubernetes Spark job management
- **Spark History Server** - Job monitoring and debugging
- **ArgoCD** - GitOps workflow management

### Optional Components (Configurable)
- **Prometheus & Grafana** - Metrics collection and visualization
- **NGINX Ingress** - Load balancing and TLS termination
- **JupyterHub** - Interactive notebook environment
- **YuniKorn** - Advanced Kubernetes scheduler
- **External Secrets** - Secure credential management

## ⚙️ Configuration

### Data Stack Configuration (`terraform/data-stack.tfvars`)

```hcl
# Basic Configuration
region = "us-west-2"
name   = "spark-on-eks"

# Core Platform Components (Always Enabled)
# - EKS Cluster with managed addons
# - VPC with dual CIDR support
# - Karpenter for autoscaling
# - ArgoCD for GitOps

# Spark-Specific Components
enable_spark_operator        = true   # Spark Operator for job management
enable_spark_history_server  = true   # History server for job tracking
enable_yunikorn              = false  # Advanced scheduler (optional)

# Data Platform Addons
enable_jupyterhub           = false   # Interactive notebooks
enable_kube_prometheus_stack = true   # Monitoring stack
enable_cert_manager         = false   # TLS certificate management
enable_ingress_nginx        = true    # Ingress controller

# Storage & Data
enable_aws_efs_csi_driver   = false   # Shared file system
enable_aws_fsx_csi_driver   = false   # High-performance file system

# Streaming & Analytics
enable_kafka                = false   # Stream processing
enable_datahub              = false   # Metadata management

# Security
enable_external_secrets     = false   # External secret management
enable_aws_for_fluentbit    = false   # Log aggregation

# Advanced Features
enable_team_shared_ns_soft_multi_tenancy = false  # Multi-tenancy
```

### Infrastructure Customization

#### VPC Configuration
```hcl
# Custom VPC settings (optional)
vpc_cidr         = "10.0.0.0/16"
secondary_cidrs  = ["100.64.0.0/16"]  # For additional IP space

# Subnet tagging for specific workloads
public_subnet_tags = {
  "kubernetes.io/role/elb" = "1"
}

private_subnet_tags = {
  "kubernetes.io/role/internal-elb" = "1"
}
```

#### EKS Configuration
```hcl
# EKS cluster settings
eks_cluster_version = "1.33"
cluster_endpoint_public_access = true

# Node group configuration
node_instance_types = ["m5.large", "m5.xlarge", "m5.2xlarge"]
node_capacity_type  = "SPOT"  # or "ON_DEMAND"
```

#### Karpenter Node Pools
```hcl
# Customize Karpenter node provisioning
karpenter_node_instance_family = ["m5", "c5", "r5"]
karpenter_node_sizes = ["large", "xlarge", "2xlarge", "4xlarge"]
```

## 🚀 Deployment Process

### 1. Infrastructure Deployment

```bash
# Set environment variables (optional)
export AWS_REGION=us-west-2
export CLUSTER_NAME=spark-on-eks

# Run deployment script
./deploy.sh
```

### Deployment Steps (Automated)
1. **Prerequisites Check** - Validates AWS credentials and tools
2. **Infrastructure Copy** - Copies base infrastructure from `infra/terraform/`
3. **Configuration Apply** - Applies `data-stack.tfvars` settings
4. **VPC & EKS Deployment** - Creates networking and cluster
5. **ArgoCD Bootstrap** - Installs GitOps controller
6. **Addon Deployment** - Installs selected components via ArgoCD

### 2. Post-Deployment Access

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-west-2 --name spark-on-eks

# Verify cluster
kubectl get nodes
kubectl get pods -n spark-operator

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080
# Username: admin
# Password: (retrieved automatically during deployment)
```

## 📊 Monitoring & Observability

### Prometheus Metrics
- **Cluster Metrics** - Node utilization, pod status
- **Spark Metrics** - Job execution, driver/executor stats
- **Karpenter Metrics** - Node provisioning, scaling events

### Grafana Dashboards
- EKS Cluster Overview
- Spark Application Monitoring
- Karpenter Node Management
- Cost Analysis (when Kubecost enabled)

### Accessing Monitoring

```bash
# Grafana UI
kubectl port-forward svc/kube-prometheus-stack-grafana -n kube-prometheus-stack 3000:80
# Open http://localhost:3000
# Username: admin / Password: prom-operator

# Spark History Server
kubectl port-forward svc/spark-history-server -n spark-operator 18080:18080
# Open http://localhost:18080
```

## 💰 Cost Optimization

### Karpenter Configuration
- **Spot Instances** - Up to 70% cost savings
- **Right-sizing** - Automatic node selection based on workload
- **Node Consolidation** - Efficient bin-packing

### Storage Optimization
- **gp3 Volumes** - Cost-effective SSD storage
- **EBS Snapshot Lifecycle** - Automated backup management
- **S3 Intelligent Tiering** - For Spark data lakes

## 🔧 Troubleshooting

### Common Issues

#### ArgoCD Applications Not Syncing
```bash
# Check ArgoCD status
kubectl get applications -n argocd

# Manual sync
kubectl patch application spark-operator -n argocd -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' --type merge
```

#### Karpenter Nodes Not Provisioning
```bash
# Check Karpenter logs
kubectl logs -n karpenter deployment/karpenter

# Verify node pool configuration
kubectl get nodepools
kubectl describe nodepool default
```

#### Spark Jobs Failing
```bash
# Check Spark Operator logs
kubectl logs -n spark-operator deployment/spark-operator

# Check specific application
kubectl describe sparkapplication <app-name> -n spark-operator
kubectl logs <driver-pod> -n spark-operator
```

### Performance Tuning

#### Memory Optimization
```yaml
# Spark job configuration
spec:
  driver:
    memory: "2g"
    cores: 1
  executor:
    memory: "4g"
    cores: 2
    instances: 4
```

#### Storage Performance
```yaml
# Use NVMe instance store for high-performance workloads
nodeClassRef:
  name: karpenter-node-nvme
```

## 🧪 Examples & Use Cases

After deployment, explore these example scenarios:

### 1. **Performance Examples**
- [Gluten-Velox Acceleration](../../website/docs/datastacks/spark-on-eks/_gluten-velox.md)
- [ARM Graviton Processing](../../website/docs/datastacks/spark-on-eks/_spark-graviton.md)
- [DataFusion Comet Engine](../../website/docs/datastacks/spark-on-eks/_spark_datafusion-comet.md)

### 2. **Storage Examples**
- [EBS Persistent Volumes](../../website/docs/datastacks/spark-on-eks/_spark-ebs-pvc.md)
- [Node Local Storage](../../website/docs/datastacks/spark-on-eks/_spark-ebs-nodestorage.md)
- [NVMe SSD Performance](../../website/docs/datastacks/spark-on-eks/_spark-nvme-ssd.md)

### 3. **Advanced Features**
- [Celeborn Remote Shuffle](../../website/docs/datastacks/spark-on-eks/_spark-celeborn.md)

### Running Examples
```bash
# Navigate to examples
cd examples/

# Submit sample Spark job
kubectl apply -f karpenter/pyspark-pi-job.yaml

# Monitor job progress
kubectl get sparkapplications -n spark-operator -w
```

## 🧹 Cleanup

```bash
# Destroy infrastructure
./cleanup.sh

# Manual cleanup (if needed)
cd terraform/_local
terraform destroy -auto-approve
```

## 🔗 Additional Resources

- [Data on EKS Website](https://awslabs.github.io/data-on-eks/)
- [Apache Spark on Kubernetes](https://spark.apache.org/docs/latest/running-on-kubernetes.html)
- [Karpenter Documentation](https://karpenter.sh/)
- [EKS Best Practices](https://aws-ia.github.io/aws-eks-best-practices/)

## 🆘 Support

- **GitHub Issues**: [Report bugs and feature requests](https://github.com/awslabs/data-on-eks/issues)
- **Documentation**: [Comprehensive guides and examples](https://awslabs.github.io/data-on-eks/)
- **Community**: Join our discussions and Q&A
