---
title: Best Practices
sidebar_position: 1
sidebar_label: Overview
---

import '@site/src/css/datastack-tiles.css';
import '@site/src/css/getting-started.css';
import BestPracticesHero from '@site/src/components/BestPractices/BestPracticesHero';
import { Shield, Layers, TrendingUp, Database, Zap, Lock } from 'lucide-react';

<BestPracticesHero />

## Overview

Through working with AWS customers, we've identified production-proven best practices for running data and ML workloads on EKS. These recommendations are continuously updated based on real-world deployments and customer feedback.

These Data on EKS Best Practices expand upon the [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/) for data-centric use cases (batch processing, stream processing, machine learning). We recommend reviewing the EKS Best Practices as a primer before diving into these recommendations.

## Best Practice Categories

<div className="datastacks-grid">

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Layers size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>Cluster Architecture</h3>
<p className="datastack-description">Design patterns for dynamic and static clusters, scaling strategies, and resource management.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Dynamic Clusters</span>
<span className="feature-tag">Static Clusters</span>
<span className="feature-tag">High Churn</span>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <TrendingUp size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>Performance Optimization</h3>
<p className="datastack-description">Tuning strategies for Spark, Karpenter autoscaling, and resource allocation patterns.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Spark Tuning</span>
<span className="feature-tag">Autoscaling</span>
<span className="feature-tag">Cost Optimization</span>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Database size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>Data Storage</h3>
<p className="datastack-description">Storage strategies for S3, EBS, EFS, and ephemeral storage optimization.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">S3 Integration</span>
<span className="feature-tag">EBS Volumes</span>
<span className="feature-tag">Shuffle Data</span>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Lock size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>Security & Compliance</h3>
<p className="datastack-description">IRSA, network policies, encryption at rest, and security hardening.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">IRSA</span>
<span className="feature-tag">Network Policies</span>
<span className="feature-tag">Encryption</span>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Zap size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>Observability</h3>
<p className="datastack-description">Monitoring, logging, and alerting strategies for data workloads.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Prometheus</span>
<span className="feature-tag">CloudWatch</span>
<span className="feature-tag">Dashboards</span>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Shield size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>Production Readiness</h3>
<p className="datastack-description">High availability, disaster recovery, and operational excellence.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">HA Setup</span>
<span className="feature-tag">Backup/Restore</span>
<span className="feature-tag">GitOps</span>
</div>
</div>

</div>

## Cluster Design Patterns

The recommendations are built from working with customers using one of two cluster designs:

* **Dynamic Clusters** - Scale with high "churn" rates. Run batch processing (Spark) with pods created for short periods. These clusters create/delete resources (pods, nodes) at high rates, adding unique pressures to Kubernetes components.

* **Static Clusters** - Large but stable scaling behavior. Run longer-lived jobs (streaming, training). Avoiding interruptions is critical, requiring careful change management.

### Scale Considerations

Large clusters typically have >500 nodes and >5000 pods, or create/destroy hundreds of resources per minute. However, scalability constraints differ per workload due to [Kubernetes scalability complexity](https://github.com/kubernetes/community/blob/master/sig-scalability/configs-and-limits/thresholds.md).

:::info Coming Soon
Detailed best practice guides are being developed. Check back for updates on cluster configuration, resource management, security, monitoring, and optimization strategies.
:::
