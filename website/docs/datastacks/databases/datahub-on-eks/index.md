---
title: DataHub on EKS
sidebar_position: 3
---

import '@site/src/css/datastack-tiles.css';

{/*
  DataHub Examples Tiles Documentation:

  🎯 To add a new DataHub example tile:
  1. Copy the showcase-card template below and modify the content
  2. Update icon (emoji), title, description, tags, and link
  3. Use tag classes for specific colors: infrastructure, storage, performance, optimization, guide
  4. No CSS knowledge required!

  📚 Full documentation: /src/components/DatastackTileExamples.md
  🌟 Featured tiles: Add "featured" class to highlight special examples
*/}

# DataHub on EKS Stack

Production-ready DataHub metadata management and data governance examples for Amazon EKS. Enterprise data catalog and lineage tracking solutions.

<div className="getting-started-header">

## Getting Started

<div className="steps-grid">

<div className="step-card">
<div className="step-number">1</div>
<div className="step-content">
<h4>Deploy Infrastructure</h4>
<p>Start with the infrastructure deployment guide to set up your DataHub metadata foundation</p>
</div>
</div>

<div className="step-card">
<div className="step-number">2</div>
<div className="step-content">
<h4>Choose Your Use Case</h4>
<p>Select the data governance example that matches your enterprise metadata requirements</p>
</div>
</div>

<div className="step-card">
<div className="step-number">3</div>
<div className="step-content">
<h4>Follow Instructions</h4>
<p>Each example provides step-by-step deployment and data catalog configuration guides</p>
</div>
</div>

<div className="step-card">
<div className="step-number">4</div>
<div className="step-content">
<h4>Customize</h4>
<p>Adapt the configurations for your specific data governance and compliance needs</p>
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
<p className="showcase-description">Deploy a scalable DataHub platform on Amazon EKS with Terraform, Karpenter for node auto-scaling, and ArgoCD for GitOps management.</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">Infrastructure</span>
<span className="tag">EKS</span>
<span className="tag">Terraform</span>
<span className="tag">ArgoCD</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/databases/datahub-on-eks/infra" className="showcase-link">
<span>View Guide</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">🔂</div>
<div className="showcase-content">
<h3>CLI Metadata Ingestion</h3>
<p className="showcase-description">Use the DataHub CLI to ingest sample metadata into your DataHub instance and learn how to verify the results in the UI.</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag guide">Guide</span>
<span className="tag">CLI</span>
<span className="tag">Ingestion</span>
<span className="tag">Metadata</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/databases/datahub-on-eks/cli-ingestion" className="showcase-link">
<span>View Guide</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

{/* End of showcase grid - All styles are now in /src/css/datastack-tiles.css */}
