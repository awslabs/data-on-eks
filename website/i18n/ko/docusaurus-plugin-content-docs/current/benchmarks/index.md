---
title: 벤치마크
sidebar_position: 1
sidebar_label: 개요
---

import '@site/src/css/datastack-tiles.css';
import '@site/src/css/getting-started.css';
import BenchmarksHero from '@site/src/components/Benchmarks/BenchmarksHero';
import { Settings, BarChart3, Cpu, Zap } from 'lucide-react';

<BenchmarksHero />

## 벤치마크 결과 및 설정

<div className="datastacks-grid">

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Settings size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>벤치마크 설정</h3>
<p className="datastack-description">TPC-DS 벤치마크 인프라 설정, 데이터 생성 및 테스트 실행을 위한 완벽한 가이드입니다.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">데이터 생성</span>
<span className="feature-tag">테스트 구성</span>
<span className="feature-tag">인프라 설정</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/benchmarks/spark-operator-benchmark/data-generation" className="datastack-link">
<span>설정 가이드</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <BarChart3 size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>EMR on EKS TPC-DS</h3>
<p className="datastack-description">다양한 구성에서 EMR on EKS 성능을 비교하는 포괄적인 TPC-DS 3TB 벤치마크입니다.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">TPC-DS 3TB</span>
<span className="feature-tag">EMR on EKS</span>
<span className="feature-tag">비용 분석</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/benchmarks/emr-on-eks" className="datastack-link">
<span>결과 보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Cpu size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>Spark Graviton R 시리즈</h3>
<p className="datastack-description">Spark 워크로드에서 ARM 기반 Graviton 프로세서와 x86 인스턴스를 비교하는 성능 벤치마크입니다.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Graviton3</span>
<span className="feature-tag">R7g vs R6i</span>
<span className="feature-tag">비용/성능</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/benchmarks/spark-operator-benchmark/graviton-r-data" className="datastack-link">
<span>결과 보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Zap size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>Spark Gluten + Velox</h3>
<p className="datastack-description">EKS에서 Spark를 위한 Gluten 및 Velox 벡터화 실행 엔진을 사용한 가속 벤치마크입니다.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">벡터화 실행</span>
<span className="feature-tag">네이티브 엔진</span>
<span className="feature-tag">2-3배 속도 향상</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/benchmarks/spark-gluten-velox-benchmark" className="datastack-link">
<span>결과 보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

## TPC-DS 벤치마크 소개

**TPC-DS**(Transaction Processing Performance Council - Decision Support)는 의사 결정 지원 시스템의 성능을 평가하기 위한 업계 표준 벤치마크입니다. 저희 벤치마크에서는 다음을 사용합니다:

- **데이터셋 크기**: 1TB 및 3TB 규모
- **쿼리 스위트**: 복잡한 분석 패턴을 다루는 99개의 쿼리
- **측정 지표**: 쿼리 실행 시간, 쿼리당 비용, 리소스 활용도
- **인프라**: Karpenter 오토스케일링, Spot 인스턴스를 활용한 Amazon EKS

모든 벤치마크는 제공된 설정 가이드를 사용하여 재현할 수 있습니다. 결과에는 상세한 방법론, 인프라 구성 및 비용 분석이 포함되어 있습니다.
