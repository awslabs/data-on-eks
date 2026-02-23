---
title: PostgreSQL on EKS
sidebar_position: 0
---

import '@site/src/css/datastack-tiles.css';

# PostgreSQL on EKS 스택

Amazon EKS 기반 CloudNativePG를 사용한 프로덕션 준비 완료 PostgreSQL 데이터베이스. 자동 백업이 포함된 고가용성 관계형 데이터베이스를 배포하세요.

<div className="getting-started-header">

## 시작하기

<div className="steps-grid">

<div className="step-card">
<div className="step-number">1</div>
<div className="step-content">
<h4>인프라 배포</h4>
<p>HA 구성으로 CloudNativePG 연산자 설정</p>
</div>
</div>

<div className="step-card">
<div className="step-number">2</div>
<div className="step-content">
<h4>클러스터 생성</h4>
<p>레플리카 및 장애 조치가 포함된 PostgreSQL 클러스터 배포</p>
</div>
</div>

<div className="step-card">
<div className="step-number">3</div>
<div className="step-content">
<h4>백업 구성</h4>
<p>특정 시점 복구가 가능한 S3 자동 백업 활성화</p>
</div>
</div>

<div className="step-card">
<div className="step-number">4</div>
<div className="step-content">
<h4>모니터링 및 확장</h4>
<p>성능을 위한 메트릭 및 연결 풀링 사용</p>
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
<p className="showcase-description">CloudNativePG 및 HA 설정을 포함한 EKS 기반 PostgreSQL의 완전한 인프라 배포 가이드</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">Infrastructure</span>
<span className="tag guide">Guide</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/blueprints/distributed-databases/cloudnative-postgres" className="showcase-link">
<span>인프라 배포</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">💾</div>
<div className="showcase-content">
<h3>S3 백업 및 복구</h3>
<p className="showcase-description">WAL 아카이빙 및 PITR 기능을 갖춘 S3로의 PostgreSQL 자동 백업 구성</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag storage">Backup</span>
<span className="tag guide">Example</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/blueprints/distributed-databases/cloudnative-postgres" className="showcase-link">
<span>자세히 보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

{/* End of showcase grid */}
