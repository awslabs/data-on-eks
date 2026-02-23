---
sidebar_label: 기여 가이드
sidebar_position: 8
---

## 데이터 스택에 기여하기

<details>
<summary>요약</summary>

*   **핵심 아이디어:** 이 저장소는 "Base + Overlay" 패턴을 사용합니다. 공통 `infra/terraform` 베이스가 기반을 제공하고, `data-stacks/`의 각 디렉토리는 이를 커스터마이징하는 "오버레이(overlay)"입니다.
*   **배포:** 스택을 배포하려면 해당 디렉토리(예: `data-stacks/spark-on-eks/`)로 이동하여 `./deploy.sh`를 실행합니다. 이 스크립트는 베이스를 임시 `_local` 디렉토리에 복사하고, 스택별 파일을 오버레이한 다음 `terraform apply`를 실행합니다.
*   **커스터마이징:**
    *   **새 스택을 만들려면** 기존 스택을 복사합니다.
    *   **간단한 변경**(인스턴스 수 등)의 경우 스택의 `terraform` 디렉토리 내 `.tfvars` 파일을 편집합니다.
    *   **복잡한 변경**(리소스 수정 등)의 경우 교체하려는 베이스 파일과 *동일한 경로와 이름*으로 스택의 `terraform` 디렉토리에 파일을 생성합니다.
*   **라이프사이클:** 스택을 생성/업데이트하려면 `./deploy.sh`를, 삭제하려면 `./cleanup.sh`를 사용합니다. cleanup 스크립트는 EBS 볼륨과 같은 고아 리소스도 제거하므로 필수적입니다.

</details>

이 가이드는 저장소의 구조와 데이터 스택을 정의하고 배포하는 데 사용되는 설계 패턴을 설명합니다. 주요 목표는 개발자가 기존 스택을 쉽게 커스터마이징하거나 새로운 스택을 만들 수 있도록 하는 것입니다.

### 핵심 개념: Base와 Overlay 패턴

저장소는 인프라 및 데이터 스택 배포를 관리하기 위해 "Base + Overlay" 패턴을 사용합니다.

*   **Base (`infra/`):** 이 디렉토리에는 EKS 클러스터, 네트워킹, 보안, 모니터링 및 기타 공유 리소스에 대한 기본 Terraform 구성이 포함되어 있습니다. 모든 데이터 스택에 대한 기본적이고 공통적인 인프라를 정의합니다.

*   **Overlay (`data-stacks/<stack-name>/`):** `data-stacks` 내의 각 디렉토리는 특정 데이터 분석 스택(예: `spark-on-eks`)을 나타냅니다. 해당 특정 워크로드에 대한 베이스 인프라를 *커스터마이징*하거나 *확장*하는 데 필요한 파일만 포함합니다.

이 구조는 다음과 같이 시각화할 수 있습니다:

```
data-on-eks/
├── infra/                          # 베이스 인프라 템플릿
│   └── terraform/
│       ├── main.tf
│       ├── s3.tf
│       ├── argocd-applications/
│       │   └── *.yaml
│       ├── helm-values/            # Helm 값을 위한 Terraform 템플릿 YAML 파일
│       │   └── *.yaml
│       └── manifests/              # K8s 매니페스트를 위한 Terraform 템플릿 YAML 파일
│           └── *.yaml
│
└── data-stacks/
    └── spark-on-eks/               # 예시 Data Stack
        ├── _local/                 # 작업 디렉토리 (자동 생성). terraform은 이 폴더에서 실행됨
        ├── deploy.sh
        └── terraform/              # 설치 스크립트
            ├── s3.tf                   # infra/terraform/s3.tf 오버라이드
            ├── *.tfvars
            └── argocd-applications/    # infra/terraform/argocd-applications 오버라이드
                └── *.yaml
```

### `infra/terraform/` 내의 특수 파일 유형 및 디렉토리

`infra/terraform/` 디렉토리에는 표준 Terraform 구성(`.tf` 파일)뿐만 아니라 동적 구성 및 GitOps 통합을 용이하게 하는 특수 디렉토리와 파일도 포함되어 있습니다:

*   **`helm-values/`:** 이 디렉토리에는 ArgoCD가 애플리케이션을 배포하는 데 사용하는 Helm `values.yaml` 파일이 포함되어 있습니다. 중요한 것은, 이들이 종종 **Terraform 템플릿 YAML 파일**이라는 것입니다. 이는 Terraform이 먼저 이를 처리하여 동적 정보(예: EKS 클러스터 이름 또는 기타 환경별 세부 정보)를 채운다는 것을 의미합니다. 렌더링된 Helm 값은 ArgoCD가 이를 사용하기 전에 ArgoCD 애플리케이션 매니페스트 파일에 직접 포함됩니다.

