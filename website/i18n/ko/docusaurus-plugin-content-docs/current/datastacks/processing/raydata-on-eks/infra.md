---
title: 인프라 배포
sidebar_position: 1
---

# Ray Data on EKS - 인프라 배포

분산 컴퓨팅, 머신러닝, 데이터 처리 워크로드를 위한 프로덕션 준비 Ray 인프라를 Amazon EKS에 배포합니다.

## 아키텍처 개요

이 배포는 자동 확장, 모니터링, GitOps 기반 관리가 포함된 완전한 Ray 플랫폼을 EKS에 프로비저닝합니다.

### 구성 요소

| 계층 | 구성 요소 | 목적 |
|-----|----------|-----|
| **AWS 인프라** | VPC (듀얼 CIDR), EKS v1.31+, S3, KMS | 네트워크 격리, 관리형 Kubernetes, 스토리지, 암호화 |
| **플랫폼** | Karpenter, ArgoCD, Prometheus Stack | 노드 오토스케일링, GitOps 배포, 모니터링 |
| **보안** | Pod Identity, cert-manager, external-secrets | IAM 인증, TLS, 시크릿 관리 |
| **Ray** | KubeRay Operator v1.4.2, RayCluster/Job/Service CRD | 클러스터 관리, 작업 오케스트레이션 |

### 네트워크 설계

```
VPC 10.0.0.0/16
├── 퍼블릭 서브넷 (3 AZ)   → NAT Gateway, Load Balancer
├── 프라이빗 서브넷 (3 AZ)  → EKS 컨트롤 플레인, Ray 워크로드
└── 보조 100.64.0.0/16     → Karpenter 관리 노드 풀
```

## 전제 조건

| 요구 사항 | 버전 | 목적 |
|---------|------|-----|
| AWS CLI | v2.x | AWS 리소스 관리 |
| Terraform | >= 1.0 | Infrastructure as Code |
| kubectl | >= 1.28 | Kubernetes 관리 |
| Git | 최신 | 저장소 복제 |

**필요한 IAM 권한:**
- EKS: 클러스터 관리
- EC2: VPC, Security Group, 인스턴스
- IAM: 역할, 정책, Pod Identity
- S3: 버킷 작업
- CloudWatch: 로그 및 메트릭
- KMS: 암호화 키

## 배포

### 1. 저장소 복제

```bash
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/data-stacks/ray-on-eks
```

### 2. 스택 구성

`terraform/data-stack.tfvars` 편집:

```hcl
name                      = "ray-on-eks"      # 고유 클러스터 이름
region                    = "us-west-2"       # AWS 리전
enable_raydata            = true              # KubeRay Operator 배포
enable_ingress_nginx      = true              # Ray Dashboard 접근 (선택 사항)
enable_jupyterhub         = false             # 대화형 노트북 (선택 사항)
enable_amazon_prometheus  = false             # AWS Managed Prometheus (선택 사항)
```

### 3. 인프라 배포

```bash
./deploy.sh
```

**배포 프로세스** (~25-30분):
1. ✅ VPC, EKS 클러스터, S3 버킷 프로비저닝
2. ✅ 노드 오토스케일링을 위한 Karpenter 구성
3. ✅ GitOps를 위한 ArgoCD 배포
4. ✅ KubeRay Operator 및 플랫폼 애드온 설치
5. ✅ kubectl 접근 구성

### 4. 배포 확인

```bash
source set-env.sh

# 클러스터 확인
kubectl get nodes

# KubeRay Operator 확인
kubectl get pods -n kuberay-operator

# ArgoCD 애플리케이션 확인
kubectl get applications -n argocd | grep -E "kuberay|karpenter"
```

**예상 출력:**
```
NAME               READY   STATUS    AGE
kuberay-operator   1/1     Running   5m
```

## 대시보드 접근

### Ray Dashboard

```bash
# RayCluster 배포 후 (아래 예제 참조)
kubectl port-forward -n raydata service/<raycluster-name>-head-svc 8265:8265

# 접근: http://localhost:8265
```

### ArgoCD UI

```bash
# 비밀번호 가져오기
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# 포트 포워드
kubectl port-forward -n argocd svc/argocd-server 8080:443

# 접근: https://localhost:8080 (admin / <password>)
```

### Grafana 모니터링

```bash
# 비밀번호 가져오기
kubectl get secret -n kube-prometheus-stack kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d

# 포트 포워드
kubectl port-forward -n kube-prometheus-stack svc/kube-prometheus-stack-grafana 3000:80

# 접근: http://localhost:3000 (admin / <password>)
```

## AWS 접근을 위한 Pod Identity

인프라는 Ray 워크로드가 AWS 서비스에 안전하게 접근할 수 있도록 EKS Pod Identity를 자동으로 구성합니다.

### 자동 구성

**IAM 역할** (`raydata` 네임스페이스):
- **S3 접근**: 데이터 버킷 및 Iceberg 웨어하우스 읽기/쓰기
- **AWS Glue**: Iceberg 카탈로그 테이블 생성 및 관리
- **CloudWatch**: 로그 및 메트릭 쓰기
- **S3 Tables**: S3 Tables API 접근

**구성 위치**: `/infra/terraform/teams.tf` 및 `/infra/terraform/ray-operator.tf`

### Ray 작업에서의 사용

서비스 계정을 지정하여 Pod Identity 활성화:

