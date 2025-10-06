---
title: AI for Data
sidebar_position: 1
sidebar_label: Overview
---

import '@site/src/css/datastack-tiles.css';
import '@site/src/css/getting-started.css';
import AIforDataHero from '@site/src/components/AIforData/AIforDataHero';
import { Database, Cpu } from 'lucide-react';

<AIforDataHero />

## AI-Native Data Infrastructure

Transform your data platforms with AI capabilities. From vector databases for semantic search to intelligent agents that automatically diagnose Spark jobs, these stacks bring cutting-edge AI to your data operations on Amazon EKS.

<div className="datastacks-grid">

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Database size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>Vector Databases</h3>
<p className="datastack-description">High-performance vector storage and similarity search for AI applications, embeddings, and semantic data retrieval.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Milvus on EKS</span>
<span className="feature-tag">pgvector</span>
<span className="feature-tag">Weaviate</span>
<span className="feature-tag">Semantic Search</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/ai-ml/vector-databases" className="datastack-link">
<span>Explore Vector DBs</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Cpu size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>AI Agents for Data</h3>
<p className="datastack-description">Intelligent agents that automatically monitor, diagnose, and optimize your data workloads using AI.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Spark Diagnostics</span>
<span className="feature-tag">Auto-Optimization</span>
<span className="feature-tag">Anomaly Detection</span>
<span className="feature-tag">LangGraph</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/ai-ml/ai-agents" className="datastack-link">
<span>Explore AI Agents</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

## Why AI for Data on EKS?

The convergence of AI and data infrastructure opens new possibilities for intelligent systems. By running vector databases and AI agents on Amazon EKS, you get:

### Intelligence at Scale
Deploy vector databases like Milvus alongside your existing data stacks to enable semantic search across billions of embeddings with sub-second latency.

### Automated Operations
AI agents monitor your Spark jobs, Kafka streams, and Airflow DAGs—automatically detecting anomalies, optimizing configurations, and preventing failures before they happen.

### Cost Optimization
Machine learning models analyze resource usage patterns and recommend optimal configurations, reducing cloud spend while improving performance.

### Unified Platform
Run everything on Kubernetes: your data processing (Spark), streaming (Kafka), orchestration (Airflow), and now AI agents—all managed through GitOps with ArgoCD.

## Use Cases

### Semantic Search for Data Discovery
Build a data catalog where users can ask natural language questions like "find all tables containing customer payment data" and get AI-powered results using vector similarity.

### Spark Job Auto-Diagnostics
Deploy an AI agent that watches every Spark job, detects common failure patterns (OOM errors, data skew, shuffle problems), and automatically suggests fixes or creates JIRA tickets.

### Real-time Data Quality
AI agents continuously validate streaming data, detect schema drift, identify PII leakage, and trigger automated remediation workflows.

### Intelligent Cost Management
ML models predict resource usage, recommend spot vs on-demand instance mixes, and automatically scale clusters based on workload patterns.

## Technology Stack

Our AI for Data stacks are built on:

- **Vector Databases**: Milvus, Weaviate, pgvector for embeddings storage
- **AI Frameworks**: LangChain, LangGraph for agent orchestration
- **Compute**: Amazon EKS with Karpenter for GPU/CPU autoscaling
- **Storage**: Amazon S3 for data lakes, EBS/EFS for vector indices
- **Observability**: Prometheus, Grafana for agent monitoring
- **GitOps**: ArgoCD for declarative AI infrastructure

:::tip Coming Soon
We're actively developing production-ready examples for:
- **Milvus on EKS** - Distributed vector database deployment
- **pgvector on EKS** - PostgreSQL with vector similarity search
- **Spark Diagnostics Agent** - AI-powered Spark job analyzer using LangGraph
- **Performance Optimization Agent** - Automated query and configuration tuning
:::

## Get Started

1. **Explore Vector Databases** - Start with Milvus or pgvector for semantic search capabilities
2. **Deploy AI Agents** - Try the Spark Diagnostics agent to analyze your existing jobs and automatically optimize configurations

---

*For questions or contributions, visit our [GitHub repository](https://github.com/awslabs/data-on-eks) or join the community discussions.*
