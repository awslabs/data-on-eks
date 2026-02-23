---
title: 스택 커스터마이징
sidebar_position: 8
---

## 스택 커스터마이징

데이터 스택을 배포한 후 추가 컴포넌트를 활성화하거나 새로운 컴포넌트를 추가하여 커스터마이징할 수 있습니다.

:::tip 기본 설정으로 먼저 시작하세요
아직 스택을 배포하지 않았다면 기본 설정을 사용하여 사전 구성된 [데이터 스택](/docs/datastacks/) 중 하나로 시작하세요. 실행된 후 여기로 돌아와서 커스터마이징하세요.
:::

:::info 컴포넌트 정보
- **핵심 인프라(Core Infrastructure)**: 항상 배포됨 - 오토스케일링, 모니터링, GitOps와 같은 기본 기능 제공
- **선택적 컴포넌트(Optional Components)**: Terraform 변수를 통해 필요 시 활성화
- **사용자 정의 컴포넌트(Custom Components)**: 실험을 위해 ArgoCD를 통해 자체 추가
:::

---

### 핵심 구성 변수

다음 변수들은 기본 인프라 설정을 구성합니다:

| 변수 | 설명 | Terraform 변수 | 타입 | 기본값 |
|----------|-------------|-------------------|------|---------|
| Name | 모든 리소스의 식별자로 사용될 이름 | `name` | `string` | `data-on-eks` |
| Region | AWS 리전 | `region` | `string` | `us-west-2` |
| Tags | 모든 리소스에 추가할 태그 맵 | `tags` | `string` | `{}` |

---

### 핵심 인프라 (항상 활성화)

다음 컴포넌트들은 모든 데이터 스택에서 기본적으로 배포됩니다:

| 컴포넌트 | 설명 | 변수 | 상태 |
|-----------|-------------|----------|--------|
| AWS Load Balancer Controller | AWS ALB/NLB 통합 | N/A | ✅ |
| Argo Events | 이벤트 기반 워크플로우 자동화 | N/A | ✅ |
| Argo Workflows | Kubernetes용 워크플로우 엔진 | N/A | ✅ |
| ArgoCD | GitOps 지속적 배포 | N/A | ✅ |
| Cert Manager | TLS 인증서 관리 | N/A | ✅ |
| Fluent Bit | CloudWatch로 로그 전달 | N/A | ✅ |
| Karpenter | 노드 오토스케일링 및 프로비저닝 | N/A | ✅ |
| Kube Prometheus Stack | Prometheus 및 Grafana 모니터링 | N/A | ✅ |
| Spark History Server | Spark 작업 이력 및 메트릭 | N/A | ✅ |
| Spark Operator | Apache Spark 작업 오케스트레이션 | N/A | ✅ |
| YuniKorn | 고급 배치 스케줄링 | N/A | ✅ |

---

### 선택적 컴포넌트

다음 컴포넌트들은 해당 Terraform 변수를 설정하여 활성화할 수 있습니다.

#### 활성화 방법

1. 스택의 `terraform/data-stack.tfvars` 파일 편집
2. 해당 `enable_*` 변수를 `true`로 설정
3. 재배포: `./deploy.sh`

예시:
```hcl
name   = "my-data-platform"
region = "us-east-1"

enable_datahub  = true
enable_superset = true
```

#### 사용 가능한 선택적 컴포넌트