```yaml
apiVersion: ray.io/v1
kind: RayJob
metadata:
  name: my-ray-job
  namespace: raydata
spec:
  submitterPodTemplate:
    spec:
      serviceAccountName: raydata  # ← Pod Identity 활성화

  rayClusterSpec:
    headGroupSpec:
      template:
        spec:
          serviceAccountName: raydata  # ← Pod Identity 활성화

    workerGroupSpecs:
      - template:
          spec:
            serviceAccountName: raydata  # ← Pod Identity 활성화
```

:::tip 네이티브 S3 접근
PyArrow 21.0.0+는 `AWS_CONTAINER_CREDENTIALS_FULL_URI`를 통해 Pod Identity 자격 증명을 자동으로 사용합니다. boto3 구성이나 자격 증명 헬퍼가 필요 없습니다.
:::

## 예제: 기본 Ray 클러스터

오토스케일링이 포함된 Ray 클러스터 배포:

```yaml
apiVersion: ray.io/v1
kind: RayCluster
metadata:
  name: raycluster-basic
  namespace: raydata
spec:
  rayVersion: '2.47.1'
  enableInTreeAutoscaling: true

  headGroupSpec:
    rayStartParams:
      dashboard-host: '0.0.0.0'
    template:
      spec:
        serviceAccountName: raydata
        containers:
        - name: ray-head
          image: rayproject/ray:2.47.1-py310
          resources:
            requests: {cpu: "1", memory: "2Gi"}
            limits: {cpu: "2", memory: "4Gi"}

  workerGroupSpecs:
  - replicas: 2
    minReplicas: 1
    maxReplicas: 10
    groupName: workers
    template:
      spec:
        serviceAccountName: raydata
        containers:
        - name: ray-worker
          image: rayproject/ray:2.47.1-py310
          resources:
            requests: {cpu: "2", memory: "4Gi"}
            limits: {cpu: "4", memory: "8Gi"}
```

**배포:**
```bash
kubectl apply -f raycluster-basic.yaml

# 확인
kubectl get rayclusters -n raydata
kubectl get pods -n raydata
```

## 고급 구성

### 스택 애드온

`terraform/data-stack.tfvars`에서 선택적 구성 요소 구성:

| 애드온 | 기본값 | 목적 |
|-------|-------|-----|
| `enable_raydata` | true | KubeRay Operator |
| `enable_ingress_nginx` | false | 공개 대시보드 접근 |
| `enable_jupyterhub` | false | 대화형 노트북 |
| `enable_amazon_prometheus` | false | AWS Managed Prometheus |

### Karpenter 오토스케일링

Karpenter는 Ray 워크로드를 위해 자동으로 노드를 프로비저닝합니다. 특정 인스턴스 유형에 대한 NodePool 구성:

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: ray-compute
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          values: ["spot", "on-demand"]
        - key: node.kubernetes.io/instance-type
          values: ["m5.2xlarge", "m5.4xlarge", "c5.4xlarge"]
  limits:
    cpu: "1000"
```

## 문제 해결

### Operator 문제

```bash
# Operator 상태 확인
kubectl get pods -n kuberay-operator
kubectl logs -n kuberay-operator deployment/kuberay-operator --tail=50

# ArgoCD 애플리케이션 확인
kubectl get application kuberay-operator -n argocd
```

**일반적인 문제:**
| 문제 | 원인 | 해결 방법 |
|-----|-----|----------|
| ImagePullBackOff | 네트워크 연결 | VPC NAT Gateway, Security Group 확인 |
| CrashLoopBackOff | 구성 오류 | Operator 로그에서 세부 정보 검토 |
| Pending Pod | 용량 부족 | Karpenter 로그, 노드 제한 확인 |

### Ray 클러스터 문제

```bash
# 클러스터 설명
kubectl describe raycluster <name> -n raydata

# Pod 로그 확인
kubectl logs <ray-head-pod> -n raydata

# Karpenter 프로비저닝 확인
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=100
```

## 비용 최적화

### 권장 사항

1. **스팟 인스턴스**: Karpenter는 기본적으로 스팟 사용 (60-90% 절감)
2. **적정 크기 조정**: 작은 인스턴스로 시작, 메트릭에 따라 확장
3. **오토스케일링**: 워크로드 수요에 맞게 Ray 오토스케일링 활성화
4. **노드 통합**: Karpenter가 자동으로 활용도가 낮은 노드 통합

### 비용 모니터링

```bash
# 프로비저닝된 인스턴스 보기
kubectl get nodes -l karpenter.sh/capacity-type

# 인스턴스 유형 확인
kubectl get nodes -L node.kubernetes.io/instance-type
```

## 정리

```bash
# Ray 클러스터 삭제
kubectl delete rayclusters --all -n raydata

# 인프라 삭제
./cleanup.sh
```

:::warning 데이터 손실
이 작업은 S3 버킷을 포함한 모든 리소스를 삭제합니다. 정리 전에 중요한 데이터를 백업하세요.
:::

## 다음 단계

1. **[Spark 로그 처리](spark-logs-processing)** - Ray Data와 Iceberg로 Spark 로그를 처리하는 프로덕션 예제
2. **[KubeRay 예제](https://docs.ray.io/en/latest/cluster/kubernetes/examples/index.html)** - 공식 Ray on Kubernetes 가이드
3. **[Ray Train](https://docs.ray.io/en/latest/train/train.html)** - 분산 ML 학습
4. **[Ray Serve](https://docs.ray.io/en/latest/serve/index.html)** - 모델 서빙

## 리소스

- [KubeRay 문서](https://docs.ray.io/en/latest/cluster/kubernetes/index.html)
- [Data-on-EKS GitHub](https://github.com/awslabs/data-on-eks)
- [Karpenter 문서](https://karpenter.sh/)
