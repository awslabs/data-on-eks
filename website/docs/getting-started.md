---
title: Launch
sidebar_position: 0
---

import '@site/src/css/getting-started.css';
import HeroSection from '@site/src/components/GettingStarted/HeroSection';
import PrinciplesGrid from '@site/src/components/GettingStarted/PrinciplesGrid';
import ArchitectureDiagram from '@site/src/components/GettingStarted/ArchitectureDiagram';
import DataStacksShowcase from '@site/src/components/GettingStarted/DataStacksShowcase';
import { Cloud, Link2, Code, Sparkles, Globe, Users, Zap, TrendingUp, FlaskConical, Rocket, BookOpen, Bug, MessageCircle, CheckCircle, Play } from 'lucide-react';

<HeroSection />

## What is Data on EKS?

**Data on EKS (DoEKS)** is an opinionated infrastructure framework that combines the power of **Cloud Native Computing Foundation (CNCF)** projects with deep **AWS integration** to deliver production-ready data platforms on Amazon EKS.

<div style={{
  display: 'grid',
  gridTemplateColumns: 'repeat(2, 1fr)',
  gap: '1.5rem',
  margin: '2rem 0',
  maxWidth: '1200px'
}}>
  <div className="info-box info-box-success">
    <div className="info-box-title">
      <Cloud size={20} className="inline-block mr-2" /> CNCF Ecosystem
    </div>
    <div>Leverages graduated and incubating CNCF projects (Kubernetes, Prometheus, Strimzi, Argo)</div>
  </div>

  <div className="info-box info-box-info">
    <div className="info-box-title">
      <Link2 size={20} className="inline-block mr-2" /> AWS Integration
    </div>
    <div>Deep integration with Amazon EKS, S3, EMR, and AWS data services</div>
  </div>

  <div className="info-box info-box-warning">
    <div className="info-box-title">
      <Code size={20} className="inline-block mr-2" /> Infrastructure as Code
    </div>
    <div>Terraform-based, GitOps-ready deployments with ArgoCD</div>
  </div>

  <div className="info-box info-box-success">
    <div className="info-box-title">
      <Sparkles size={20} className="inline-block mr-2" /> Production Patterns
    </div>
    <div>Battle-tested configurations from real AWS customer workloads</div>
  </div>
</div>

<PrinciplesGrid />

<ArchitectureDiagram />

<DataStacksShowcase />

## Quick Start: Deploy in 15 Minutes {#quick-start}

<div className="quick-start-timeline">

<div className="timeline-step">
<div className="timeline-number">1</div>
<div className="timeline-content">

### Prerequisites

**Required Tools:**
```bash
# Verify installations
aws --version          # AWS CLI v2.x
terraform --version    # Terraform >= 1.0
kubectl version        # kubectl >= 1.28
helm version           # Helm >= 3.0
```

**AWS Setup:**
- IAM permissions: `AdministratorAccess` or custom policy for VPC/EKS/IAM creation
- Configured AWS profile: `aws configure` or `AWS_PROFILE` environment variable
- Default region set (recommend: `us-west-2`, `us-east-1`, `eu-west-1`)

</div>
</div>

<div className="timeline-step">
<div className="timeline-number">2</div>
<div className="timeline-content">

### Choose Your Data Stack

| Need | Recommended Stack |
|------|-------------------|
| Batch ETL / data processing | [Spark on EKS](/data-on-eks/docs/datastacks/processing/spark-on-eks/) |
| Real-time event streaming | [Kafka on EKS](/data-on-eks/docs/datastacks/streaming/kafka-on-eks/) |
| Workflow orchestration | [Airflow on EKS](/data-on-eks/docs/datastacks/orchestration/airflow-on-eks/) |
| AWS-managed Spark | [EMR on EKS](/data-on-eks/docs/datastacks/processing/emr-on-eks/) |
| Vector databases & AI agents | [AI for Data](/data-on-eks/docs/ai-ml/) |

