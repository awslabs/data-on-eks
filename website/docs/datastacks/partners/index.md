---
title: AWS Partner Solutions
sidebar_position: 6
sidebar_label: AWS Partner Solutions
---

import '@site/src/css/datastack-tiles.css';
import '@site/src/css/getting-started.css';
import { Handshake, Database, Zap } from 'lucide-react';

<div className="hero-section">
  <div className="hero-content">
    <h1 className="hero-title">
      <Handshake size={56} className="inline-block mr-3" strokeWidth={2.5} />
      AWS Partner Solutions
    </h1>
    <p className="hero-subtitle">
      Partner integrations for data platforms on Amazon EKS
    </p>
  </div>
</div>

## Partner Ecosystem

Extend your data platform with AWS Partner solutions built for Amazon EKS. These integrations are production-ready and supported by AWS Partner Network.

<div className="datastacks-grid">

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Database size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>Altinity ClickHouse</h3>
<p className="datastack-description">Enterprise-grade ClickHouse on EKS with advanced features, support, and optimizations from Altinity.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Real-time Analytics</span>
<span className="feature-tag">OLAP Database</span>
<span className="feature-tag">Petabyte Scale</span>
<span className="feature-tag">Enterprise Support</span>
</div>
<div className="datastack-footer">
<a href="https://github.com/Altinity/terraform-aws-eks-clickhouse" className="datastack-link" target="_blank" rel="noopener">
<span>View on GitHub</span>
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
<h3>Aerospike</h3>
<p className="datastack-description">High-performance NoSQL database for real-time applications requiring ultra-low latency at scale.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Real-time NoSQL</span>
<span className="feature-tag">Sub-millisecond Latency</span>
<span className="feature-tag">Multi-model</span>
<span className="feature-tag">Enterprise Support</span>
</div>
<div className="datastack-footer">
<a href="https://aerospike.com/docs/kubernetes" className="datastack-link" target="_blank" rel="noopener">
<span>View Documentation</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

## Why Partner Solutions?

### Enterprise Support
Get commercial support and SLAs from AWS Partners for mission-critical workloads.

### Tested Integrations
Partner solutions are designed to work seamlessly with Data on EKS blueprints.

### Accelerated Deployment
Leverage pre-built integrations to reduce time-to-production for complex data platforms.

### Extended Capabilities
Access specialized tools and platforms that complement your open-source data stack.

## Partner Categories

Partner solutions span across all Data Stack categories:

- **Processing**: Advanced Spark optimizations, GPU acceleration, specialized compute
- **Streaming**: Enterprise Kafka distributions, stream processing platforms
- **Orchestration**: Managed Airflow services, workflow automation
- **Databases**: Commercial databases, specialized data stores (Altinity ClickHouse, Aerospike)
- **Observability**: APM tools, cost management, security platforms
- **AI/ML**: Vector databases, feature stores, model serving

---

:::info Become a Partner
Are you an AWS Partner with a data platform solution? Contact the Data on EKS team to showcase your integration.
:::

*For questions about partner solutions, visit our [GitHub repository](https://github.com/awslabs/data-on-eks) or contact AWS Partner Network.*