| 컴포넌트 | 설명 | 변수 | 기본값 |
|-----------|-------------|----------|---------|
| Airflow | 워크플로우 오케스트레이션을 위한 Apache Airflow 활성화 | `enable_airflow` | ❌ |
| Amazon Prometheus | AWS Managed Prometheus 서비스 활성화 | `enable_amazon_prometheus` | ❌ |
| Celeborn | 원격 셔플링 서비스를 위한 Apache Celeborn 활성화 | `enable_celeborn` | ❌ |
| Cluster Addons | 각 애드온의 활성화 여부를 제어하는 EKS 애드온 이름과 불리언 값의 맵. 이를 통해 이 Terraform 스택에서 배포할 애드온을 세밀하게 제어할 수 있습니다. 애드온을 활성화하거나 비활성화하려면 blueprint.tfvars 파일에서 해당 값을 `true` 또는 `false`로 설정하세요. 새 애드온을 추가해야 하는 경우 이 변수 정의를 업데이트하고 EKS 모듈(예: eks.tf locals)의 로직도 필요한 사용자 정의 구성을 포함하도록 조정하세요. | `enable_cluster_addons` | ❌ |
| Datahub | 메타데이터 관리를 위한 DataHub 활성화 | `enable_datahub` | ❌ |
| Ingress Nginx | ingress-nginx 활성화 | `enable_ingress_nginx` | ✅ |
| Ipv6 | EKS 클러스터 및 해당 컴포넌트에 대한 IPv6 활성화 | `enable_ipv6` | ❌ |
| Jupyterhub | Jupyter Hub 활성화 | `enable_jupyterhub` | ✅ |
| Nvidia Device Plugin | GPU 워크로드를 위한 NVIDIA Device 플러그인 애드온 활성화 | `enable_nvidia_device_plugin` | ❌ |
| Raydata | ArgoCD를 통한 Ray Data 활성화 | `enable_raydata` | ❌ |
| Superset | 데이터 탐색 및 시각화를 위한 Apache Superset 활성화 | `enable_superset` | ❌ |

---

### EKS 클러스터 애드온

`enable_cluster_addons` 맵 변수를 통한 EKS 애드온의 세밀한 제어:

| 애드온 | 설명 | 변수 | 기본값 |
|-------|-------------|----------|---------|
| Amazon Cloudwatch Observability | Amazon CloudWatch 관측성 | `enable_cluster_addons["amazon-cloudwatch-observability"]` | ❌ |
| Aws Ebs Csi Driver | 영구 볼륨을 위한 Amazon EBS CSI 드라이버 | `enable_cluster_addons["aws-ebs-csi-driver"]` | ✅ |
| Aws Mountpoint S3 Csi Driver | Amazon S3용 Mountpoint CSI 드라이버 | `enable_cluster_addons["aws-mountpoint-s3-csi-driver"]` | ✅ |
| Eks Node Monitoring Agent | EKS 노드 모니터링 에이전트 | `enable_cluster_addons["eks-node-monitoring-agent"]` | ✅ |
| Metrics Server | 오토스케일링을 위한 Kubernetes 메트릭 서버 | `enable_cluster_addons["metrics-server"]` | ✅ |

---

### 새 컴포넌트 추가

데이터 스택을 배포한 후 실험을 위해 추가 컴포넌트를 추가할 수 있습니다.

#### 빠른 방법: ArgoCD를 통해 배포

새 컴포넌트를 추가하는 가장 빠른 방법:

1. ArgoCD Application 매니페스트 생성
2. 적용: `kubectl apply -f my-component.yaml`
3. 모니터링: `kubectl get application my-component -n argocd`

**예시: Kro (Kubernetes Resource Orchestrator) 추가**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kro
  namespace: argocd
spec:
  project: default
  source:
    repoURL: oci://registry.k8s.io/kro/charts
    chart: kro
    targetRevision: 0.7.1
  destination:
    server: https://kubernetes.default.svc
    namespace: kro-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

매니페스트 적용:
```bash
kubectl apply -f kro-app.yaml
```

배포 확인:
```bash
kubectl get application kro -n argocd
kubectl get pods -n kro-system
```

완료 후 정리:
```bash
kubectl delete application kro -n argocd
```

#### 고급: 스택에 통합 (선택 사항)

재현 가능한 배포를 위해 Terraform으로 컴포넌트를 관리하려면:

1. 스택의 `terraform/` 디렉토리에 오버레이 파일 생성:
   - `terraform/kro.tf` - Terraform 리소스 정의
   - `terraform/argocd-applications/kro.yaml` - ArgoCD 앱 매니페스트
   - `terraform/helm-values/kro.yaml` - Helm 값 (필요한 경우)

2. 스택 재배포: `./deploy.sh`

이 접근 방식은 팀을 위한 재사용 가능한 스택을 구축할 때 유용합니다. 자세한 지침은 [기여 가이드](./contributing.md)를 참조하세요.

---

**참고**: 이 페이지는 Terraform 소스 코드에서 자동 생성됩니다. 업데이트하려면 다음을 실행하세요:
```bash
./website/scripts/generate-available-components.sh
```
