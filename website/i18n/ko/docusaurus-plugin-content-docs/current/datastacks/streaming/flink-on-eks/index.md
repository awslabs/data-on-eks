---
title: Flink on EKS
sidebar_position: 1
---

import '@site/src/css/datastack-tiles.css';

{/*
  Flink Examples Tiles Documentation:

  🎯 To add a new Flink example tile:
  1. Copy the showcase-card template below and modify the content
  2. Update icon (emoji), title, description, tags, and link
  3. Use tag classes for specific colors: infrastructure, storage, performance, optimization, guide
  4. No CSS knowledge required!

  📚 Full documentation: /src/components/DatastackTileExamples.md
  🌟 Featured tiles: Add "featured" class to highlight special examples
*/}

# Flink on EKS 스택

Amazon EKS를 위한 프로덕션 준비 완료 Apache Flink 스트리밍 예제 및 구성. 인프라 배포 및 스트리밍 사용 사례 중에서 선택하세요.

<div className="getting-started-header">

## 시작하기

<div className="steps-grid">

<div className="step-card">
<div className="step-number">1</div>
<div className="step-content">
<h4>인프라 배포</h4>
<p>Flink 스트리밍 기반을 설정하기 위한 인프라 배포 가이드로 시작하세요</p>
</div>
</div>

<div className="step-card">
<div className="step-number">2</div>
<div className="step-content">
<h4>사용 사례 선택</h4>
<p>실시간 처리 요구 사항에 맞는 스트리밍 예제를 선택하세요</p>
</div>
</div>

<div className="step-card">
<div className="step-number">3</div>
<div className="step-content">
<h4>지침 따르기</h4>
<p>각 예제는 단계별 배포 및 스트리밍 구성 가이드를 제공합니다</p>
</div>
</div>

<div className="step-card">
<div className="step-number">4</div>
<div className="step-content">
<h4>커스터마이징</h4>
<p>특정 스트리밍 워크로드 및 성능 요구 사항에 맞게 구성을 조정하세요</p>
</div>
</div>

</div>

</div>

<div className="showcase-grid">

{/*
  📋 TEMPLATE: Copy this structure to add a new Flink example tile

  <div className="showcase-card">
  <div className="showcase-header">
  <div className="showcase-icon">🎯</div>
  <div className="showcase-content">
  <h3>Example Title</h3>
  <p className="showcase-description">Detailed description of this example or use case.</p>
  </div>
  </div>
  <div className="showcase-tags">
  <span className="tag infrastructure">Infrastructure</span>
  <span className="tag storage">Storage</span>
  <span className="tag performance">Performance</span>
  </div>
  <div className="showcase-footer">
  <a href="/data-on-eks/docs/datastacks/streaming/flink-on-eks/example/" className="showcase-link">
  <span>Learn More</span>
  <svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
  <path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
  </svg>
  </a>
  </div>
  </div>

  💡 For featured tiles, add "featured" class: <div className="showcase-card featured">
*/}

<div className="showcase-card featured">
<div className="showcase-header">
<div className="showcase-icon">🏗️</div>
<div className="showcase-content">
<h3>인프라 배포</h3>
<p className="showcase-description">EKS에서 Flink 스트리밍을 위한 구성 옵션 및 커스터마이징을 포함한 완전한 인프라 배포 가이드</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">Infrastructure</span>
<span className="tag guide">Guide</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/streaming/flink-on-eks/infra" className="showcase-link">
<span>인프라 배포</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">🌊</div>
<div className="showcase-content">
<h3>실시간 WordCount 스트리밍</h3>
<p className="showcase-description">Apache Flink 연산자를 사용한 Kafka 소스와 실시간 단어 수 집계의 클래식 스트리밍 예제</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag performance">Streaming</span>
<span className="tag optimization">Real-time</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/streaming/flink-on-eks/wordcount-streaming" className="showcase-link">
<span>자세히 보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

{/* End of showcase grid - All styles are now in /src/css/datastack-tiles.css */}
