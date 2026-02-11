---
title: Flink 인프라 배포
sidebar_label: 인프라
sidebar_position: 2
---

## Flink on EKS 인프라 배포

스트리밍 워크로드를 위한 Flink on EKS 인프라 배포 및 구성에 대한 완전한 가이드입니다.

### 사전 요구 사항

배포하기 전에 다음 도구가 설치되어 있는지 확인하세요:

- **AWS CLI** - [설치 가이드](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- **Terraform** (>= 1.0) - [설치 가이드](https://developer.hashicorp.com/terraform/install)
- **kubectl** - [설치 가이드](https://kubernetes.io/docs/tasks/tools/)
- **Helm** (>= 3.0) - [설치 가이드](https://helm.sh/docs/intro/install/)
- **AWS 자격 증명 구성됨** - `aws configure` 실행 또는 IAM 역할 사용

## 개요

Flink on EKS 인프라는 Amazon EKS에서 Apache Flink 스트리밍 워크로드를 위한 프로덕션 준비 완료 기반을 제공합니다. 포함 사항:

- 스트리밍에 최적화된 구성을 갖춘 **EKS 클러스터**
- 네이티브 Kubernetes Flink 작업 관리를 위한 **Flink Operator**
- 이벤트 스트리밍 및 데이터 수집을 위한 **Kafka 클러스터**
- 내결함성을 위한 S3 스토리지를 갖춘 **상태 백엔드(State Backend)**
- Flink 전용 메트릭 및 대시보드를 갖춘 **모니터링 스택**

## 빠른 시작

```bash
# 저장소 복제
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/data-stacks/flink-on-eks

# 인프라 배포
./deploy.sh

# 배포 확인
kubectl get nodes
kubectl get pods -n flink-operator
```


## 아키텍처 구성 요소

### 핵심 인프라

#### Apache Flink Operator
- Flink 작업을 위한 네이티브 Kubernetes CRD
- JobManager 및 TaskManager 관리
- 상태 백엔드 구성
- 체크포인트 조정
- 복구 및 확장

#### 상태 관리
- S3 기반 상태 저장소
- RocksDB 로컬 상태
- 체크포인트 구성
- 세이브포인트 관리
- 복구 메커니즘

## 배포 프로세스

### 1. 인프라 배포
```bash
# 자동화된 배포 프로세스
./deploy.sh
```

:::note

**배포 실패 시:**
- 동일한 명령을 다시 실행: `./deploy.sh`
- 여전히 실패하면 kubectl 명령을 사용하여 디버그하거나 [이슈를 등록](https://github.com/awslabs/data-on-eks/issues)하세요

:::

:::info

**예상 배포 시간:** 15-20분

:::


### 2. 배포 후 확인

배포 스크립트는 자동으로 kubectl을 구성합니다. 클러스터가 준비되었는지 확인합니다:

```bash
# kubeconfig 설정
export KUBECONFIG=kubeconfig.yaml

# 클러스터 노드 확인
kubectl get nodes

# 모든 네임스페이스 확인
kubectl get namespaces

# ArgoCD 애플리케이션 확인
kubectl get applications -n argocd
```

:::tip 빠른 확인

성공적인 배포를 확인하려면 다음 명령을 실행하세요:

```bash
# 1. 노드가 준비되었는지 확인
kubectl get nodes
# 예상: 4-5개의 노드가 STATUS=Ready 상태

# 2. ArgoCD 애플리케이션이 동기화되었는지 확인
kubectl get applications -n argocd
# 예상: 모든 앱이 "Synced" 및 "Healthy" 표시

# 3. Karpenter NodePools 준비 확인
kubectl get nodepools

```

:::


## 정리

### 인프라 정리
```bash
# 전체 정리
./cleanup.sh
```

## 다음 단계

인프라 배포 후:

- [Flink 작업 시작하기](./getting-started)
