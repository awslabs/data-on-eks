---
title: 시작하기
sidebar_position: 0
---

import '@site/src/css/getting-started.css';
import HeroSection from '@site/src/components/GettingStarted/HeroSection';
import PrinciplesGrid from '@site/src/components/GettingStarted/PrinciplesGrid';
import ArchitectureDiagram from '@site/src/components/GettingStarted/ArchitectureDiagram';
import DataStacksShowcase from '@site/src/components/GettingStarted/DataStacksShowcase';
import { Cloud, Link2, Code, Sparkles, Globe, Users, Zap, TrendingUp, FlaskConical, Rocket, BookOpen, Bug, MessageCircle, CheckCircle, Play } from 'lucide-react';

<HeroSection />

## Data on EKS란?

**Data on EKS (DoEKS)**는 **Cloud Native Computing Foundation (CNCF)** 프로젝트의 강력함과 **AWS 통합**을 결합하여 Amazon EKS에서 프로덕션 준비 완료 데이터 플랫폼을 제공하는 견고한 인프라 프레임워크입니다.

<div style={{
  display: 'grid',
  gridTemplateColumns: 'repeat(2, 1fr)',
  gap: '1.5rem',
  margin: '2rem 0',
  maxWidth: '1200px'
}}>
  <div className="info-box info-box-success">
    <div className="info-box-title">
      <Cloud size={20} className="inline-block mr-2" /> CNCF 에코시스템
    </div>
    <div>졸업 및 인큐베이팅 CNCF 프로젝트 활용 (Kubernetes, Prometheus, Strimzi, Argo)</div>
  </div>

  <div className="info-box info-box-info">
    <div className="info-box-title">
      <Link2 size={20} className="inline-block mr-2" /> AWS 통합
    </div>
    <div>Amazon EKS, S3, EMR 및 AWS 데이터 서비스와의 심층 통합</div>
  </div>

  <div className="info-box info-box-warning">
    <div className="info-box-title">
      <Code size={20} className="inline-block mr-2" /> Infrastructure as Code
    </div>
    <div>Terraform 기반, ArgoCD를 통한 GitOps 준비 완료 배포</div>
  </div>

  <div className="info-box info-box-success">
    <div className="info-box-title">
      <Sparkles size={20} className="inline-block mr-2" /> 프로덕션 패턴
    </div>
    <div>실제 AWS 고객 워크로드에서 검증된 구성</div>
  </div>
</div>

<PrinciplesGrid />

<ArchitectureDiagram />

<DataStacksShowcase />

## 빠른 시작: 15분 안에 배포 {#quick-start}

<div className="quick-start-timeline">

<div className="timeline-step">
<div className="timeline-number">1</div>
<div className="timeline-content">

### 사전 요구 사항

**필수 도구:**
```bash
# 설치 확인
aws --version          # AWS CLI v2.x
terraform --version    # Terraform >= 1.0
kubectl version        # kubectl >= 1.28
helm version           # Helm >= 3.0
```

**AWS 설정:**
- IAM 권한: VPC/EKS/IAM 생성을 위한 `AdministratorAccess` 또는 커스텀 정책
- 구성된 AWS 프로필: `aws configure` 또는 `AWS_PROFILE` 환경 변수
- 기본 리전 설정 (권장: `us-west-2`, `us-east-1`, `eu-west-1`)

</div>
</div>

<div className="timeline-step">
<div className="timeline-number">2</div>
<div className="timeline-content">

### 데이터 스택 선택

| 필요 | 권장 스택 |
|------|-------------------|
| 배치 ETL / 데이터 처리 | [Spark on EKS](/data-on-eks/docs/datastacks/processing/spark-on-eks/) |
| 실시간 이벤트 스트리밍 | [Kafka on EKS](/data-on-eks/docs/datastacks/streaming/kafka-on-eks/) |
| 워크플로우 오케스트레이션 | [Airflow on EKS](/data-on-eks/docs/datastacks/orchestration/airflow-on-eks/) |
| AWS 관리형 Spark | [EMR on EKS](/data-on-eks/docs/datastacks/processing/emr-on-eks/) |
| 벡터 데이터베이스 및 AI 에이전트 | [AI for Data](/data-on-eks/docs/ai-ml/) |

