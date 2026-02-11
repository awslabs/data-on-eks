---
title: Amazon EMR on EKS
sidebar_position: 0
---

import '@site/src/css/datastack-tiles.css';

# EMR on EKS 스택

Amazon EKS에서 관리형 EMR 기능과 함께 Apache Spark 워크로드를 실행하기 위한 프로덕션 준비 Amazon EMR on EKS 예제 및 구성입니다. 인프라 배포와 스토리지 최적화 사용 사례 중에서 선택하세요.

<div className="getting-started-header">

## 시작하기

<div className="steps-grid">

<div className="step-card">
<div className="step-number">1</div>
<div className="step-content">
<h4>인프라 배포</h4>
<p>인프라 배포 가이드로 시작하여 EMR on EKS 기반 설정</p>
</div>
</div>

<div className="step-card">
<div className="step-number">2</div>
<div className="step-content">
<h4>스토리지 전략 선택</h4>
<p>성능 및 비용 요구 사항에 맞는 스토리지 예제 선택</p>
</div>
</div>

<div className="step-card">
<div className="step-number">3</div>
<div className="step-content">
<h4>Spark 작업 제출</h4>
<p>EMR 관리형 런타임 및 최적화된 구성으로 Spark 애플리케이션 실행</p>
</div>
</div>

<div className="step-card">
<div className="step-number">4</div>
<div className="step-content">
<h4>모니터링 및 최적화</h4>
<p>관측성 및 성능 튜닝을 위해 EMR Studio, CloudWatch, Spark UI 사용</p>
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
<p className="showcase-description">가상 클러스터 설정, IAM 역할 및 Karpenter 구성이 포함된 EMR on EKS 전체 인프라 배포 가이드</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">인프라</span>
<span className="tag guide">가이드</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/emr-on-eks/infra" className="showcase-link">
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
<h3>EBS Hostpath 스토리지</h3>
<p className="showcase-description">Spark 셔플 데이터를 위한 비용 효율적인 EBS 루트 볼륨 스토리지입니다. 공유 노드 스토리지로 간편한 설정 및 Pod별 PVC 대비 약 70% 비용 절감</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag storage">스토리지</span>
<span className="tag optimization">최적화</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/emr-on-eks/ebs-hostpath" className="showcase-link">
<span>자세히 보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">💿</div>
<div className="showcase-content">
<h3>EBS 동적 PVC 스토리지</h3>
<p className="showcase-description">Spark 셔플 스토리지를 위한 자동 볼륨 프로비저닝이 포함된 프로덕션 준비 EBS 동적 PVC입니다. gp3 볼륨으로 Executor별 격리된 스토리지</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag storage">스토리지</span>
<span className="tag performance">성능</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/emr-on-eks/ebs-pvc" className="showcase-link">
<span>자세히 보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card featured">
<div className="showcase-header">
<div className="showcase-icon">⚡</div>
<div className="showcase-content">
<h3>NVMe SSD 스토리지</h3>
<p className="showcase-description">NVMe 인스턴스 스토어 SSD를 사용한 최대 I/O 성능입니다. 초고속 셔플 작업을 위해 Graviton 인스턴스의 로컬 NVMe 드라이브 활용</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag storage">스토리지</span>
<span className="tag performance">성능</span>
<span className="tag optimization">최적화</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/emr-on-eks/nvme-ssd" className="showcase-link">
<span>자세히 보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">🎯</div>
<div className="showcase-content">
<h3>EMR Spark Operator</h3>
<p className="showcase-description">Kubernetes 네이티브 EMR Spark Operator를 사용한 선언적 Spark 작업 관리입니다. 간소화된 워크플로를 위한 SparkApplication CRD로 GitOps 준비 완료</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag guide">가이드</span>
<span className="tag infrastructure">인프라</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/emr-on-eks/emr-spark-operator" className="showcase-link">
<span>자세히 보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

{/* End of showcase grid */}
