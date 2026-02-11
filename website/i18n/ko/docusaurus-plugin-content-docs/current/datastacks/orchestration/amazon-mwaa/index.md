---
title: Amazon MWAA
sidebar_position: 0
---

import '@site/src/css/datastack-tiles.css';

# Amazon MWAA 스택

EKS와 통합된 Amazon MWAA로 관리형 Apache Airflow. 완전 관리형 워크플로우 오케스트레이션과 Kubernetes 통합을 배포하세요.

<div className="getting-started-header">

## 시작하기

<div className="steps-grid">

<div className="step-card">
<div className="step-number">1</div>
<div className="step-content">
<h4>인프라 배포</h4>
<p>EKS 클러스터 통합과 함께 MWAA 환경 설정</p>
</div>
</div>

<div className="step-card">
<div className="step-number">2</div>
<div className="step-content">
<h4>DAG 구성</h4>
<p>MWAA에 자동 동기화되는 S3에 워크플로우 저장</p>
</div>
</div>

<div className="step-card">
<div className="step-number">3</div>
<div className="step-content">
<h4>작업 오케스트레이션</h4>
<p>MWAA 워크플로우에서 Spark, EMR 및 EKS 작업 실행</p>
</div>
</div>

<div className="step-card">
<div className="step-number">4</div>
<div className="step-content">
<h4>모니터링 및 확장</h4>
<p>CloudWatch 및 자동 스케일링으로 DAG 실행 추적</p>
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
<p className="showcase-description">EKS 통합 및 VPC 설정을 포함한 Amazon MWAA의 완전한 인프라 배포 가이드</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">Infrastructure</span>
<span className="tag guide">Guide</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/blueprints/job-schedulers/aws-managed-airflow" className="showcase-link">
<span>인프라 배포</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">🔗</div>
<div className="showcase-content">
<h3>MWAA와 EKS 작업</h3>
<p className="showcase-description">컨테이너화된 워크플로우를 위한 KubernetesPodOperator를 사용하여 MWAA에서 EKS의 Kubernetes 작업 오케스트레이션</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag integration">EKS</span>
<span className="tag guide">Example</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/blueprints/job-schedulers/aws-managed-airflow" className="showcase-link">
<span>자세히 보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

{/* End of showcase grid */}