</div>
</div>

<div className="timeline-step">
<div className="timeline-number">3</div>
<div className="timeline-content">

### 복제 및 구성

```bash
# 저장소 복제
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/data-stacks/spark-on-eks

# 구성 검토
cat terraform/data-stack.tfvars
```

**주요 구성 옵션:**
```hcl
# terraform/data-stack.tfvars

# 필수
region = "us-west-2"              # AWS 리전
name   = "spark-on-eks"           # 클러스터 이름 (고유해야 함)

# 코어 애드온 (모든 스택에 권장)
enable_karpenter                   = true   # 노드 자동 확장
enable_aws_load_balancer_controller = true   # ALB/NLB 지원
enable_kube_prometheus_stack       = true   # 모니터링

# Spark 전용 애드온
enable_spark_operator              = true   # Spark Operator (Kubeflow)
enable_spark_history_server        = true   # Spark UI 지속성
enable_yunikorn                    = true   # 고급 스케줄링
```

</div>
</div>

<div className="timeline-step">
<div className="timeline-number">4</div>
<div className="timeline-content">

### 인프라 배포

```bash
# 자동화된 배포 (사전 요구 사항 검증)
./deploy.sh

# 수동 배포 (고급 사용자용)
cd terraform
terraform init
terraform plan -var-file=data-stack.tfvars
terraform apply -var-file=data-stack.tfvars -auto-approve
```

**배포 타임라인:**
- Terraform apply: ~10-12분 (VPC, EKS, IAM, Karpenter)
- ArgoCD sync: ~3-5분 (Kubernetes 애드온)
- **총: 전체 스택 ~15분**

</div>
</div>

<div className="timeline-step">
<div className="timeline-number">5</div>
<div className="timeline-content">

### 배포 검증

```bash
# kubectl 구성
export CLUSTER_NAME=spark-on-eks
export AWS_REGION=us-west-2
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

# 노드 확인 (Karpenter 관리)
kubectl get nodes

# 애드온 배포 확인
kubectl get pods -A

# Spark Operator 확인
kubectl get crd sparkapplications.sparkoperator.k8s.io
kubectl get pods -n spark-operator
```

</div>
</div>

<div className="timeline-step">
<div className="timeline-number">6</div>
<div className="timeline-content">

### 예제 워크로드 실행

```bash
# Spark Pi 계산 작업 제출
kubectl apply -f examples/pyspark-pi-job.yaml

# 작업 진행 상황 확인
kubectl get sparkapplications -w

# 드라이버 로그 보기
kubectl logs spark-pi-driver

# Spark History Server 확인 (활성화된 경우)
kubectl port-forward -n spark-operator svc/spark-history-server 18080:80
# 열기: http://localhost:18080
```

</div>
</div>

</div>

## CNCF 에코시스템 통합

Data on EKS는 **CNCF 네이티브**이며 AWS에 최적화하면서 클라우드 네이티브 패턴을 사용합니다:

<div className="cncf-table-container">

| CNCF 프로젝트 | 성숙도 | DoEKS에서의 역할 | AWS 대안 |
|--------------|----------|---------------|-----------------|
| **Kubernetes** | Graduated | 컨테이너 오케스트레이션 | Amazon EKS (관리형 K8s) |
| **Prometheus** | Graduated | 메트릭 및 알림 | Amazon Managed Prometheus (AMP) |
| **Strimzi** | Incubating | Kafka operator | Amazon MSK (관리형 Kafka) |
| **Argo (CD/Workflows)** | Graduated | GitOps 및 파이프라인 | AWS CodePipeline |
| **Helm** | Graduated | 패키지 관리 | - |
| **Karpenter** | Graduated | 노드 자동 확장 | Cluster Autoscaler |
| **Grafana** | Observability partner | 시각화 | Amazon Managed Grafana (AMG) |

</div>

### CNCF + AWS인 이유?

