---
title: Spark on EKS
sidebar_position: 0
---

import '@site/src/css/datastack-tiles.css';

{/*
  Spark 예제 타일 문서:

  🎯 새 Spark 예제 타일을 추가하려면:
  1. 아래 showcase-card 템플릿을 복사하고 내용 수정
  2. 아이콘(이모지), 제목, 설명, 태그, 링크 업데이트
  3. 특정 색상에 태그 클래스 사용: infrastructure, storage, performance, optimization, guide
  4. CSS 지식 불필요!

  📚 전체 문서: /src/components/DatastackTileExamples.md
  🌟 추천 타일: 특별한 예제를 강조하려면 "featured" 클래스 추가
*/}

# Spark on EKS 스택

Amazon EKS를 위한 프로덕션 준비 Apache Spark 예제 및 구성입니다. 인프라 배포와 고급 사용 사례 중에서 선택하세요.

<div className="getting-started-header">

## 시작하기

<div className="steps-grid">

<div className="step-card">
<div className="step-number">1</div>
<div className="step-content">
<h4>인프라 배포</h4>
<p>인프라 배포 가이드로 시작하여 Spark on EKS 기반 설정</p>
</div>
</div>

<div className="step-card">
<div className="step-number">2</div>
<div className="step-content">
<h4>사용 사례 선택</h4>
<p>스토리지 및 성능 요구 사항에 맞는 예제 선택</p>
</div>
</div>

<div className="step-card">
<div className="step-number">3</div>
<div className="step-content">
<h4>지침 따르기</h4>
<p>각 예제는 단계별 배포 및 검증 가이드 제공</p>
</div>
</div>

<div className="step-card">
<div className="step-number">4</div>
<div className="step-content">
<h4>커스터마이징</h4>
<p>특정 워크로드 및 성능 요구 사항에 맞게 구성 조정</p>
</div>
</div>

</div>

</div>

<div className="showcase-grid">

{/*
  📋 템플릿: 새 Spark 예제 타일을 추가하려면 이 구조 복사

  <div className="showcase-card">
  <div className="showcase-header">
  <div className="showcase-icon">🎯</div>
  <div className="showcase-content">
  <h3>예제 제목</h3>
  <p className="showcase-description">이 예제 또는 사용 사례에 대한 자세한 설명.</p>
  </div>
  </div>
  <div className="showcase-tags">
  <span className="tag infrastructure">인프라</span>
  <span className="tag storage">스토리지</span>
  <span className="tag performance">성능</span>
  </div>
  <div className="showcase-footer">
  <a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/example/" className="showcase-link">
  <span>자세히 보기</span>
  <svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
  <path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
  </svg>
  </a>
  </div>
  </div>

  💡 추천 타일의 경우 "featured" 클래스 추가: <div className="showcase-card featured">
*/}

