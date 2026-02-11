---
title: 데이터 스택
sidebar_position: 0
sidebar_label: 개요
---

import '@site/src/css/datastack-tiles.css';
import '@site/src/css/getting-started.css';
import DataStacksHero from '@site/src/components/DataStacks/DataStacksHero';
import { Cpu, Waves, GitBranch, Database, BookOpen, Handshake } from 'lucide-react';

<DataStacksHero />

## 데이터 플랫폼 카테고리 살펴보기

<div className="datastacks-grid">

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Cpu size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>프로세싱(Processing)</h3>
<p className="datastack-description">Spark, EMR, Ray 및 GPU 가속을 활용한 확장 가능한 배치 및 분산 데이터 처리.</p>
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
<span>프로세싱 살펴보기</span>
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
<h3>스트리밍(Streaming)</h3>
<p className="datastack-description">Kafka와 Flink를 활용한 실시간 데이터 스트리밍 및 이벤트 기반 플랫폼.</p>
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
<span>스트리밍 살펴보기</span>
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
<h3>오케스트레이션(Orchestration)</h3>
<p className="datastack-description">Airflow, Argo, MWAA를 활용한 워크플로우 자동화 및 파이프라인 오케스트레이션.</p>
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
<span>오케스트레이션 살펴보기</span>
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
<h3>데이터베이스(Databases)</h3>
<p className="datastack-description">데이터 저장 및 분석을 위한 OLTP, OLAP 데이터베이스 및 비즈니스 인텔리전스 플랫폼.</p>
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
<span>데이터베이스 살펴보기</span>
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
<h3>워크샵(Workshops)</h3>
<p className="datastack-description">엔드투엔드 데이터 플랫폼 구축을 위한 가이드 실습과 함께하는 실전 학습 경험.</p>
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
<span>워크샵 시작하기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Handshake size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>AWS 파트너 솔루션</h3>
<p className="datastack-description">엔터프라이즈 지원이 포함된 Amazon EKS 기반 데이터 플랫폼을 위한 파트너 통합.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Enterprise Support</span>
<span className="feature-tag">Production Ready</span>
<span className="feature-tag">AWS Partners</span>
<span className="feature-tag">Tested Integrations</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/datastacks/partners/" className="datastack-link">
<span>파트너 살펴보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

{/* End of DataStacks grid */}