*   **`manifests/`:** `helm-values`와 마찬가지로, 이 디렉토리에는 **Terraform 템플릿 YAML 파일**인 Kubernetes 매니페스트 파일이 포함될 수 있습니다. 이러한 매니페스트는 일반적으로 `kubernetes_manifest` 또는 `kubectl_manifest` 리소스를 사용하여 `terraform apply` 프로세스의 일부로 *Terraform에 의해 직접 적용*됩니다. ArgoCD에 의해 배포되거나 관리되지 *않습니다*.

이 구분이 중요합니다: `helm-values`는 ArgoCD가 관리하는 Helm 배포용이고, `manifests`는 Terraform이 직접 관리하는 Kubernetes 리소스용입니다.

### 설계 철학: 왜 이 패턴인가?
현재의 "Base + Overlay" 패턴은 이 저장소의 이전 버전에서 직면한 여러 중요한 문제를 해결하기 위해 개발되었습니다:

1.  **중복 및 불일치:** 이전 버전에서는 각 데이터 스택(블루프린트)이 완전히 독립적인 Terraform 스택이었습니다. 이로 인해 스택 간에 광범위한 코드 중복과 불일치가 발생했습니다. Karpenter 노드 그룹 사양과 같은 공통 컴포넌트조차도 종종 약간 다르지만 발산하는 구성을 가지고 있었습니다.
2.  **높은 유지보수 오버헤드:** 많은 수의 개별 Terraform 스택을 관리하고 테스트하는 것은 매우 어려웠습니다. 모든 블루프린트에서 모듈과 컴포넌트 버전을 동기화하는 것은 지속적인 어려움이었고, 종종 다양한 스택에서 유사한 기능에 대해 서로 다른 모듈 버전이 사용되는 결과를 초래했습니다.
3.  **업그레이드 및 검증의 어려움:** 컴포넌트를 업데이트(예: 새 버전의 Flink 연산자로)하는 것은 복잡하고 오류가 발생하기 쉬운 프로세스였습니다. 어떤 블루프린트가 영향을 받는지 결정하고 업데이트가 회귀를 도입하지 않는지 검증하기가 어려웠습니다. 이 설계가 검증 문제를 완전히 해결하지는 않지만, 여러 스택에서 공유할 수 있는 컴포넌트를 업데이트하기 위한 하나의 중앙 지점(`infra/terraform/`)을 갖춤으로써 더 쉬워집니다.
4.  **모든 것을 처리하는 Terraform 모듈의 제거:** 이전에는 일부 구성 옵션이 노출된 특정 기술을 배포하는 옵션이 포함된 모놀리식 Terraform 모듈을 만들고 의존했습니다. 시간이 지남에 따라 대부분의 구성 옵션을 노출해야 했기 때문에(추상화 목적을 무효화) 복잡하고 불투명하며 유지 관리하기 어려워졌습니다. Base + Overlay 패턴은 이를 스택별로 선택적으로 오버라이드할 수 있는 투명하고 조합 가능한 베이스 구성으로 대체합니다.

이 파일 오버레이 시스템은 Terraform 변수나 모듈에만 의존하는 것에 비해 재사용성, 일관성 및 더 쉬운 유지보수를 촉진하기 위해 설계되었습니다.

Terraform 변수나 모듈에만 의존하는 대신 왜 이 파일 오버레이 시스템을 사용하는지 궁금할 수 있습니다.

중앙 집중식 Terraform 모듈이 고려되었지만 최종적으로 거부되었습니다. 단일 모놀리식 모듈은 모든 잠재적 기술 조합을 수용해야 하므로 빠르게 크고 복잡해질 것입니다.

예를 들어, DataHub는 Kafka, Elasticsearch 및 PostgreSQL이 필요합니다. Airflow도 PostgreSQL을 사용하지만 종종 약간 다른 구성으로 사용합니다. 모놀리식 모듈에서 이러한 차이점은 복잡한 입력 변수 웹으로 노출되어야 합니다. 더 많은 기술과 조합이 추가되면 변수 수가 폭발적으로 증가하여 모듈을 이해하고 유지보수하고 사용하기 어렵게 만듭니다.

