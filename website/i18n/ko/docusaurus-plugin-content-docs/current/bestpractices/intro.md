---
title: 모범 사례
sidebar_position: 1
sidebar_label: 개요
---

import '@site/src/css/datastack-tiles.css';
import '@site/src/css/getting-started.css';
import BestPracticesHero from '@site/src/components/BestPractices/BestPracticesHero';
import { Shield, Layers, TrendingUp, Database, Zap, Lock } from 'lucide-react';

<BestPracticesHero />

## 개요

AWS 고객과의 협력을 통해 EKS에서 데이터 및 ML 워크로드를 실행하기 위한 프로덕션에서 검증된 모범 사례를 파악했습니다. 이 권장 사항은 실제 배포 및 고객 피드백을 기반으로 지속적으로 업데이트됩니다.

이 Data on EKS 모범 사례는 데이터 중심 사용 사례(배치 처리, 스트림 처리, 머신 러닝)를 위한 [EKS 모범 사례 가이드](https://aws.github.io/aws-eks-best-practices/)를 확장합니다. 이 권장 사항을 살펴보기 전에 EKS 모범 사례를 먼저 검토하는 것을 권장합니다.

## 모범 사례 카테고리

<div className="datastacks-grid">

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Layers size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>클러스터 아키텍처</h3>
<p className="datastack-description">동적 및 정적 클러스터, 스케일링 전략, 리소스 관리를 위한 설계 패턴.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">동적 클러스터</span>
<span className="feature-tag">정적 클러스터</span>
<span className="feature-tag">고빈도 변동</span>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <TrendingUp size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>성능 최적화</h3>
<p className="datastack-description">Spark, Karpenter 오토스케일링, 리소스 할당 패턴을 위한 튜닝 전략.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Spark 튜닝</span>
<span className="feature-tag">오토스케일링</span>
<span className="feature-tag">비용 최적화</span>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Database size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>데이터 스토리지</h3>
<p className="datastack-description">S3, EBS, EFS 및 임시 스토리지 최적화를 위한 스토리지 전략.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">S3 통합</span>
<span className="feature-tag">EBS 볼륨</span>
<span className="feature-tag">셔플 데이터</span>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Lock size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>보안 및 컴플라이언스</h3>
<p className="datastack-description">IRSA, 네트워크 정책, 저장 데이터 암호화 및 보안 강화.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">IRSA</span>
<span className="feature-tag">네트워크 정책</span>
<span className="feature-tag">암호화</span>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Zap size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>관측성(Observability)</h3>
<p className="datastack-description">데이터 워크로드를 위한 모니터링, 로깅 및 알림 전략.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">Prometheus</span>
<span className="feature-tag">CloudWatch</span>
<span className="feature-tag">대시보드</span>
</div>
</div>

<div className="datastack-card">
<div className="datastack-header">
<div className="datastack-icon">
  <Shield size={32} strokeWidth={2} />
</div>
<div className="datastack-content">
<h3>프로덕션 준비</h3>
<p className="datastack-description">고가용성, 재해 복구 및 운영 우수성.</p>
</div>
</div>
<div className="datastack-features">
<span className="feature-tag">HA 설정</span>
<span className="feature-tag">백업/복원</span>
<span className="feature-tag">GitOps</span>
</div>
</div>

</div>

## 클러스터 설계 패턴

이 권장 사항은 두 가지 클러스터 설계 중 하나를 사용하는 고객과의 협력을 통해 구축되었습니다:

* **동적 클러스터(Dynamic Clusters)** - 높은 "변동(churn)" 비율로 스케일링됩니다. 짧은 기간 동안 생성되는 Pod로 배치 처리(Spark)를 실행합니다. 이러한 클러스터는 높은 비율로 리소스(Pod, 노드)를 생성/삭제하여 Kubernetes 구성 요소에 고유한 부담을 줍니다.

* **정적 클러스터(Static Clusters)** - 크지만 안정적인 스케일링 동작을 보입니다. 더 오래 실행되는 작업(스트리밍, 학습)을 실행합니다. 중단을 피하는 것이 중요하며, 신중한 변경 관리가 필요합니다.

### 스케일 고려 사항

대규모 클러스터는 일반적으로 500개 이상의 노드와 5000개 이상의 Pod를 보유하거나, 분당 수백 개의 리소스를 생성/삭제합니다. 그러나 스케일링 제약 조건은 [Kubernetes 스케일링 복잡성](https://github.com/kubernetes/community/blob/master/sig-scalability/configs-and-limits/thresholds.md)으로 인해 워크로드마다 다릅니다.

:::info 곧 제공 예정
상세한 모범 사례 가이드가 개발 중입니다. 클러스터 구성, 리소스 관리, 보안, 모니터링 및 최적화 전략에 대한 업데이트를 확인하세요.
:::
