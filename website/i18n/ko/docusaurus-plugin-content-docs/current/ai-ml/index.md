---
title: 데이터를 위한 AI
sidebar_position: 1
sidebar_label: 개요
---

import '@site/src/css/datastack-tiles.css';
import '@site/src/css/getting-started.css';
import AIforDataHero from '@site/src/components/AIforData/AIforDataHero';
import { Database, Cpu } from 'lucide-react';

<AIforDataHero />

## AI 네이티브 데이터 인프라

AI 기능으로 데이터 플랫폼을 혁신하세요. 시맨틱 검색을 위한 벡터 데이터베이스부터 Spark 작업을 자동으로 진단하는 지능형 에이전트까지, 이러한 스택은 Amazon EKS의 데이터 운영에 최첨단 AI를 제공합니다.

<div className="datastacks-grid">

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Database size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>벡터 데이터베이스</h3>
<p className="datastack-description">AI 애플리케이션, 임베딩 및 시맨틱 데이터 검색을 위한 고성능 벡터 스토리지 및 유사성 검색.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Milvus on EKS</span>
<span className="feature-tag">pgvector</span>
<span className="feature-tag">Weaviate</span>
<span className="feature-tag">시맨틱 검색</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/ai-ml/vector-databases" className="datastack-link">
<span>벡터 DB 탐색</span>
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
<h3>데이터용 AI 에이전트</h3>
<p className="datastack-description">AI를 사용하여 데이터 워크로드를 자동으로 모니터링, 진단 및 최적화하는 지능형 에이전트.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Spark 진단</span>
<span className="feature-tag">자동 최적화</span>
<span className="feature-tag">이상 탐지</span>
<span className="feature-tag">LangGraph</span>
</div>
<div className="datastack-footer">
<a href="/data-on-eks/docs/ai-ml/ai-agents" className="datastack-link">
<span>AI 에이전트 탐색</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

## EKS에서 데이터를 위한 AI를 사용해야 하는 이유

AI와 데이터 인프라의 융합은 지능형 시스템의 새로운 가능성을 열어줍니다. Amazon EKS에서 벡터 데이터베이스와 AI 에이전트를 실행하면 다음을 얻을 수 있습니다:

### 대규모 인텔리전스
기존 데이터 스택과 함께 Milvus와 같은 벡터 데이터베이스를 배포하여 수십억 개의 임베딩에 대해 밀리초 미만의 지연 시간으로 시맨틱 검색을 가능하게 합니다.

### 자동화된 운영
AI 에이전트가 Spark 작업, Kafka 스트림 및 Airflow DAG를 모니터링하여 이상을 자동으로 감지하고, 구성을 최적화하며, 장애가 발생하기 전에 예방합니다.

### 비용 최적화
머신 러닝 모델이 리소스 사용 패턴을 분석하고 최적의 구성을 권장하여 성능을 개선하면서 클라우드 비용을 절감합니다.

### 통합 플랫폼
Kubernetes에서 모든 것을 실행합니다: 데이터 처리(Spark), 스트리밍(Kafka), 오케스트레이션(Airflow), 그리고 이제 AI 에이전트까지 - 모두 ArgoCD를 사용한 GitOps로 관리됩니다.

## 사용 사례

### 데이터 검색을 위한 시맨틱 검색
사용자가 "고객 결제 데이터가 포함된 모든 테이블 찾기"와 같은 자연어 질문을 하고 벡터 유사성을 사용하여 AI 기반 결과를 얻을 수 있는 데이터 카탈로그를 구축합니다.

### Spark 작업 자동 진단
모든 Spark 작업을 감시하고, 일반적인 실패 패턴(OOM 오류, 데이터 스큐, 셔플 문제)을 감지하며, 자동으로 수정 사항을 제안하거나 JIRA 티켓을 생성하는 AI 에이전트를 배포합니다.

### 실시간 데이터 품질
AI 에이전트가 스트리밍 데이터를 지속적으로 검증하고, 스키마 드리프트를 감지하며, PII 유출을 식별하고, 자동화된 수정 워크플로를 트리거합니다.

### 지능형 비용 관리
ML 모델이 리소스 사용량을 예측하고, 스팟 vs 온디맨드 인스턴스 조합을 권장하며, 워크로드 패턴에 따라 클러스터를 자동으로 스케일링합니다.

## 기술 스택

데이터를 위한 AI 스택은 다음을 기반으로 구축됩니다:

- **벡터 데이터베이스**: 임베딩 스토리지를 위한 Milvus, Weaviate, pgvector
- **AI 프레임워크**: 에이전트 오케스트레이션을 위한 LangChain, LangGraph
- **컴퓨팅**: GPU/CPU 오토스케일링을 위한 Karpenter가 있는 Amazon EKS
- **스토리지**: 데이터 레이크용 Amazon S3, 벡터 인덱스용 EBS/EFS
- **관측성(Observability)**: 에이전트 모니터링을 위한 Prometheus, Grafana
- **GitOps**: 선언적 AI 인프라를 위한 ArgoCD

:::tip 곧 제공 예정
다음에 대한 프로덕션 준비 예제를 적극적으로 개발 중입니다:
- **Milvus on EKS** - 분산 벡터 데이터베이스 배포
- **pgvector on EKS** - 벡터 유사성 검색이 있는 PostgreSQL
- **Spark 진단 에이전트** - LangGraph를 사용한 AI 기반 Spark 작업 분석기
- **성능 최적화 에이전트** - 자동화된 쿼리 및 구성 튜닝
:::

## 시작하기

1. **벡터 데이터베이스 탐색** - 시맨틱 검색 기능을 위해 Milvus 또는 pgvector로 시작
2. **AI 에이전트 배포** - 기존 작업을 분석하고 구성을 자동으로 최적화하는 Spark 진단 에이전트 사용해 보기

---

*질문이나 기여는 [GitHub 저장소](https://github.com/awslabs/data-on-eks)를 방문하거나 커뮤니티 토론에 참여하세요.*