오버레이 패턴은 관심사의 더 명확한 분리를 제공합니다. 베이스는 공통적인 "무엇"을 제공하고, 스택 오버레이는 중앙 모듈에 과도한 조건부 로직과 변수를 과부하시키지 않고 해당 특정 컨텍스트에 대한 특수화된 "어떻게"를 제공합니다.

*   **단순성과 검색 가능성:** 스택을 커스터마이징하는 것은 변경하려는 베이스 파일과 동일한 이름과 경로로 스택의 디렉토리에 파일을 만드는 것만큼 간단합니다. 이를 통해 복잡한 변수 보간이나 모듈 로직을 추적하지 않고도 특정 스택이 무엇을 오버라이드하는지 정확히 알 수 있습니다.

*   **복잡한 오버라이드 처리:** 간단한 변경은 Terraform 변수(`.tfvars`)로 처리해야 하지만, 이 패턴은 변수로 쉽게 처리할 수 없는 복잡한 변경을 만드는 데 탁월합니다. 예를 들어, 리소스 정의를 완전히 교체하거나, 프로바이더 구성을 변경하거나, ArgoCD 통합을 통해 완전히 새로운 Kubernetes 매니페스트를 추가하는 경우입니다.

*   **오버라이드 vs 변수 사용 시기:**
    *   **`.tfvars` 사용:** ingress-nginx와 같은 공통 기술 활성화, 인스턴스 수와 같이 많은 데이터 스택에서 공통적인 것들.
    *   **파일 오버라이드 사용:** Terraform 리소스의 구조적 변경, 전체 Kubernetes 매니페스트 교체, 또는 베이스에 해당하는 것이 없는 새 파일 추가. **파일 오버라이드는 강력한 도구이며 신중하게 사용해야 합니다.**

### 배포 프로세스

스택의 디렉토리(예: `data-stacks/spark-on-eks/`)에서 `./deploy.sh`를 실행하면 다음 단계를 수행하는 중앙 집중식 배포 엔진(`infra/terraform/install.sh`)이 트리거됩니다:

1.  **작업 공간 준비:** 스크립트는 스택의 `terraform/` 폴더 내에 `_local/`이라는 작업 디렉토리를 준비합니다. 이전 파일을 제거하여 이 디렉토리를 정리하지만 필수 Terraform 상태(`terraform.tfstate*`), 플러그인 캐시(`.terraform/`) 및 잠금 파일(`.terraform.lock.hcl`)은 보존합니다. 이를 통해 후속 실행이 훨씬 효율적이 됩니다.

2.  **기반 복사:** 스크립트는 전체 `infra/terraform/` 디렉토리를 `_local/` 작업 공간으로 복사합니다.

3.  **오버레이 적용:** 그런 다음 `data-stacks/<stack-name>/terraform/`에서 스택별 파일을 `_local/`로 재귀적으로 복사하여 **동일한 이름과 경로를 가진 베이스 파일을 덮어씁니다.**

4.  **Terraform 실행:** 스크립트는 안정성을 보장하기 위해 특정 다단계 순서로 `_local/` 디렉토리 내에서 Terraform을 실행합니다:
    *   먼저, 작업 공간을 준비하기 위해 `terraform init -upgrade`를 실행합니다.
    *   다음으로, `terraform apply -target=module.vpc`로 핵심 인프라를 적용합니다.
    *   그런 다음, `terraform apply -target=module.eks`로 EKS 클러스터를 적용합니다.
    *   마지막으로, 나머지 모든 리소스를 배포하기 위해 대상 없이 `terraform apply`를 한 번 더 실행합니다.

5.  **GitOps 동기화:** 스택에서 ArgoCD Application 매니페스트를 배포하여 GitOps 컨트롤러가 지속적 배포를 위해 올바른 리소스를 가리키도록 합니다.

---

### 새 데이터 스택 추가 방법

다음은 `my-new-stack`이라는 새 스택을 만드는 단계별 가이드입니다.

**1단계: 스택 디렉토리 생성**

시작하는 가장 쉬운 방법은 구축하려는 것과 유사한 기존 스택을 복사하는 것입니다.

```bash
# 예: spark-on-eks 스택을 복사하여 시작
cp -r data-stacks/spark-on-eks data-stacks/my-new-stack
```

**2단계: 구성 커스터마이징**

이제 `data-stacks/my-new-stack/terraform/` 내의 파일을 수정합니다.

