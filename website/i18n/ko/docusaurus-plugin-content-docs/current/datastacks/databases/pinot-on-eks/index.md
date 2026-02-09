---
title: Pinot on EKS
sidebar_position: 0
---

import '@site/src/css/datastack-tiles.css';

# Apache Pinot on EKS 스택

Amazon EKS를 위한 프로덕션 준비 완료 Apache Pinot 실시간 OLAP 데이터스토어. 사용자 대면 애플리케이션을 위한 초저지연 분석을 배포하세요.

<div className="getting-started-header">

## 시작하기

<div className="steps-grid">

<div className="step-card">
<div className="step-number">1</div>
<div className="step-content">
<h4>인프라 배포</h4>
<p>EKS에서 컨트롤러, 브로커 및 서버로 Pinot 클러스터 설정</p>
</div>
</div>

<div className="step-card">
<div className="step-number">2</div>
<div className="step-content">
<h4>테이블 생성</h4>
<p>스키마 정의 및 실시간 및 오프라인 테이블 구성</p>
</div>
</div>

<div className="step-card">
<div className="step-number">3</div>
<div className="step-content">
<h4>데이터 수집</h4>
<p>Kafka에서 스트리밍하거나 S3/HDFS에서 배치 로드</p>
</div>
</div>

<div className="step-card">
<div className="step-number">4</div>
<div className="step-content">
<h4>분석 쿼리</h4>
<p>수십억 개의 행에서 밀리초 미만의 SQL 쿼리 실행</p>
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
<p className="showcase-description">분산 아키텍처 설정을 포함한 EKS 기반 Apache Pinot의 완전한 인프라 배포 가이드</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">Infrastructure</span>
<span className="tag guide">Guide</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/databases/pinot-on-eks/infra" className="showcase-link">
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
<h3>실시간 분석 파이프라인</h3>
<p className="showcase-description">Kafka 수집, star-tree 인덱스 및 밀리초 미만 쿼리 성능을 갖춘 실시간 분석 구축</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag performance">Real-time</span>
<span className="tag guide">Example</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/databases/pinot-on-eks/kafka-integration" className="showcase-link">
<span>자세히 보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

{/* End of showcase grid */}
