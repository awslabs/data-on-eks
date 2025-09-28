---
title: EMR on EKS
sidebar_position: 2
---

import '@site/src/css/datastack-tiles.css';

{/*
  EMR Examples Tiles Documentation:

  🎯 To add a new EMR example tile:
  1. Copy the showcase-card template below and modify the content
  2. Update icon (emoji), title, description, tags, and link
  3. Use tag classes for specific colors: infrastructure, storage, performance, optimization, guide
  4. No CSS knowledge required!

  📚 Full documentation: /src/components/DatastackTileExamples.md
  🌟 Featured tiles: Add "featured" class to highlight special examples
*/}

# EMR on EKS Blueprints

Production-ready Amazon EMR serverless examples and configurations for Amazon EKS. Enterprise-grade managed Spark and Hive workloads.

<div className="getting-started-header">

## Getting Started

<div className="steps-grid">

<div className="step-card">
<div className="step-number">1</div>
<div className="step-content">
<h4>Deploy Infrastructure</h4>
<p>Start with the infrastructure deployment guide to set up your EMR serverless foundation</p>
</div>
</div>

<div className="step-card">
<div className="step-number">2</div>
<div className="step-content">
<h4>Choose Your Use Case</h4>
<p>Select the managed workload example that matches your enterprise requirements</p>
</div>
</div>

<div className="step-card">
<div className="step-number">3</div>
<div className="step-content">
<h4>Follow Instructions</h4>
<p>Each example provides step-by-step deployment and EMR serverless configuration guides</p>
</div>
</div>

<div className="step-card">
<div className="step-number">4</div>
<div className="step-content">
<h4>Customize</h4>
<p>Adapt the configurations for your specific enterprise workloads and cost optimization needs</p>
</div>
</div>

</div>

</div>

<div className="showcase-grid">

{/*
  📋 TEMPLATE: Copy this structure to add a new EMR example tile

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
  <a href="/data-on-eks/docs/datastacks/emr-on-eks/example/" className="showcase-link">
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
<div className="showcase-icon">🚧</div>
<div className="showcase-content">
<h3>Coming Soon</h3>
<p className="showcase-description">EMR on EKS examples are currently under development. This will include EMR serverless integration with enterprise-grade features.</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">Infrastructure</span>
<span className="tag guide">Coming Soon</span>
</div>
<div className="showcase-footer">
<a href="https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/" className="showcase-link">
<span>View AWS Docs</span>
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
<h3>EMR Serverless Integration</h3>
<p className="showcase-description">Managed Spark execution with automatic scaling, cost optimization, and enterprise security features for EKS workloads.</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag performance">Serverless</span>
<span className="tag optimization">Cost Optimized</span>
</div>
<div className="showcase-footer">
<a href="https://docs.aws.amazon.com/emr/latest/EMR-Serverless-UserGuide/" className="showcase-link">
<span>Learn More</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

{/* End of showcase grid - All styles are now in /src/css/datastack-tiles.css */}