</div>
</div>

<div className="timeline-step">
<div className="timeline-number">3</div>
<div className="timeline-content">

### Clone & Configure

```bash
# Clone repository
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/data-stacks/spark-on-eks

# Review configuration
cat terraform/data-stack.tfvars
```

**Key Configuration Options:**
```hcl
# terraform/data-stack.tfvars

# Required
region = "us-west-2"              # AWS region
name   = "spark-on-eks"           # Cluster name (must be unique)

# Core addons (recommended for all stacks)
enable_karpenter                   = true   # Node autoscaling
enable_aws_load_balancer_controller = true   # ALB/NLB support
enable_kube_prometheus_stack       = true   # Monitoring

# Spark-specific addons
enable_spark_operator              = true   # Spark Operator (Kubeflow)
enable_spark_history_server        = true   # Spark UI persistence
enable_yunikorn                    = true   # Advanced scheduling
```

</div>
</div>

<div className="timeline-step">
<div className="timeline-number">4</div>
<div className="timeline-content">

### Deploy Infrastructure

```bash
# Automated deployment (validates prerequisites)
./deploy.sh

# Manual deployment (for advanced users)
cd terraform
terraform init
terraform plan -var-file=data-stack.tfvars
terraform apply -var-file=data-stack.tfvars -auto-approve
```

**Deployment Timeline:**
- Terraform apply: ~10-12 minutes (VPC, EKS, IAM, Karpenter)
- ArgoCD sync: ~3-5 minutes (Kubernetes addons)
- **Total: ~15 minutes** for full stack

</div>
</div>

<div className="timeline-step">
<div className="timeline-number">5</div>
<div className="timeline-content">

### Validate Deployment

```bash
# Configure kubectl
export CLUSTER_NAME=spark-on-eks
export AWS_REGION=us-west-2
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

# Verify nodes (Karpenter-managed)
kubectl get nodes

# Check addon deployments
kubectl get pods -A

# Verify Spark Operator
kubectl get crd sparkapplications.sparkoperator.k8s.io
kubectl get pods -n spark-operator
```

</div>
</div>

<div className="timeline-step">
<div className="timeline-number">6</div>
<div className="timeline-content">

### Run Example Workload

```bash
# Submit Spark Pi calculation job
kubectl apply -f examples/pyspark-pi-job.yaml

# Watch job progress
kubectl get sparkapplications -w

# View driver logs
kubectl logs spark-pi-driver

# Check Spark History Server (if enabled)
kubectl port-forward -n spark-operator svc/spark-history-server 18080:80
# Open: http://localhost:18080
```

</div>
</div>

</div>

## CNCF Ecosystem Integration

Data on EKS is **CNCF-native**, using cloud-native patterns while optimizing for AWS:

<div className="cncf-table-container">

| CNCF Project | Maturity | Role in DoEKS | AWS Alternative |
|--------------|----------|---------------|-----------------|
| **Kubernetes** | Graduated | Container orchestration | Amazon EKS (managed K8s) |
| **Prometheus** | Graduated | Metrics & alerting | Amazon Managed Prometheus (AMP) |
| **Strimzi** | Incubating | Kafka operator | Amazon MSK (managed Kafka) |
| **Argo (CD/Workflows)** | Graduated | GitOps & pipelines | AWS CodePipeline |
| **Helm** | Graduated | Package management | - |
| **Karpenter** | Graduated | Node autoscaling | Cluster Autoscaler |
| **Grafana** | Observability partner | Visualization | Amazon Managed Grafana (AMG) |

</div>

### Why CNCF + AWS?

