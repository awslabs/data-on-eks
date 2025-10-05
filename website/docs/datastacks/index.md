---
title: Data Stacks
sidebar_position: 0
sidebar_label: Overview
---

import '@site/src/css/datastack-tiles.css';
import '@site/src/css/getting-started.css';
import DataStacksHero from '@site/src/components/DataStacks/DataStacksHero';
import { Cpu, Waves, GitBranch, Database, BookOpen } from 'lucide-react';

<DataStacksHero />

## Explore Data Platform Categories

<div className="datastacks-grid">

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Cpu size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>Processing</h3>
<p className="datastack-description">Scalable batch and distributed data processing with Spark, EMR, Ray, and GPU acceleration.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Spark on EKS</span>
<span className="feature-tag">EMR Variants</span>
<span className="feature-tag">Ray Data</span>
<span className="feature-tag">AWS Batch</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/datastacks/processing/" className="datastack-link">
<span>Explore Processing</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Waves size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>Streaming</h3>
<p className="datastack-description">Real-time data streaming and event-driven platforms with Kafka and Flink.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Kafka on EKS</span>
<span className="feature-tag">Flink on EKS</span>
<span className="feature-tag">EMR Flink</span>
<span className="feature-tag">Event Streaming</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/datastacks/streaming/" className="datastack-link">
<span>Explore Streaming</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <GitBranch size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>Orchestration</h3>
<p className="datastack-description">Workflow automation and pipeline orchestration with Airflow, Argo, and MWAA.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Airflow on EKS</span>
<span className="feature-tag">Argo Workflows</span>
<span className="feature-tag">Amazon MWAA</span>
<span className="feature-tag">DAG Workflows</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/datastacks/orchestration/" className="datastack-link">
<span>Explore Orchestration</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Database size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>Databases</h3>
<p className="datastack-description">OLTP, OLAP databases and business intelligence platforms for data storage and analytics.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">PostgreSQL</span>
<span className="feature-tag">ClickHouse</span>
<span className="feature-tag">Pinot</span>
<span className="feature-tag">Superset BI</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/datastacks/databases/" className="datastack-link">
<span>Explore Databases</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <BookOpen size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>Workshops</h3>
<p className="datastack-description">Hands-on learning experiences with guided labs for building end-to-end data platforms.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Hands-on Labs</span>
<span className="feature-tag">End-to-End Pipelines</span>
<span className="feature-tag">Best Practices</span>
<span className="feature-tag">JupyterHub</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/datastacks/workshops/" className="datastack-link">
<span>Start Workshop</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

{/* End of DataStacks grid */}
