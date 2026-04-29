---
title: AI Agents for Data
sidebar_position: 3
sidebar_label: AI Agents for Data
---

import '@site/src/css/datastack-tiles.css';

# AI Agents for Data

**Autonomous AI agents that monitor, investigate, and act on your data — without a human in the loop.**

These reference architectures show how to wire together Amazon Bedrock, LangGraph, MCP servers, and your data stack on Amazon EKS to build agents that compress hours of manual investigation into automated, real-time decisions.

---

## What is an Agentic Data System?

Traditional tools answer questions **you already know to ask**. You write a query, you get data back.

An **agentic system** decides for itself **what questions to ask**. You give it a goal — "CTR dropped, find the root cause" — and it figures out the investigation plan, fetches the data, reads the results, and delivers a written report.

> Think of the difference between a calculator and a data analyst.
> A calculator does exactly what you type. An analyst hears your problem, goes and investigates, and comes back with an answer — at any hour, for any number of incidents, simultaneously.

---

## Agent Examples

<div className="showcase-grid">

<div className="showcase-card featured">
<div className="showcase-header">
<div className="showcase-icon">📊</div>
<div className="showcase-content">
<h3>Agentic Ad Intelligence</h3>
<p className="showcase-description">Autonomous root-cause analysis for ad performance anomalies. When CTR drops, the agent investigates across every dimension — creative, placement, device, country — and delivers a written incident report automatically.</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">LangGraph</span>
<span className="tag guide">Amazon Bedrock</span>
<span className="tag infrastructure">StarRocks</span>
<span className="tag guide">MCP Server</span>
<span className="tag infrastructure">Real-time</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/ai-ml/ai-agents/agentic-ad-intelligence" className="showcase-link">
<span>View Example</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">🔍</div>
<div className="showcase-content">
<h3>Spark Diagnostics Agent</h3>
<p className="showcase-description">AI-powered Spark job analyzer using LangGraph. Detects OOM errors, data skew, and shuffle problems — automatically suggests fixes or creates incident tickets.</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">LangGraph</span>
<span className="tag guide">Amazon Bedrock</span>
<span className="tag infrastructure">Apache Spark</span>
<span className="tag guide">Auto-Diagnosis</span>
</div>
<div className="showcase-footer">
<button className="datastack-link" disabled>
<span>Coming Soon</span>
</button>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">💰</div>
<div className="showcase-content">
<h3>Cost Optimization Agent</h3>
<p className="showcase-description">ML-driven resource analysis across your EKS data workloads. Recommends optimal instance types, spot vs. on-demand mix, and right-sizing configurations.</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">LangGraph</span>
<span className="tag guide">Amazon Bedrock</span>
<span className="tag infrastructure">Karpenter</span>
<span className="tag guide">Cost Optimization</span>
</div>
<div className="showcase-footer">
<button className="datastack-link" disabled>
<span>Coming Soon</span>
</button>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">🛡️</div>
<div className="showcase-content">
<h3>Data Quality Agent</h3>
<p className="showcase-description">Continuously validates streaming data, detects schema drift, identifies PII leakage, and triggers automated remediation workflows — before bad data reaches downstream consumers.</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">LangGraph</span>
<span className="tag guide">Amazon Bedrock</span>
<span className="tag infrastructure">Kafka</span>
<span className="tag guide">Data Quality</span>
</div>
<div className="showcase-footer">
<button className="datastack-link" disabled>
<span>Coming Soon</span>
</button>
</div>
</div>

</div>

---

## Technology Stack

All agents in this collection are built on the same foundation:

| Layer | Technology | Role |
|---|---|---|
| **AI Model** | Amazon Bedrock — Claude Sonnet 4.6 | Reasoning, SQL generation, report writing |
| **Agent Orchestration** | LangGraph | State machine — defines the investigation workflow |
| **Data Connector** | MCP Server (Model Context Protocol) | Safe, structured tool interface between the AI and your database |
| **Data Warehouse** | StarRocks / other EKS data stacks | Where the data lives and queries run |
| **Auth** | IRSA (IAM Roles for Service Accounts) | Agent pods get AWS permissions with zero secrets or API keys |
| **Platform** | Amazon EKS | Runs everything — agents, databases, and connectors as Kubernetes workloads |

---

## Why Agents on EKS?

Running AI agents as Kubernetes workloads — alongside your data stacks — means you get:

- **IRSA** — no API keys or secrets. Agents get AWS permissions through pod identity, just like any other service
- **Co-location** — agents run in the same cluster as your database. MCP server calls are in-cluster, sub-millisecond
- **Scalability** — Karpenter scales agent pods the same way it scales Spark executors or StarRocks BE nodes
- **GitOps** — agent deployments are YAML manifests, version-controlled and deployed via ArgoCD like everything else
- **Observability** — Prometheus and Grafana already running for your data stacks pick up agent metrics too