*   **간단한 변수를 변경하려면:** `*.tfvars` 파일(예: `data-stack.tfvars`)을 편집합니다. 이것이 간단한 변경에 선호되는 방법입니다.

    ```hcl
    // data-stacks/my-new-stack/terraform/data-stack.tfvars
    cluster_name = "my-new-eks-cluster"
    ```
    **`deployment_id`에 대한 참고:** 스택을 복사하면 `data-stack.tfvars` 파일에 `deployment_id = "abcdefg"`와 같은 플레이스홀더가 포함됩니다. `./deploy.sh`를 처음 실행하면 스크립트가 자동으로 이를 새로운 랜덤 ID로 교체합니다.

*   **베이스 인프라 파일을 오버라이드하려면:** 다른 S3 버킷 구성을 사용하고 싶다고 가정해 봅시다. 베이스 파일은 `infra/terraform/s3.tf`에 있습니다. 이를 오버라이드하려면 `data-stacks/my-new-stack/terraform/s3.tf`를 편집하면 됩니다. 배포 스크립트는 베이스 파일 대신 여러분의 버전을 사용합니다.

*   **새 컴포넌트를 추가하려면:** 새 파일을 생성합니다. 예를 들어 `data-stacks/my-new-stack/terraform/my-new-resource.tf`. 이 파일은 배포 중에 구성에 추가됩니다.

**3단계: ArgoCD 애플리케이션 커스터마이징**

베이스 `infra/argocd-applications` 디렉토리에는 기본 ArgoCD `Application` 매니페스트 세트가 포함되어 있습니다. 스택에 맞게 커스터마이징하려면:

1.  `infra/argocd-applications` 디렉토리를 `data-stacks/my-new-stack/terraform/argocd-applications`로 복사합니다.
2.  내부의 YAML 파일을 수정합니다. 다음을 원할 수 있습니다:
    *   `source.helm.values`를 사용자 정의 값 파일을 가리키도록 변경.
    *   `destination.namespace` 변경.

배포 중에 스택의 `argocd-applications` 디렉토리가 베이스 디렉토리를 완전히 대체합니다.

**4단계: 배포 및 테스트**

새 스택의 디렉토리에서 배포 스크립트를 실행합니다:

```bash
cd data-stacks/my-new-stack
./deploy.sh
```

Terraform 계획을 검사하고 적용합니다. 완료되면 EKS 클러스터와 ArgoCD UI를 확인하여 새 스택이 예상대로 배포되었는지 확인합니다.

**5단계: 스택 정리**

각 데이터 스택에는 `deploy.sh`에 대응하는 `cleanup.sh` 스크립트가 포함되어 있습니다. 이 스크립트는 원하지 않는 비용을 방지하기 위해 스택에서 생성된 모든 리소스를 삭제하는 역할을 합니다.

프로세스는 배포 워크플로우를 반영합니다:
1.  스택 디렉토리(예: `data-stacks/my-new-stack/`)의 `cleanup.sh` 스크립트는 `_local/` 작업 공간으로 이동하는 래퍼입니다.
2.  그런 다음 `infra/terraform/`에서 복사된 메인 `cleanup.sh` 엔진을 실행합니다.

cleanup 엔진은 단순한 `terraform destroy`보다 더 정교합니다. 리소스가 올바른 순서로 제거되도록 다단계 정리를 수행합니다:
*   **Pre-Terraform 정리:** 특정 Kubernetes 리소스를 즉시 제거하기 위해 `kubectl delete`를 실행합니다.
*   **대상 지정 Terraform 파괴:** Terraform이 관리하는 특정 Kubernetes 매니페스트를 먼저 지능적으로 대상 지정하고 파괴합니다.
*   **전체 Terraform 파괴:** 나머지 인프라를 제거하기 위해 전체 `terraform destroy`를 실행합니다.
*   **EBS 볼륨 정리:** destroy 명령이 완료된 후 스크립트는 중요한 마지막 단계를 수행합니다. 스택의 고유한 `deployment_id`를 사용하여 Kubernetes PersistentVolumeClaims(PVC)에 의해 남겨졌을 수 있는 고아 EBS 볼륨을 찾아 삭제합니다.

정리 프로세스를 실행하려면:
```bash
cd data-stacks/my-new-stack
./cleanup.sh
```

---
## 기타 규칙

### `examples/` 디렉토리
새 스택을 만들 때 `examples/` 디렉토리도 볼 수 있습니다. 이 폴더는 데이터 스택과 관련된 사용 예제, 튜토리얼, 샘플 코드 또는 쿼리를 저장하는 관례적인 장소입니다. 사용자가 새 데이터 스택을 시작하는 데 도움이 되도록 예제를 포함하는 것이 좋습니다.
