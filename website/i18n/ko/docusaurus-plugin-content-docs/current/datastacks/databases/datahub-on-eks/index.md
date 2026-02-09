---
title: DataHub on EKS
sidebar_position: 3
---

import '@site/src/css/datastack-tiles.css';

{/*
  DataHub Examples Tiles Documentation:

  🎯 To add a new DataHub example tile:
  1. Copy the showcase-card template below and modify the content
  2. Update icon (emoji), title, description, tags, and link
  3. Use tag classes for specific colors: infrastructure, storage, performance, optimization, guide
  4. No CSS knowledge required!

  📚 Full documentation: /src/components/DatastackTileExamples.md
  🌟 Featured tiles: Add "featured" class to highlight special examples
*/}

# DataHub on EKS 스택

Amazon EKS를 위한 프로덕션 준비 완료 DataHub 메타데이터 관리 및 데이터 거버넌스 예제. 엔터프라이즈 데이터 카탈로그 및 계보(lineage) 추적 솔루션.

<div className="getting-started-header">

## 시작하기

<div className="steps-grid">

<div className="step-card">
<div className="step-number">1</div>
<div className="step-content">
<h4>인프라 배포</h4>
<p>DataHub 메타데이터 기반을 설정하기 위한 인프라 배포 가이드로 시작하세요</p>
</div>
</div>

<div className="step-card">
<div className="step-number">2</div>
<div className="step-content">
<h4>사용 사례 선택</h4>
<p>엔터프라이즈 메타데이터 요구 사항에 맞는 데이터 거버넌스 예제를 선택하세요</p>
</div>
</div>

<div className="step-card">
<div className="step-number">3</div>
<div className="step-content">
<h4>지침 따르기</h4>
<p>각 예제는 단계별 배포 및 데이터 카탈로그 구성 가이드를 제공합니다</p>
</div>
</div>

<div className="step-card">
<div className="step-number">4</div>
<div className="step-content">
<h4>커스터마이징</h4>
<p>특정 데이터 거버넌스 및 컴플라이언스 요구 사항에 맞게 구성을 조정하세요</p>
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
<p className="showcase-description">Terraform, 노드 자동 스케일링을 위한 Karpenter, GitOps 관리를 위한 ArgoCD를 사용하여 Amazon EKS에 확장 가능한 DataHub 플랫폼을 배포하세요.</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">Infrastructure</span>
<span className="tag">EKS</span>
<span className="tag">Terraform</span>
<span className="tag">ArgoCD</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/databases/datahub-on-eks/infra" className="showcase-link">
<span>가이드 보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">🔂</div>
<div className="showcase-content">
<h3>CLI 메타데이터 수집</h3>
<p className="showcase-description">DataHub CLI를 사용하여 DataHub 인스턴스에 샘플 메타데이터를 수집하고 UI에서 결과를 확인하는 방법을 알아보세요.</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag guide">Guide</span>
<span className="tag">CLI</span>
<span className="tag">Ingestion</span>
<span className="tag">Metadata</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/databases/datahub-on-eks/cli-ingestion" className="showcase-link">
<span>가이드 보기</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

{/* End of showcase grid - All styles are now in /src/css/datastack-tiles.css */}
