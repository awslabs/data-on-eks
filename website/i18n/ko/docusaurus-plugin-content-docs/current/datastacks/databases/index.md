---
title: 데이터베이스
sidebar_position: 4
---

import '@site/src/css/datastack-tiles.css';

# 데이터베이스

Amazon EKS 기반 OLTP, OLAP 및 쿼리 엔진. 데이터 저장 및 쿼리를 위한 프로덕션 준비가 완료된 데이터베이스 및 분석 플랫폼을 배포하세요.

<div className="datastacks-grid">

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">🐘</div>
<div className="datastack-content">
<h3>PostgreSQL on EKS</h3>
<p className="datastack-description">고가용성 관계형 데이터베이스를 위한 CloudNativePG 기반 프로덕션 준비 완료 PostgreSQL.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">CloudNativePG</span>
<span className="feature-tag">High Availability</span>
<span className="feature-tag">S3 Backups</span>
<span className="feature-tag">Point-in-Time Recovery</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/datastacks/databases/postgres-on-eks/" className="datastack-link">
<span>PostgreSQL 살펴보기</span>
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
<h3>ClickHouse on EKS</h3>
<p className="datastack-description">실시간 분석 쿼리를 위한 컬럼형 스토리지 기반 고성능 OLAP 데이터베이스.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">OLAP Database</span>
<span className="feature-tag">Columnar Storage</span>
<span className="feature-tag">Distributed Clusters</span>
<span className="feature-tag">S3 Integration</span>
</div>
<div className="datastack-footer">
<button className="datastack-link" disabled>
<span>Coming Soon</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</button>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">🧭</div>
<div className="datastack-content">
<h3>DataHub on EKS</h3>
<p className="datastack-description">데이터 검색, 데이터 관측성 및 데이터 거버넌스를 위한 오픈소스 메타데이터 플랫폼.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Data Discovery</span>
<span className="feature-tag">Data Observability</span>
<span className="feature-tag">Data Governance</span>
<span className="feature-tag">Metadata Management</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/datastacks/databases/datahub-on-eks/" className="datastack-link">
<span>DataHub 살펴보기</span>
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
<h3>Pinot on EKS</h3>
<p className="datastack-description">사용자 대면 애플리케이션에서 초저지연 분석을 위한 실시간 OLAP 데이터스토어.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Real-time OLAP</span>
<span className="feature-tag">Sub-second Queries</span>
<span className="feature-tag">Kafka Ingestion</span>
<span className="feature-tag">Star-tree Indexes</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/datastacks/databases/pinot-on-eks/" className="datastack-link">
<span>Pinot 살펴보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">📈</div>
<div className="datastack-content">
<h3>Superset on EKS</h3>
<p className="datastack-description">데이터 탐색 및 시각화를 위한 Apache Superset 비즈니스 인텔리전스 플랫폼.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Business Intelligence</span>
<span className="feature-tag">Interactive Dashboards</span>
<span className="feature-tag">SQL Editor</span>
<span className="feature-tag">RBAC</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/datastacks/databases/superset-on-eks/" className="datastack-link">
<span>Superset 살펴보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">🔍</div>
<div className="datastack-content">
<h3>Trino on EKS</h3>
<p className="datastack-description">데이터 레이크, 웨어하우스 및 여러 데이터 소스를 쿼리하기 위한 분산 SQL 쿼리 엔진.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Query Engine</span>
<span className="feature-tag">Federated Queries</span>
<span className="feature-tag">KEDA Autoscaling</span>
<span className="feature-tag">Fault Tolerance</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/datastacks/databases/trino-on-eks/" className="datastack-link">
<span>Trino 살펴보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

{/* End of DataStacks grid */}
