---
title: ClickHouse on EKS
sidebar_position: 0
---

import '@site/src/css/datastack-tiles.css';

# ClickHouse on EKS Stack
[ClickHouse](https://clickhouse.com/) is a high-performance, column-oriented SQL database management system (DBMS) for online analytical processing (OLAP) that is open sourced under the Apache 2.0 license.


OLAP is software technology you can use to analyze business data from different points of view. Organizations collect and store data from multiple data sources, such as websites, applications, smart meters, and internal systems. OLAP helps organizations process and benefit from a growing amount of information by combining and groups this data into categories to provide actionable insights for strategic planning. For example, a retailer stores data about all the products it sells, such as color, size, cost, and location. The retailer also collects customer purchase data, such as the name of the items ordered and total sales value, in a different system. OLAP combines the datasets to answer questions such as which color products are more popular or how product placement impacts sales.

**Some key benefits of Clickhouse include:**

* Real-Time Analytics: ClickHouse can handle real-time data ingestion and analysis, making it suitable for use cases such as monitoring, logging, and event data processing.
* High Performance: ClickHouse is optimized for analytical workloads, providing fast query execution and high throughput.
* Scalability: ClickHouse is designed to scale horizontally across multiple nodes, allowing users to store and process petabytes of data across a distributed cluster. It supports sharding and replication for high availability and fault tolerance.
* Column-Oriented Storage: ClickHouse organizes data by columns rather than rows, which allows for efficient compression and faster query processing, especially for queries that involve aggregations and scans of large datasets.
* SQL Support: ClickHouse supports a subset of SQL, making it familiar and easy to use for developers and analysts who are already familiar with SQL-based databases.
* Integrated Data Formats: ClickHouse supports various data formats, including CSV, JSON, Apache Avro, and Apache Parquet, making it flexible for ingesting and querying different types of data.



Production-ready ClickHouse OLAP database on Amazon EKS. Deploy high-performance analytical databases with columnar storage.

<div style={{
  background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
  color: 'white',
  padding: '30px',
  borderRadius: '12px',
  textAlign: 'center',
  margin: '30px 0',
  boxShadow: '0 4px 6px rgba(0,0,0,0.1)'
}}>
  <h2 style={{margin: '0 0 10px 0'}}>🚧 Coming Soon</h2>
  <p style={{margin: 0, opacity: 0.9}}>This data stack is currently under development. Check back soon for deployment guides and examples!</p>
</div>

<!-- <div className="getting-started-header">

## Getting Started

<div className="steps-grid">

<div className="step-card">
<div className="step-number">1</div>
<div className="step-number">1</div>
<div className="step-content">
<h4>Deploy Infrastructure</h4>
<p>Set up ClickHouse operator with distributed clusters</p>
</div>
</div>

<div className="step-card">
<div className="step-number">2</div>
<div className="step-content">
<h4>Create Tables</h4>
<p>Define schemas with MergeTree engines and partitioning</p>
</div>
</div>

<div className="step-card">
<div className="step-number">3</div>
<div className="step-content">
<h4>Ingest Data</h4>
<p>Stream data from Kafka or batch load from S3</p>
</div>
</div>

<div className="step-card">
<div className="step-number">4</div>
<div className="step-content">
<h4>Query Analytics</h4>
<p>Run blazing-fast SQL queries on billions of rows</p>
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
<p className="showcase-description">Complete infrastructure deployment guide for ClickHouse on EKS with distributed cluster setup</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">Infrastructure</span>
<span className="tag guide">Guide</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/clickhouse-on-eks/infra" className="showcase-link">
<span>Deploy Infrastructure</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">📊</div>
<div className="showcase-content">
<h3>S3 Data Lake Analytics</h3>
<p className="showcase-description">Query S3 data lakes directly with ClickHouse S3 table functions for serverless analytics</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag storage">Data Lake</span>
<span className="tag guide">Example</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/clickhouse-on-eks/s3-analytics" className="showcase-link">
<span>Learn More</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div> -->