<div style={{
  display: 'grid',
  gridTemplateColumns: 'repeat(2, 1fr)',
  gap: '1.5rem',
  margin: '2rem 0',
  maxWidth: '1200px'
}}>
  <div style={{
    padding: '2rem',
    background: 'linear-gradient(135deg, rgba(102, 126, 234, 0.05), rgba(118, 75, 162, 0.05))',
    borderRadius: '16px',
    border: '2px solid rgba(102, 126, 234, 0.2)'
  }}>
    <h4 style={{ fontSize: '1.25rem', fontWeight: '700', marginBottom: '0.75rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <Globe size={20} /> Portability
    </h4>
    <div style={{ margin: 0, color: 'var(--ifm-color-content-secondary)' }}>
      Run anywhere Kubernetes runs (on-prem, multi-cloud)
    </div>
  </div>

  <div style={{
    padding: '2rem',
    background: 'linear-gradient(135deg, rgba(240, 147, 251, 0.05), rgba(245, 87, 108, 0.05))',
    borderRadius: '16px',
    border: '2px solid rgba(240, 147, 251, 0.2)'
  }}>
    <h4 style={{ fontSize: '1.25rem', fontWeight: '700', marginBottom: '0.75rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <Users size={20} /> Community Innovation
    </h4>
    <div style={{ margin: 0, color: 'var(--ifm-color-content-secondary)' }}>
      Benefit from thousands of contributors
    </div>
  </div>

  <div style={{
    padding: '2rem',
    background: 'linear-gradient(135deg, rgba(79, 172, 254, 0.05), rgba(0, 242, 254, 0.05))',
    borderRadius: '16px',
    border: '2px solid rgba(79, 172, 254, 0.2)'
  }}>
    <h4 style={{ fontSize: '1.25rem', fontWeight: '700', marginBottom: '0.75rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <Zap size={20} /> AWS Optimization
    </h4>
    <div style={{ margin: 0, color: 'var(--ifm-color-content-secondary)' }}>
      Tight integration with EKS, S3, IAM, CloudWatch
    </div>
  </div>

  <div style={{
    padding: '2rem',
    background: 'linear-gradient(135deg, rgba(67, 233, 123, 0.05), rgba(56, 249, 215, 0.05))',
    borderRadius: '16px',
    border: '2px solid rgba(67, 233, 123, 0.2)'
  }}>
    <h4 style={{ fontSize: '1.25rem', fontWeight: '700', marginBottom: '0.75rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <TrendingUp size={20} /> Hybrid Workloads
    </h4>
    <div style={{ margin: 0, color: 'var(--ifm-color-content-secondary)' }}>
      Mix open-source (Spark) + managed (EMR on EKS)
    </div>
  </div>
</div>

## Production Deployment Patterns

### Multi-Environment Strategy

<div style={{
  display: 'grid',
  gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))',
  gap: '1.5rem',
  margin: '2rem 0',
  maxWidth: '1200px'
}}>
  <div style={{
    padding: '2rem',
    background: 'linear-gradient(135deg, rgba(34, 197, 94, 0.1), rgba(16, 185, 129, 0.05))',
    borderRadius: '16px',
    border: '2px solid rgba(34, 197, 94, 0.3)'
  }}>
    <h4 style={{ fontSize: '1.25rem', fontWeight: '700', marginBottom: '1rem', color: '#059669', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <FlaskConical size={20} /> Development
    </h4>
    <ul style={{ margin: 0, paddingLeft: '1.5rem', color: 'var(--ifm-color-content-secondary)' }}>
      <li>Small instances</li>
      <li>100% Spot instances</li>
      <li>Minimal addons</li>
      <li>Single AZ</li>
    </ul>
  </div>

  <div style={{
    padding: '2rem',
    background: 'linear-gradient(135deg, rgba(234, 179, 8, 0.1), rgba(202, 138, 4, 0.05))',
    borderRadius: '16px',
    border: '2px solid rgba(234, 179, 8, 0.3)'
  }}>
    <h4 style={{ fontSize: '1.25rem', fontWeight: '700', marginBottom: '1rem', color: '#ca8a04', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <Play size={20} /> Staging
    </h4>
    <ul style={{ margin: 0, paddingLeft: '1.5rem', color: 'var(--ifm-color-content-secondary)' }}>
      <li>Production-like size</li>
      <li>70% Spot / 30% On-Demand</li>
      <li>Full addons enabled</li>
      <li>Multi-AZ</li>
    </ul>
  </div>

  <div style={{
    padding: '2rem',
    background: 'linear-gradient(135deg, rgba(59, 130, 246, 0.1), rgba(37, 99, 235, 0.05))',
    borderRadius: '16px',
    border: '2px solid rgba(59, 130, 246, 0.3)'
  }}>
    <h4 style={{ fontSize: '1.25rem', fontWeight: '700', marginBottom: '1rem', color: '#2563eb', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <CheckCircle size={20} /> Production
    </h4>
    <ul style={{ margin: 0, paddingLeft: '1.5rem', color: 'var(--ifm-color-content-secondary)' }}>
      <li>Right-sized instances</li>
      <li>70% Spot / 30% On-Demand</li>
      <li>HA, observability, security</li>
      <li>Multi-AZ with consolidation</li>
    </ul>
  </div>
</div>

### Cost Optimization

**Karpenter Best Practices:**
- Mix Spot (70%) + On-Demand (30%) for fault tolerance
- Use multiple instance families (M5, M6i, M6a) for Spot diversity
- Enable consolidation to reduce idle capacity
- Set appropriate limits per NodePool

**Savings Realized:**
- Karpenter vs Cluster Autoscaler: **~30% reduction** in node costs
- Spot instances: **~70% savings** vs On-Demand
- EBS gp3 vs gp2: **~20% savings** on storage

## Learning Resources

<div style={{
  display: 'grid',
  gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))',
  gap: '2rem',
  margin: '3rem 0',
  maxWidth: '1200px'
}}>
  <div className="learning-card">
    <h3 style={{ fontSize: '1.5rem', fontWeight: '700', marginBottom: '1rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <BookOpen size={24} /> Tutorials
    </h3>
    <div style={{ color: 'var(--ifm-color-content-secondary)', marginBottom: '1.5rem' }}>
      Step-by-step guides for deploying data platforms
    </div>
    <ul style={{ paddingLeft: '1.5rem', margin: 0 }}>
      <li><a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/infra">Spark on EKS: From Zero to Production</a></li>
      <li><a href="/data-on-eks/docs/datastacks/streaming/kafka-on-eks/">Kafka Streaming with Strimzi</a></li>
      <li><a href="/data-on-eks/docs/datastacks/orchestration/airflow-on-eks/">Airflow Workflows on Kubernetes</a></li>
    </ul>
  </div>

  <div className="learning-card">
    <h3 style={{ fontSize: '1.5rem', fontWeight: '700', marginBottom: '1rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <Zap size={24} /> Deep Dives
    </h3>
    <div style={{ color: 'var(--ifm-color-content-secondary)', marginBottom: '1.5rem' }}>
      Advanced topics for production optimization
    </div>
    <ul style={{ paddingLeft: '1.5rem', margin: 0 }}>
      <li><a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/spark-gluten-velox-gpu">Spark Performance with Gluten & Velox</a></li>
      <li><a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/spark-ebs-pvc">Storage Optimization with EBS</a></li>
      <li><a href="/data-on-eks/docs/bestpractices/intro">Security & Observability Best Practices</a></li>
    </ul>
  </div>

  <div className="learning-card">
    <h3 style={{ fontSize: '1.5rem', fontWeight: '700', marginBottom: '1rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <TrendingUp size={24} /> Benchmarks
    </h3>
    <div style={{ color: 'var(--ifm-color-content-secondary)', marginBottom: '1.5rem' }}>
      Real-world performance testing results
    </div>
    <ul style={{ paddingLeft: '1.5rem', margin: 0 }}>
      <li><a href="/data-on-eks/docs/benchmarks/emr-on-eks">TPCDS 3TB: Spark vs EMR on EKS</a></li>
      <li><a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/spark-graviton">Graviton3 Performance Analysis</a></li>
      <li><a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/spark-nvme-storage">NVMe Storage Performance</a></li>
    </ul>
  </div>
</div>

<div className="cta-section">
  <h2 className="cta-section-title">Ready to Build Your Data Platform?</h2>
  <div className="cta-section-description">
    Join thousands of data engineers using Data on EKS to run production workloads on Amazon EKS.
    Deploy your first stack in 15 minutes.
  </div>
  <div style={{ display: 'flex', justifyContent: 'center', gap: '1.5rem', flexWrap: 'wrap', position: 'relative', zIndex: 1 }}>
    <a
      href="#quick-start"
      style={{
        padding: '1rem 2.5rem',
        background: 'white',
        color: '#4f46e5',
        borderRadius: '50px',
        textDecoration: 'none',
        fontWeight: '700',
        fontSize: '1.1rem',
        boxShadow: '0 8px 25px rgba(0, 0, 0, 0.25)',
        transition: 'all 0.3s ease',
        display: 'inline-flex',
        alignItems: 'center',
        gap: '0.75rem'
      }}
    >
      <Rocket size={20} />
      <span>Get Started Now</span>
    </a>
    <a
      href="https://github.com/awslabs/data-on-eks"
      style={{
        padding: '1rem 2.5rem',
        background: 'rgba(255, 255, 255, 0.15)',
        color: 'white',
        borderRadius: '50px',
        textDecoration: 'none',
        fontWeight: '700',
        fontSize: '1.1rem',
        border: '2px solid rgba(255, 255, 255, 0.4)',
        backdropFilter: 'blur(10px)',
        transition: 'all 0.3s ease',
        display: 'inline-flex',
        alignItems: 'center',
        gap: '0.75rem'
      }}
    >
      <Code size={20} />
      <span>Star on GitHub</span>
    </a>
  </div>
</div>

## Community & Support

<div style={{
  display: 'grid',
  gridTemplateColumns: 'repeat(auto-fit, minmax(250px, 1fr))',
  gap: '1.5rem',
  margin: '2rem 0',
  maxWidth: '1200px'
}}>
  <a
    href="https://awslabs.github.io/data-on-eks/"
    className="community-card"
  >
    <h4 style={{ fontSize: '1.25rem', fontWeight: '700', marginBottom: '0.75rem', color: 'var(--ifm-heading-color)', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <BookOpen size={20} /> Documentation
    </h4>
    <div style={{ margin: 0, color: 'var(--ifm-color-content-secondary)' }}>
      Comprehensive guides, tutorials, and API reference
    </div>
  </a>

  <a
    href="https://github.com/awslabs/data-on-eks/issues"
    className="community-card"
  >
    <h4 style={{ fontSize: '1.25rem', fontWeight: '700', marginBottom: '0.75rem', color: 'var(--ifm-heading-color)', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <Bug size={20} /> GitHub Issues
    </h4>
    <div style={{ margin: 0, color: 'var(--ifm-color-content-secondary)' }}>
      Bug reports, feature requests, and discussions
    </div>
  </a>

  <a
    href="https://github.com/awslabs/data-on-eks/discussions"
    className="community-card"
  >
    <h4 style={{ fontSize: '1.25rem', fontWeight: '700', marginBottom: '0.75rem', color: 'var(--ifm-heading-color)', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <MessageCircle size={20} /> Discussions
    </h4>
    <div style={{ margin: 0, color: 'var(--ifm-color-content-secondary)' }}>
      Q&A, show-and-tell, and community ideas
    </div>
  </a>
</div>

---

**Built with ❤️ by AWS Solutions Architects and Community Contributors**

*Data on EKS is an open-source project maintained by AWS community. Support is provided on a best-effort basis. This is not an official AWS service.*

**License:** Apache 2.0 | **Version:** 2.0 (Current) | **Last Updated:** January 2025
