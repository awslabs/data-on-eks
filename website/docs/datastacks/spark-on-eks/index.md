---
title: Spark on EKS
sidebar_position: 0
---

import '@site/src/css/datastack-tiles.css';

{/*
  Spark Examples Tiles Documentation:

  🎯 To add a new Spark example tile:
  1. Copy the showcase-card template below and modify the content
  2. Update icon (emoji), title, description, tags, and link
  3. Use tag classes for specific colors: infrastructure, storage, performance, optimization, guide
  4. No CSS knowledge required!

  📚 Full documentation: /src/components/DatastackTileExamples.md
  🌟 Featured tiles: Add "featured" class to highlight special examples
*/}

# Spark on EKS Blueprints

Production-ready Apache Spark examples and configurations for Amazon EKS. Choose from infrastructure deployment and advanced use cases.

<div className="getting-started-header">

## Getting Started

<div className="steps-grid">

<div className="step-card">
<div className="step-number">1</div>
<div className="step-content">
<h4>Deploy Infrastructure</h4>
<p>Start with the infrastructure deployment guide to set up your Spark on EKS foundation</p>
</div>
</div>

<div className="step-card">
<div className="step-number">2</div>
<div className="step-content">
<h4>Choose Your Use Case</h4>
<p>Select the example that matches your storage and performance requirements</p>
</div>
</div>

<div className="step-card">
<div className="step-number">3</div>
<div className="step-content">
<h4>Follow Instructions</h4>
<p>Each example provides step-by-step deployment and verification guides</p>
</div>
</div>

<div className="step-card">
<div className="step-number">4</div>
<div className="step-content">
<h4>Customize</h4>
<p>Adapt the configurations for your specific workload and performance needs</p>
</div>
</div>

</div>

</div>

<div className="showcase-grid">

{/*
  📋 TEMPLATE: Copy this structure to add a new Spark example tile

  <div className="showcase-card">
  <div className="showcase-header">
  <div className="showcase-icon">🎯</div>
  <div className="showcase-content">
  <h3>Example Title</h3>
  <p className="showcase-description">Detailed description of this example or use case.</p>
  </div>
  </div>
  <div className="showcase-tags">
  <span className="tag infrastructure">Infrastructure</span>
  <span className="tag storage">Storage</span>
  <span className="tag performance">Performance</span>
  </div>
  <div className="showcase-footer">
  <a href="/data-on-eks/docs/datastacks/spark-on-eks/example/" className="showcase-link">
  <span>Learn More</span>
  <svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
  <path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
  </svg>
  </a>
  </div>
  </div>

  💡 For featured tiles, add "featured" class: <div className="showcase-card featured">
*/}

<div className="showcase-card featured">
<div className="showcase-header">
<div className="showcase-icon">🏗️</div>
<div className="showcase-content">
<h3>Infrastructure Deployment</h3>
<p className="showcase-description">Complete infrastructure deployment guide with configuration options and customization for Spark on EKS</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">Infrastructure</span>
<span className="tag guide">Guide</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/spark-on-eks/infra" className="showcase-link">
<span>Deploy Infrastructure</span>
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
<p className="showcase-description">Production-ready EBS Dynamic PVC with fault tolerance, PVC reuse, and automatic volume provisioning for Spark shuffle storage</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag storage">Storage</span>
<span className="tag performance">Performance</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/spark-on-eks/ebs-pvc-storage" className="showcase-link">
<span>Learn More</span>
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
<h3>EBS Node Storage</h3>
<p className="showcase-description">Cost-effective shared EBS volume per node for Spark shuffle storage. ~70% cost reduction vs per-pod PVCs with potential noisy neighbor trade-offs</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag storage">Storage</span>
<span className="tag optimization">Optimization</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/spark-on-eks/ebs-node-storage" className="showcase-link">
<span>Learn More</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">⚡</div>
<div className="showcase-content">
<h3>NVMe Instance Storage</h3>
<p className="showcase-description">Leverage instance store NVMe SSDs for maximum I/O performance and cost optimization with local data processing</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag storage">Storage</span>
<span className="tag performance">Performance</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/spark-on-eks/nvme-storage" className="showcase-link">
<span>Learn More</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

{/* End of showcase grid - All styles are now in /src/css/datastack-tiles.css */}
