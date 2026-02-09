---
title: ClickHouse on EKS
sidebar_position: 0
---

import '@site/src/css/datastack-tiles.css';

# ClickHouse on EKS 스택
[ClickHouse](https://clickhouse.com/)는 Apache 2.0 라이선스 하에 오픈소스로 제공되는 온라인 분석 처리(OLAP)를 위한 고성능 컬럼 지향 SQL 데이터베이스 관리 시스템(DBMS)입니다.


OLAP는 다양한 관점에서 비즈니스 데이터를 분석하는 데 사용할 수 있는 소프트웨어 기술입니다. 조직은 웹사이트, 애플리케이션, 스마트 미터 및 내부 시스템과 같은 여러 데이터 소스에서 데이터를 수집하고 저장합니다. OLAP는 조직이 전략적 계획을 위한 실행 가능한 인사이트를 제공하기 위해 이 데이터를 결합하고 카테고리로 그룹화하여 증가하는 정보량을 처리하고 활용하는 데 도움이 됩니다. 예를 들어, 소매업체는 색상, 크기, 비용 및 위치와 같이 판매하는 모든 제품에 대한 데이터를 저장합니다. 소매업체는 또한 주문한 상품 이름 및 총 판매 가치와 같은 고객 구매 데이터를 다른 시스템에 수집합니다. OLAP는 데이터셋을 결합하여 어떤 색상의 제품이 더 인기가 있는지 또는 제품 배치가 판매에 어떤 영향을 미치는지와 같은 질문에 답변합니다.

**ClickHouse의 주요 이점:**

* 실시간 분석: ClickHouse는 실시간 데이터 수집 및 분석을 처리할 수 있어 모니터링, 로깅 및 이벤트 데이터 처리와 같은 사용 사례에 적합합니다.
* 고성능: ClickHouse는 분석 워크로드에 최적화되어 빠른 쿼리 실행과 높은 처리량을 제공합니다.
* 확장성: ClickHouse는 여러 노드에서 수평 확장되도록 설계되어 사용자가 분산 클러스터 전체에서 페타바이트 규모의 데이터를 저장하고 처리할 수 있습니다. 고가용성 및 내결함성을 위한 샤딩 및 복제를 지원합니다.
* 컬럼 지향 스토리지: ClickHouse는 행이 아닌 열로 데이터를 구성하여 효율적인 압축과 더 빠른 쿼리 처리를 가능하게 하며, 특히 대규모 데이터셋의 집계 및 스캔을 포함하는 쿼리에 효과적입니다.
* SQL 지원: ClickHouse는 SQL의 하위 집합을 지원하여 SQL 기반 데이터베이스에 이미 익숙한 개발자와 분석가에게 친숙하고 사용하기 쉽습니다.
* 통합 데이터 형식: ClickHouse는 CSV, JSON, Apache Avro 및 Apache Parquet를 포함한 다양한 데이터 형식을 지원하여 다양한 유형의 데이터를 유연하게 수집하고 쿼리할 수 있습니다.



Amazon EKS 기반 프로덕션 준비 완료 ClickHouse OLAP 데이터베이스. 컬럼형 스토리지를 갖춘 고성능 분석 데이터베이스를 배포하세요.

<div style={{
  background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
  color: 'white',
  padding: '30px',
  borderRadius: '12px',
  textAlign: 'center',
  margin: '30px 0',
  boxShadow: '0 4px 6px rgba(0,0,0,0.1)'
}}>
  <h2 style={{margin: '0 0 10px 0'}}>🚧 Coming Soon</h2>
  <p style={{margin: 0, opacity: 0.9}}>이 데이터 스택은 현재 개발 중입니다. 배포 가이드와 예제를 곧 확인하세요!</p>
</div>

<!-- <div className="getting-started-header">

## Getting Started

<div className="steps-grid">

<div className="step-card">
<div className="step-number">1</div>
<div className="step-number">1</div>
<div className="step-content">
<h4>Deploy Infrastructure</h4>
<p>Set up ClickHouse operator with distributed clusters</p>
</div>
</div>

<div className="step-card">
<div className="step-number">2</div>
<div className="step-content">
<h4>Create Tables</h4>
<p>Define schemas with MergeTree engines and partitioning</p>
</div>
</div>

<div className="step-card">
<div className="step-number">3</div>
<div className="step-content">
<h4>Ingest Data</h4>
<p>Stream data from Kafka or batch load from S3</p>
</div>
</div>

<div className="step-card">
<div className="step-number">4</div>
<div className="step-content">
<h4>Query Analytics</h4>
<p>Run blazing-fast SQL queries on billions of rows</p>
</div>
</div>

</div>

</div>

<div className="showcase-grid">

<div className="showcase-card featured">
<div className="showcase-header">
<div className="showcase-icon">🏗️</div>
<div className="showcase-content">
<h3>Infrastructure Deployment</h3>
<p className="showcase-description">Complete infrastructure deployment guide for ClickHouse on EKS with distributed cluster setup</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">Infrastructure</span>
<span className="tag guide">Guide</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/clickhouse-on-eks/infra" className="showcase-link">
<span>Deploy Infrastructure</span>
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
<h3>S3 Data Lake Analytics</h3>
<p className="showcase-description">Query S3 data lakes directly with ClickHouse S3 table functions for serverless analytics</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag storage">Data Lake</span>
<span className="tag guide">Example</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/clickhouse-on-eks/s3-analytics" className="showcase-link">
<span>Learn More</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div> -->
