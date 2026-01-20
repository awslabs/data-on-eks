---
title: Benchmarks
sidebar_position: 1
sidebar_label: Overview
---

import '@site/src/css/datastack-tiles.css';
import '@site/src/css/getting-started.css';
import BenchmarksHero from '@site/src/components/Benchmarks/BenchmarksHero';
import { Settings, BarChart3, Cpu, Zap } from 'lucide-react';

<BenchmarksHero />

## Benchmark Results & Setup

<div className="datastacks-grid">

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Settings size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>Benchmark Setup</h3>
<p className="datastack-description">Complete guide for setting up TPC-DS benchmark infrastructure, data generation, and test execution.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Data Generation</span>
<span className="feature-tag">Test Configuration</span>
<span className="feature-tag">Infrastructure Setup</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/benchmarks/spark-operator-benchmark/data-generation" className="datastack-link">
<span>Setup Guide</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <BarChart3 size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>EMR on EKS TPC-DS</h3>
<p className="datastack-description">Comprehensive TPC-DS 3TB benchmark comparing EMR on EKS performance across different configurations.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">TPC-DS 3TB</span>
<span className="feature-tag">EMR on EKS</span>
<span className="feature-tag">Cost Analysis</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/benchmarks/emr-on-eks" className="datastack-link">
<span>View Results</span>
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
<h3>Spark Graviton R Series</h3>
<p className="datastack-description">Performance benchmarks comparing ARM-based Graviton processors with x86 instances for Spark workloads.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Graviton3</span>
<span className="feature-tag">R7g vs R6i</span>
<span className="feature-tag">Cost/Performance</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/benchmarks/spark-operator-benchmark/graviton-r-data" className="datastack-link">
<span>View Results</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Zap size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>Spark Gluten + Velox</h3>
<p className="datastack-description">Acceleration benchmarks using Gluten and Velox vectorized execution engine for Spark on EKS.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Vectorized Execution</span>
<span className="feature-tag">Native Engine</span>
<span className="feature-tag">2-3x Speedup</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/benchmarks/spark-gluten-velox-benchmark" className="datastack-link">
<span>View Results</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

## About TPC-DS Benchmarks

**TPC-DS** (Transaction Processing Performance Council - Decision Support) is the industry-standard benchmark for evaluating the performance of decision support systems. Our benchmarks use:

- **Dataset Sizes**: 1TB and 3TB scales
- **Query Suite**: 99 queries covering complex analytical patterns
- **Metrics**: Query execution time, cost per query, resource utilization
- **Infrastructure**: Amazon EKS with Karpenter autoscaling, Spot instances

All benchmarks are reproducible using the setup guides provided. Results include detailed methodology, infrastructure configuration, and cost analysis.
