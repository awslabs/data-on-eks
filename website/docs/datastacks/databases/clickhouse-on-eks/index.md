---
title: ClickHouse on EKS
sidebar_position: 1
---

import '@site/src/css/datastack-tiles.css';

{/*
  ClickHouse Examples Tiles Documentation:

  🎯 To add a new ClickHouse example tile:
  1. Copy the showcase-card template below and modify the content
  2. Update icon (emoji), title, description, tags, and link
  3. Use tag classes for specific colors: infrastructure, storage, performance, optimization, guide
  4. No CSS knowledge required!

  📚 Full documentation: /src/components/DatastackTileExamples.md
  🌟 Featured tiles: Add "featured" class to highlight special examples
*/}

# ClickHouse on EKS Stack

[ClickHouse](https://clickhouse.com/) deployment on Amazon EKS — a high-performance, column-oriented OLAP database for real-time analytics on petabyte-scale datasets. This stack provisions a sharded, replicated ClickHouse cluster managed by the [ClickHouse Kubernetes operator](https://github.com/Altinity/clickhouse-operator) with a dedicated [ClickHouse Keeper](https://clickhouse.com/docs/en/guides/sre/keeper/clickhouse-keeper) ensemble for replication and distributed DDL coordination.

<div className="getting-started-header">

## Getting Started

<div className="steps-grid">

<div className="step-card">
<div className="step-number">1</div>
<div className="step-content">
<h4>Deploy Infrastructure</h4>
<p>Provision the EKS cluster, Karpenter node pools, and the ClickHouse operator with ArgoCD</p>
</div>
</div>

<div className="step-card">
<div className="step-number">2</div>
<div className="step-content">
<h4>Launch a ClickHouse Cluster</h4>
<p>Deploy a sharded, replicated ClickHouse installation backed by ClickHouse Keeper</p>
</div>
</div>

<div className="step-card">
<div className="step-number">3</div>
<div className="step-content">
<h4>Load Sample Data</h4>
<p>Ingest the ClickHouse <code>hits</code> dataset from S3 into a Distributed/ReplicatedMergeTree table</p>
</div>
</div>

<div className="step-card">
<div className="step-number">4</div>
<div className="step-content">
<h4>Query and Test Failover</h4>
<p>Run analytical queries, inspect index usage with <code>EXPLAIN</code>, and validate replica failover</p>
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
<p className="showcase-description">Deploy a scalable ClickHouse platform on Amazon EKS with Terraform, Karpenter for node auto-scaling, ArgoCD for GitOps management, and the ClickHouse operator for cluster lifecycle.</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">Infrastructure</span>
<span className="tag">EKS</span>
<span className="tag">Terraform</span>
<span className="tag">ArgoCD</span>
<span className="tag">Karpenter</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/databases/clickhouse-on-eks/infra" className="showcase-link">
<span>View Guide</span>
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
<h3>Sample Workload: Hits Dataset</h3>
<p className="showcase-description">Load the canonical ClickHouse <code>hits</code> Parquet dataset from S3 into a Distributed table over ReplicatedMergeTree, run analytical queries, and demonstrate replica failover by deleting a pod.</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag guide">Example</span>
<span className="tag performance">OLAP</span>
<span className="tag storage">S3</span>
<span className="tag">Replication</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/databases/clickhouse-on-eks/sample-workload" className="showcase-link">
<span>View Guide</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

{/* End of showcase grid - All styles are now in /src/css/datastack-tiles.css */}
