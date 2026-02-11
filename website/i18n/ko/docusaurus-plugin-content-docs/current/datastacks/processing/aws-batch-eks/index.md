---
title: AWS Batch on EKS
sidebar_position: 0
---

import '@site/src/css/datastack-tiles.css';

# AWS Batch on EKS 스택

Amazon EKS에서 배치 컴퓨팅 워크로드를 실행하기 위한 프로덕션 준비 AWS Batch 구성입니다. 관리형 배치 작업 오케스트레이션을 활용하세요.

<div className="getting-started-header">

## 시작하기

<div className="steps-grid">

<div className="step-card">
<div className="step-number">1</div>
<div className="step-content">
<h4>인프라 배포</h4>
<p>EKS 클러스터에 AWS Batch 컴퓨팅 환경 설정</p>
</div>
</div>

<div className="step-card">
<div className="step-number">2</div>
<div className="step-content">
<h4>작업 대기열 정의</h4>
<p>워크로드 스케줄링을 위한 작업 대기열 및 우선순위 구성</p>
</div>
</div>

<div className="step-card">
<div className="step-number">3</div>
<div className="step-content">
<h4>배치 작업 제출</h4>
<p>배치 처리 작업 배포 및 모니터링</p>
</div>
</div>

<div className="step-card">
<div className="step-number">4</div>
<div className="step-content">
<h4>비용 최적화</h4>
<p>비용 효율성을 위한 스팟 인스턴스 및 자동 확장 사용</p>
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
<p className="showcase-description">컴퓨팅 환경 및 작업 대기열이 포함된 AWS Batch on EKS 전체 인프라 배포 가이드</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">인프라</span>
<span className="tag guide">가이드</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/blueprints/job-schedulers/aws-batch" className="showcase-link">
<span>인프라 배포</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">⚡</div>
<div className="showcase-content">
<h3>스팟 인스턴스 배치 작업</h3>
<p className="showcase-description">자동 장애 조치 및 대기열 관리 기능이 포함된 EC2 스팟 인스턴스를 사용한 비용 최적화 배치 처리</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag optimization">비용</span>
<span className="tag guide">예제</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/blueprints/job-schedulers/aws-batch" className="showcase-link">
<span>자세히 보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

{/* End of showcase grid */}
