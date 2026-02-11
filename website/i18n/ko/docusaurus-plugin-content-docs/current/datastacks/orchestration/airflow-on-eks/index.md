---
title: Airflow on EKS
sidebar_position: 0
---

import '@site/src/css/datastack-tiles.css';

# Apache Airflow on EKS 스택

Amazon EKS 기반 프로덕션 준비 완료 Apache Airflow 오케스트레이션 플랫폼. Kubernetes executor를 사용한 확장 가능한 워크플로우 자동화를 배포하세요.

<div className="getting-started-header">

## 시작하기

<div className="steps-grid">

<div className="step-card">
<div className="step-number">1</div>
<div className="step-content">
<h4>인프라 배포</h4>
<p>PostgreSQL 백엔드 및 Redis 큐와 함께 Airflow 설정</p>
</div>
</div>

<div className="step-card">
<div className="step-number">2</div>
<div className="step-content">
<h4>Executor 구성</h4>
<p>동적 태스크 스케일링을 위한 KubernetesExecutor 활성화</p>
</div>
</div>

<div className="step-card">
<div className="step-number">3</div>
<div className="step-content">
<h4>DAG 생성</h4>
<p>GitSync 또는 S3 스토리지로 데이터 파이프라인 배포</p>
</div>
</div>

<div className="step-card">
<div className="step-number">4</div>
<div className="step-content">
<h4>워크플로우 모니터링</h4>
<p>Airflow UI로 DAG 실행 및 태스크 로그 추적</p>
</div>
</div>

</div>

</div>

<div className="showcase-grid">

<div className="showcase-card featured">
<div className="showcase-header">
<div className="showcase-icon">🏗️</div>
<div className="showcase-content">
<h3>인프라 배포</h3>
<p className="showcase-description">HA 구성을 포함한 EKS 기반 Apache Airflow의 완전한 인프라 배포 가이드</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">Infrastructure</span>
<span className="tag guide">Guide</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/orchestration/airflow-on-eks/infra" className="showcase-link">
<span>인프라 배포</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">⚙️</div>
<div className="showcase-content">
<h3>Airflow에서 Spark 실행</h3>
<p className="showcase-description">데이터 파이프라인을 위한 SparkKubernetesOperator를 사용하여 EKS에서 Airflow로 Spark 작업 오케스트레이션</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag integration">Spark</span>
<span className="tag guide">Example</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/orchestration/airflow-on-eks/airflow" className="showcase-link">
<span>자세히 보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

{/* End of showcase grid */}
