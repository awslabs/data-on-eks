---
title: Data Stacks
sidebar_position: 0
---

import '@site/src/css/datastack-tiles.css';

{/*
  DataStack Tiles Documentation:

  🎯 To add a new DataStack tile:
  1. Copy the template below and modify the content
  2. Update icon (emoji), title, description, features, and link
  3. No CSS knowledge required!

  📚 Full documentation: /src/components/DatastackTileExamples.md
  🎨 Colors: Tags automatically get gradient colors based on position (1st=purple, 2nd=pink, 3rd=blue, 4th=green)
*/}

# Data Stacks on EKS

Production-ready data platform stacks for Amazon EKS. Each DataStack provides a complete infrastructure foundation with curated examples and best practices.

<div className="datastacks-grid">

{/*
  📋 TEMPLATE: Copy this structure to add a new DataStack tile

  <div className="datastack-card">
  <div className="datastack-header">
  <div className="datastack-icon">🎯</div>
  <div className="datastack-content">
  <h3>Your Service Name</h3>
  <p className="datastack-description">Brief description of your service and main benefits.</p>
  </div>
  </div>
  <div className="datastack-features">
  <span className="feature-tag">Feature 1</span>
  <span className="feature-tag">Feature 2</span>
  <span className="feature-tag">Feature 3</span>
  <span className="feature-tag">Feature 4</span>
  </div>
  <div className="datastack-footer">
  <a href="/data-on-eks/docs/datastacks/your-service/" className="datastack-link">
  <span>Explore Service</span>
  <svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
  <path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
  </svg>
  </a>
  </div>
  </div>
*/}

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">🔥</div>
<div className="datastack-content">
<h3>Spark on EKS</h3>
<p className="datastack-description">Apache Spark processing platform with auto-scaling, monitoring, and performance optimization.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Spark Operator</span>
<span className="feature-tag">Karpenter</span>
<span className="feature-tag">History Server</span>
<span className="feature-tag">Monitoring</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/datastacks/spark-on-eks/" className="datastack-link">
<span>Explore Spark</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">🌊</div>
<div className="datastack-content">
<h3>Flink on EKS</h3>
<p className="datastack-description">Apache Flink streaming platform for real-time data processing and event-driven applications.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Flink Operator</span>
<span className="feature-tag">Stream Processing</span>
<span className="feature-tag">Kafka Integration</span>
<span className="feature-tag">State Management</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/datastacks/flink-on-eks/" className="datastack-link">
<span>Explore Flink</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">⚡</div>
<div className="datastack-content">
<h3>EMR on EKS</h3>
<p className="datastack-description">Amazon EMR serverless integration with EKS for managed Spark and Hive workloads.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">EMR Serverless</span>
<span className="feature-tag">Managed Jobs</span>
<span className="feature-tag">Auto Scaling</span>
<span className="feature-tag">Cost Optimized</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/datastacks/emr-on-eks/" className="datastack-link">
<span>Explore EMR</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">📊</div>
<div className="datastack-content">
<h3>DataHub on EKS</h3>
<p className="datastack-description">Metadata management and data governance platform for enterprise data catalogs.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Data Catalog</span>
<span className="feature-tag">Lineage Tracking</span>
<span className="feature-tag">Governance</span>
<span className="feature-tag">Search & Discovery</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/datastacks/datahub-on-eks/" className="datastack-link">
<span>Explore DataHub</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

{/* End of DataStacks grid - All styles are now in /src/css/datastack-tiles.css */}
