---
title: Amazon EMR on EKS
sidebar_position: 0
---

import '@site/src/css/datastack-tiles.css';

# EMR on EKS Stack

Production-ready Amazon EMR on EKS examples and configurations for running Apache Spark workloads on Amazon EKS with managed EMR capabilities. Choose from infrastructure deployment and storage optimization use cases.

<div className="getting-started-header">

## Getting Started

<div className="steps-grid">

<div className="step-card">
<div className="step-number">1</div>
<div className="step-content">
<h4>Deploy Infrastructure</h4>
<p>Start with the infrastructure deployment guide to set up your EMR on EKS foundation</p>
</div>
</div>

<div className="step-card">
<div className="step-number">2</div>
<div className="step-content">
<h4>Choose Storage Strategy</h4>
<p>Select the storage example that matches your performance and cost requirements</p>
</div>
</div>

<div className="step-card">
<div className="step-number">3</div>
<div className="step-content">
<h4>Submit Spark Jobs</h4>
<p>Run Spark applications with EMR managed runtime and optimized configurations</p>
</div>
</div>

<div className="step-card">
<div className="step-number">4</div>
<div className="step-content">
<h4>Monitor & Optimize</h4>
<p>Use EMR Studio, CloudWatch, and Spark UI for observability and performance tuning</p>
</div>
</div>

</div>

</div>

<div className="showcase-grid">

<div className="showcase-card featured">
<div className="showcase-header">
<div className="showcase-icon">🏗️</div>
<div className="showcase-content">
<h3>Infrastructure Deployment</h3>
<p className="showcase-description">Complete infrastructure deployment guide for EMR on EKS with virtual cluster setup, IAM roles, and Karpenter configuration</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">Infrastructure</span>
<span className="tag guide">Guide</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/emr-on-eks/infra" className="showcase-link">
<span>Deploy Infrastructure</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">💾</div>
<div className="showcase-content">
<h3>EBS Hostpath Storage</h3>
<p className="showcase-description">Cost-effective EBS root volume storage for Spark shuffle data. Simple setup with shared node storage and ~70% cost reduction vs per-pod PVCs</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag storage">Storage</span>
<span className="tag optimization">Optimization</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/emr-on-eks/ebs-hostpath" className="showcase-link">
<span>Learn More</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">💿</div>
<div className="showcase-content">
<h3>EBS Dynamic PVC Storage</h3>
<p className="showcase-description">Production-ready EBS Dynamic PVC with automatic volume provisioning for Spark shuffle storage. Isolated storage per executor with gp3 volumes</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag storage">Storage</span>
<span className="tag performance">Performance</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/emr-on-eks/ebs-pvc" className="showcase-link">
<span>Learn More</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card featured">
<div className="showcase-header">
<div className="showcase-icon">⚡</div>
<div className="showcase-content">
<h3>NVMe SSD Storage</h3>
<p className="showcase-description">Maximum I/O performance with NVMe instance store SSDs. Leverage local NVMe drives on Graviton instances for ultra-fast shuffle operations</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag storage">Storage</span>
<span className="tag performance">Performance</span>
<span className="tag optimization">Optimization</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/emr-on-eks/nvme-ssd" className="showcase-link">
<span>Learn More</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">🎯</div>
<div className="showcase-content">
<h3>EMR Spark Operator</h3>
<p className="showcase-description">Declarative Spark job management with Kubernetes-native EMR Spark Operator. GitOps-ready with SparkApplication CRDs for streamlined workflows</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag guide">Guide</span>
<span className="tag infrastructure">Infrastructure</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/emr-on-eks/emr-spark-operator" className="showcase-link">
<span>Learn More</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

{/* End of showcase grid */}