<div style={{
  display: 'grid',
  gridTemplateColumns: 'repeat(2, 1fr)',
  gap: '1.5rem',
  margin: '2rem 0',
  maxWidth: '1200px'
}}>
  <div style={{
    padding: '2rem',
    background: 'linear-gradient(135deg, rgba(102, 126, 234, 0.05), rgba(118, 75, 162, 0.05))',
    borderRadius: '16px',
    border: '2px solid rgba(102, 126, 234, 0.2)'
  }}>
    <h4 style={{ fontSize: '1.25rem', fontWeight: '700', marginBottom: '0.75rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <Globe size={20} /> 이식성
    </h4>
    <div style={{ margin: 0, color: 'var(--ifm-color-content-secondary)' }}>
      Kubernetes가 실행되는 모든 곳에서 실행 (온프레미스, 멀티클라우드)
    </div>
  </div>

  <div style={{
    padding: '2rem',
    background: 'linear-gradient(135deg, rgba(240, 147, 251, 0.05), rgba(245, 87, 108, 0.05))',
    borderRadius: '16px',
    border: '2px solid rgba(240, 147, 251, 0.2)'
  }}>
    <h4 style={{ fontSize: '1.25rem', fontWeight: '700', marginBottom: '0.75rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <Users size={20} /> 커뮤니티 혁신
    </h4>
    <div style={{ margin: 0, color: 'var(--ifm-color-content-secondary)' }}>
      수천 명의 기여자로부터 혜택
    </div>
  </div>

  <div style={{
    padding: '2rem',
    background: 'linear-gradient(135deg, rgba(79, 172, 254, 0.05), rgba(0, 242, 254, 0.05))',
    borderRadius: '16px',
    border: '2px solid rgba(79, 172, 254, 0.2)'
  }}>
    <h4 style={{ fontSize: '1.25rem', fontWeight: '700', marginBottom: '0.75rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <Zap size={20} /> AWS 최적화
    </h4>
    <div style={{ margin: 0, color: 'var(--ifm-color-content-secondary)' }}>
      EKS, S3, IAM, CloudWatch와의 긴밀한 통합
    </div>
  </div>

  <div style={{
    padding: '2rem',
    background: 'linear-gradient(135deg, rgba(67, 233, 123, 0.05), rgba(56, 249, 215, 0.05))',
    borderRadius: '16px',
    border: '2px solid rgba(67, 233, 123, 0.2)'
  }}>
    <h4 style={{ fontSize: '1.25rem', fontWeight: '700', marginBottom: '0.75rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <TrendingUp size={20} /> 하이브리드 워크로드
    </h4>
    <div style={{ margin: 0, color: 'var(--ifm-color-content-secondary)' }}>
      오픈 소스(Spark) + 관리형(EMR on EKS) 혼합
    </div>
  </div>
</div>

## 프로덕션 배포 패턴

### 다중 환경 전략

<div style={{
  display: 'grid',
  gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))',
  gap: '1.5rem',
  margin: '2rem 0',
  maxWidth: '1200px'
}}>
  <div style={{
    padding: '2rem',
    background: 'linear-gradient(135deg, rgba(34, 197, 94, 0.1), rgba(16, 185, 129, 0.05))',
    borderRadius: '16px',
    border: '2px solid rgba(34, 197, 94, 0.3)'
  }}>
    <h4 style={{ fontSize: '1.25rem', fontWeight: '700', marginBottom: '1rem', color: '#059669', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <FlaskConical size={20} /> 개발
    </h4>
    <ul style={{ margin: 0, paddingLeft: '1.5rem', color: 'var(--ifm-color-content-secondary)' }}>
      <li>소형 인스턴스</li>
      <li>100% Spot 인스턴스</li>
      <li>최소 애드온</li>
      <li>단일 AZ</li>
    </ul>
  </div>

  <div style={{
    padding: '2rem',
    background: 'linear-gradient(135deg, rgba(234, 179, 8, 0.1), rgba(202, 138, 4, 0.05))',
    borderRadius: '16px',
    border: '2px solid rgba(234, 179, 8, 0.3)'
  }}>
    <h4 style={{ fontSize: '1.25rem', fontWeight: '700', marginBottom: '1rem', color: '#ca8a04', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <Play size={20} /> 스테이징
    </h4>
    <ul style={{ margin: 0, paddingLeft: '1.5rem', color: 'var(--ifm-color-content-secondary)' }}>
      <li>프로덕션과 유사한 크기</li>
      <li>70% Spot / 30% On-Demand</li>
      <li>전체 애드온 활성화</li>
      <li>다중 AZ</li>
    </ul>
  </div>

  <div style={{
    padding: '2rem',
    background: 'linear-gradient(135deg, rgba(59, 130, 246, 0.1), rgba(37, 99, 235, 0.05))',
    borderRadius: '16px',
    border: '2px solid rgba(59, 130, 246, 0.3)'
  }}>
    <h4 style={{ fontSize: '1.25rem', fontWeight: '700', marginBottom: '1rem', color: '#2563eb', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <CheckCircle size={20} /> 프로덕션
    </h4>
    <ul style={{ margin: 0, paddingLeft: '1.5rem', color: 'var(--ifm-color-content-secondary)' }}>
      <li>적절한 크기의 인스턴스</li>
      <li>70% Spot / 30% On-Demand</li>
      <li>HA, 관측성, 보안</li>
      <li>통합을 갖춘 다중 AZ</li>
    </ul>
  </div>
</div>

### 비용 최적화

**Karpenter 모범 사례:**
- 내결함성을 위해 Spot (70%) + On-Demand (30%) 혼합
- Spot 다양성을 위해 여러 인스턴스 패밀리 사용 (M5, M6i, M6a)
- 유휴 용량을 줄이기 위해 통합 활성화
- NodePool당 적절한 제한 설정

**실현된 절감:**
- Karpenter vs Cluster Autoscaler: 노드 비용 **~30% 감소**
- Spot 인스턴스: On-Demand 대비 **~70% 절감**
- EBS gp3 vs gp2: 스토리지 **~20% 절감**

## 학습 리소스

<div style={{
  display: 'grid',
  gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))',
  gap: '2rem',
  margin: '3rem 0',
  maxWidth: '1200px'
}}>
  <div className="learning-card">
    <h3 style={{ fontSize: '1.5rem', fontWeight: '700', marginBottom: '1rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <BookOpen size={24} /> 튜토리얼
    </h3>
    <div style={{ color: 'var(--ifm-color-content-secondary)', marginBottom: '1.5rem' }}>
      데이터 플랫폼 배포를 위한 단계별 가이드
    </div>
    <ul style={{ paddingLeft: '1.5rem', margin: 0 }}>
      <li><a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/infra">Spark on EKS: 제로에서 프로덕션까지</a></li>
      <li><a href="/data-on-eks/docs/datastacks/streaming/kafka-on-eks/">Strimzi를 사용한 Kafka 스트리밍</a></li>
      <li><a href="/data-on-eks/docs/datastacks/orchestration/airflow-on-eks/">Kubernetes에서 Airflow 워크플로우</a></li>
    </ul>
  </div>

  <div className="learning-card">
    <h3 style={{ fontSize: '1.5rem', fontWeight: '700', marginBottom: '1rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <Zap size={24} /> 심층 분석
    </h3>
    <div style={{ color: 'var(--ifm-color-content-secondary)', marginBottom: '1.5rem' }}>
      프로덕션 최적화를 위한 고급 주제
    </div>
    <ul style={{ paddingLeft: '1.5rem', margin: 0 }}>
      <li><a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/spark-gluten-velox-gpu">Gluten 및 Velox를 사용한 Spark 성능</a></li>
      <li><a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/spark-ebs-pvc">EBS를 사용한 스토리지 최적화</a></li>
      <li><a href="/data-on-eks/docs/bestpractices/intro">보안 및 관측성 모범 사례</a></li>
    </ul>
  </div>

  <div className="learning-card">
    <h3 style={{ fontSize: '1.5rem', fontWeight: '700', marginBottom: '1rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <TrendingUp size={24} /> 벤치마크
    </h3>
    <div style={{ color: 'var(--ifm-color-content-secondary)', marginBottom: '1.5rem' }}>
      실제 성능 테스트 결과
    </div>
    <ul style={{ paddingLeft: '1.5rem', margin: 0 }}>
      <li><a href="/data-on-eks/docs/benchmarks/emr-on-eks">TPCDS 3TB: Spark vs EMR on EKS</a></li>
      <li><a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/spark-graviton">Graviton3 성능 분석</a></li>
      <li><a href="/data-on-eks/docs/datastacks/processing/spark-on-eks/spark-nvme-storage">NVMe 스토리지 성능</a></li>
    </ul>
  </div>
</div>

<div className="cta-section">
  <h2 className="cta-section-title">데이터 플랫폼을 구축할 준비가 되셨나요?</h2>
  <div className="cta-section-description">
    Data on EKS를 사용하여 Amazon EKS에서 프로덕션 워크로드를 실행하는 수천 명의 데이터 엔지니어와 함께하세요.
    15분 안에 첫 번째 스택을 배포하세요.
  </div>
  <div style={{ display: 'flex', justifyContent: 'center', gap: '1.5rem', flexWrap: 'wrap', position: 'relative', zIndex: 1 }}>
    <a
      href="#quick-start"
      style={{
        padding: '1rem 2.5rem',
        background: 'white',
        color: '#4f46e5',
        borderRadius: '50px',
        textDecoration: 'none',
        fontWeight: '700',
        fontSize: '1.1rem',
        boxShadow: '0 8px 25px rgba(0, 0, 0, 0.25)',
        transition: 'all 0.3s ease',
        display: 'inline-flex',
        alignItems: 'center',
        gap: '0.75rem'
      }}
    >
      <Rocket size={20} />
      <span>지금 시작하기</span>
    </a>
    <a
      href="https://github.com/awslabs/data-on-eks"
      style={{
        padding: '1rem 2.5rem',
        background: 'rgba(255, 255, 255, 0.15)',
        color: 'white',
        borderRadius: '50px',
        textDecoration: 'none',
        fontWeight: '700',
        fontSize: '1.1rem',
        border: '2px solid rgba(255, 255, 255, 0.4)',
        backdropFilter: 'blur(10px)',
        transition: 'all 0.3s ease',
        display: 'inline-flex',
        alignItems: 'center',
        gap: '0.75rem'
      }}
    >
      <Code size={20} />
      <span>GitHub에서 Star</span>
    </a>
  </div>
</div>

## 커뮤니티 및 지원

<div style={{
  display: 'grid',
  gridTemplateColumns: 'repeat(auto-fit, minmax(250px, 1fr))',
  gap: '1.5rem',
  margin: '2rem 0',
  maxWidth: '1200px'
}}>
  <a
    href="https://awslabs.github.io/data-on-eks/"
    className="community-card"
  >
    <h4 style={{ fontSize: '1.25rem', fontWeight: '700', marginBottom: '0.75rem', color: 'var(--ifm-heading-color)', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <BookOpen size={20} /> 문서
    </h4>
    <div style={{ margin: 0, color: 'var(--ifm-color-content-secondary)' }}>
      포괄적인 가이드, 튜토리얼 및 API 레퍼런스
    </div>
  </a>

  <a
    href="https://github.com/awslabs/data-on-eks/issues"
    className="community-card"
  >
    <h4 style={{ fontSize: '1.25rem', fontWeight: '700', marginBottom: '0.75rem', color: 'var(--ifm-heading-color)', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <Bug size={20} /> GitHub Issues
    </h4>
    <div style={{ margin: 0, color: 'var(--ifm-color-content-secondary)' }}>
      버그 리포트, 기능 요청 및 토론
    </div>
  </a>

  <a
    href="https://github.com/awslabs/data-on-eks/discussions"
    className="community-card"
  >
    <h4 style={{ fontSize: '1.25rem', fontWeight: '700', marginBottom: '0.75rem', color: 'var(--ifm-heading-color)', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
      <MessageCircle size={20} /> 토론
    </h4>
    <div style={{ margin: 0, color: 'var(--ifm-color-content-secondary)' }}>
      Q&A, 쇼앤텔 및 커뮤니티 아이디어
    </div>
  </a>
</div>

---

**AWS Solutions Architects와 커뮤니티 기여자들이 사랑으로 만들었습니다**

*Data on EKS는 AWS 커뮤니티에서 관리하는 오픈 소스 프로젝트입니다. 지원은 최선의 노력으로 제공됩니다. 이것은 공식 AWS 서비스가 아닙니다.*

**라이선스:** Apache 2.0 | **버전:** 2.0 (현재) | **최종 업데이트:** 2025년 1월