<div className="showcase-card featured">
<div className="showcase-header">
<div className="showcase-icon">🏗️</div>
<div className="showcase-content">
<h3>인프라 배포</h3>
<p className="showcase-description">Spark on EKS를 위한 구성 옵션 및 커스터마이징이 포함된 전체 인프라 배포 가이드</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">인프라</span>
<span className="tag guide">가이드</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/infra" className="showcase-link">
<span>인프라 배포</span>
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
<p className="showcase-description">Spark 셔플 스토리지를 위한 장애 허용, PVC 재사용, 자동 볼륨 프로비저닝이 포함된 프로덕션 준비 EBS 동적 PVC</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag storage">스토리지</span>
<span className="tag performance">성능</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/ebs-pvc-storage" className="showcase-link">
<span>자세히 보기</span>
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
<h3>EBS 노드 스토리지</h3>
<p className="showcase-description">Spark 셔플 스토리지를 위한 비용 효율적인 노드당 공유 EBS 볼륨. Pod별 PVC 대비 약 70% 비용 절감, 노이지 네이버 트레이드오프 가능성</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag storage">스토리지</span>
<span className="tag optimization">최적화</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/ebs-node-storage" className="showcase-link">
<span>자세히 보기</span>
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
<h3>NVMe 인스턴스 스토리지</h3>
<p className="showcase-description">최대 I/O 성능 및 로컬 데이터 처리를 통한 비용 최적화를 위해 인스턴스 스토어 NVMe SSD 활용</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag storage">스토리지</span>
<span className="tag performance">성능</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/nvme-storage" className="showcase-link">
<span>자세히 보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card featured">
<div className="showcase-header">
<div className="showcase-icon">🚀</div>
<div className="showcase-content">
<h3>Graviton NVMe 스토리지</h3>
<p className="showcase-description">우수한 가격 대비 성능을 위한 NVMe SSD가 포함된 ARM64 Graviton 프로세서. 최대 I/O 성능으로 최대 40% 비용 절감</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag storage">스토리지</span>
<span className="tag performance">성능</span>
<span className="tag optimization">최적화</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/nvme-storage-graviton" className="showcase-link">
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
<h3>YuniKorn Gang 스케줄링</h3>
<p className="showcase-description">Apache YuniKorn gang 스케줄링은 Spark 작업에 대한 원자적 리소스 할당을 보장합니다. 리소스 파편화 방지 및 데드락 제거</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag performance">성능</span>
<span className="tag optimization">최적화</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/yunikorn-gang-scheduling" className="showcase-link">
<span>자세히 보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">🗄️</div>
<div className="showcase-content">
<h3>Mountpoint for Amazon S3</h3>
<p className="showcase-description">네이티브 POSIX 작업이 포함된 S3용 고성능 파일 인터페이스. 대규모 데이터 처리 워크로드에 최적화</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag storage">스토리지</span>
<span className="tag performance">성능</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/mountpoint-s3" className="showcase-link">
<span>자세히 보기</span>
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
<h3>S3 Express One Zone</h3>
<p className="showcase-description">밀리초 단위 지연 시간의 초고속 S3 스토리지 클래스. 고성능 분석 워크로드를 위해 설계</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag storage">스토리지</span>
<span className="tag performance">성능</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/mountpoint-s3express" className="showcase-link">
<span>자세히 보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card featured">
<div className="showcase-header">
<div className="showcase-icon">📊</div>
<div className="showcase-content">
<h3>Iceberg를 사용한 S3 Tables</h3>
<p className="showcase-description">Spark와 S3 Tables의 단계별 배포. ACID 트랜잭션, 타임 트래블, 스키마 진화 및 JupyterHub 통합 포함</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag storage">스토리지</span>
<span className="tag guide">가이드</span>
<span className="tag optimization">최적화</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/s3tables" className="showcase-link">
<span>자세히 보기</span>
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
<h3>Spark 관측성</h3>
<p className="showcase-description">Prometheus, Grafana, Spark History Server를 사용한 프로덕션 등급 모니터링. 네이티브 PrometheusServlet 메트릭 통합</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">인프라</span>
<span className="tag guide">가이드</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/observability" className="showcase-link">
<span>자세히 보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">🔄</div>
<div className="showcase-content">
<h3>Apache Beam 파이프라인</h3>
<p className="showcase-description">Spark에서 이식 가능한 Apache Beam 파이프라인 실행. 통합 프로그래밍 모델로 배치 및 스트리밍을 위한 한 번 작성, 어디서나 실행</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag performance">성능</span>
<span className="tag guide">가이드</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/beam" className="showcase-link">
<span>자세히 보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">🌐</div>
<div className="showcase-content">
<h3>IPv6 네트워킹</h3>
<p className="showcase-description">현대적인 클라우드 네트워킹을 위해 IPv6 지원 EKS 클러스터에 Spark 배포.</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">인프라</span>
<span className="tag guide">가이드</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/ipv6" className="showcase-link">
<span>자세히 보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

{/* showcase grid 끝 - 모든 스타일은 이제 /src/css/datastack-tiles.css에 있습니다 */}
