---
title: DataHub 인프라 배포
sidebar_label: 인프라
sidebar_position: 0
---

## DataHub on EKS

이 가이드는 Amazon EKS에 확장 가능한 DataHub 플랫폼을 배포하는 방법을 설명합니다. 스택은 Terraform으로 프로비저닝되며 노드 자동 스케일링을 위한 Karpenter와 GitOps 스타일 애플리케이션 관리를 위한 ArgoCD가 포함됩니다.

### 아키텍처

```mermaid
graph TD
    subgraph "AWS Cloud"
        subgraph "EKS Cluster"
            ArgoCD[ArgoCD]
            Karpenter[Karpenter]
            DataHub[DataHub]
            Kafka[Kafka]
            Postgres[PostgreSQL]
        end
    end

    User[User] --> DataHub
    DataHub -- "Stores metadata" --> Postgres
    DataHub -- "Uses for metadata events" --> Kafka
    ArgoCD --"Manages"--> DataHub
    ArgoCD --"Manages"--> Kafka
    ArgoCD --"Manages"--> Postgres
```

- **Amazon EKS 클러스터:** 모든 애플리케이션을 실행하기 위한 핵심 Kubernetes 환경.
- **DataHub:** 데이터 검색, 데이터 관측성 및 데이터 거버넌스를 위한 플랫폼.
- **ArgoCD:** GitOps 방식으로 DataHub 및 해당 종속성의 배포를 관리합니다.
- **Karpenter:** 필요할 때 새 EKS 노드를 자동으로 프로비저닝하여 클러스터가 효율적으로 확장될 수 있도록 합니다.
- **PostgreSQL:** DataHub의 메타데이터 데이터베이스를 호스팅합니다.
- **Kafka:** 메타데이터 변경 이벤트 스트리밍을 위해 DataHub에서 사용됩니다.


### 사전 요구 사항

배포하기 전에 다음 도구가 설치되어 있는지 확인하세요:

- **AWS CLI** - [설치 가이드](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- **Terraform** (>= 1.0) - [설치 가이드](https://developer.hashicorp.com/terraform/install)
- **kubectl** - [설치 가이드](https://kubernetes.io/docs/tasks/tools/)
- **Helm** (>= 3.0) - [설치 가이드](https://helm.sh/docs/intro/install/)
- **AWS 자격 증명 구성됨** - `aws configure` 실행 또는 IAM 역할 사용

## 1단계: 저장소 복제 및 이동

```bash
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/data-stacks/datahub-on-eks
```

## 2단계: 스택 커스터마이징
필요한 경우 설정을 커스터마이징하려면 `terraform/data-stack.tfvars` 파일을 편집합니다. 예를 들어 `vi`, `nano` 또는 다른 텍스트 편집기로 열 수 있습니다.

## 3단계: 인프라 배포

배포 스크립트를 실행합니다:

```bash
./deploy.sh
```

:::note

**배포 실패 시:**
- 동일한 명령을 다시 실행: `./deploy.sh`
- 여전히 실패하면 kubectl 명령을 사용하여 디버그하거나 [이슈를 등록](https://github.com/awslabs/data-on-eks/issues)하세요

:::

:::info

**예상 배포 시간:** 15-30분

:::

## 4단계: 배포 확인

배포 스크립트는 자동으로 kubectl을 구성합니다. 클러스터가 준비되었는지 확인합니다:

```bash
# kubeconfig 설정
export KUBECONFIG=kubeconfig.yaml

:::tip Kubeconfig 지속성
`export` 명령은 현재 터미널 세션에 대해서만 `KUBECONFIG`를 설정합니다. 새 터미널을 열면 이 명령을 다시 실행해야 합니다. 영구적으로 만들려면 쉘의 프로필 스크립트(예: `~/.bashrc`, `~/.zshrc`)에 해당 라인을 추가할 수 있습니다:

`echo "export KUBECONFIG=$(pwd)/kubeconfig.yaml" >> ~/.bashrc && source ~/.bashrc`

bash를 사용하지 않는 경우 쉘의 특정 프로필 파일로 `~/.bashrc`를 교체하세요.
:::


다음 명령을 사용하여 스택의 핵심 컴포넌트가 올바르게 실행 중인지 확인합니다.

```bash
# 1. EKS 노드가 준비되었는지 확인
kubectl get nodes
# 예상: 최소 2-3개의 노드가 'Ready' 상태여야 합니다.

# 2. Karpenter NodePools가 구성되었는지 확인
kubectl get nodepools
# 예상: 클러스터에 대해 정의된 nodepools가 보여야 합니다.

# 3. ArgoCD 애플리케이션이 Synced되고 Healthy한지 확인
kubectl get applications -n argocd
# 예상: 모든 애플리케이션의 SYNC STATUS가 'Synced'이고 HEALTH STATUS가 'Healthy'여야 합니다.
```

<details>
<summary><b>예상 출력 예시</b></summary>

**노드:**
```
NAME                                          STATUS   ROLES    AGE     VERSION
ip-100-64-112-7.us-west-2.compute.internal    Ready    <none>   6h16m   v1.33.5-eks-113cf36
ip-100-64-113-62.us-west-2.compute.internal   Ready    <none>   6h16m   v1.33.5-eks-113cf36
ip-100-64-12-166.us-west-2.compute.internal   Ready    <none>   6h10m   v1.33.5-eks-113cf36

```

**ArgoCD 애플리케이션:**
```
NAME                           SYNC STATUS   HEALTH STATUS
datahub                        Scyned        Healthy
argo-events                    Synced        Healthy
argo-workflows                 Synced        Healthy
aws-for-fluentbit              Synced        Healthy
...
```

**Karpenter NodePools:**
```
NAME                              TYPE          CAPACITY    ZONE         NODE                                          READY   AGE
general-purpose-d2mrg             m7g.4xlarge   spot        us-west-2a   ip-100-64-12-166.us-west-2.compute.internal   True    6h12m
general-purpose-d5mgm             m7g.4xlarge   spot        us-west-2a   ip-100-64-50-67.us-west-2.compute.internal    True    6h15m
memory-optimized-graviton-xkn5x   r8g.4xlarge   on-demand   us-west-2a   ip-100-64-59-123.us-west-2.compute.internal   True    6h14m
```

</details>

## 5단계: ArgoCD UI 액세스

배포 스크립트는 마지막에 ArgoCD 자격 증명을 표시합니다. 다른 서비스와의 포트 충돌을 피하기 위해 ArgoCD를 로컬 포트 `8081`로 포워딩합니다.

```bash
# ArgoCD 서버 포트 포워딩
kubectl port-forward svc/argocd-server -n argocd 8081:443
```

브라우저에서 https://localhost:8081 을 엽니다:
- **사용자명:** `admin`
- **비밀번호:** `deploy.sh` 출력 끝에 표시됨

:::info
모든 애플리케이션이 **Synced** 및 **Healthy** 상태로 표시되기까지 추가로 ~5분이 걸릴 수 있습니다.
:::


## 문제 해결

### 일반적인 문제

**Pending 상태에서 멈춘 Pod:**
```bash
# 노드 용량 확인
kubectl describe nodes

# Karpenter 로그 확인
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter
```

**ArgoCD 애플리케이션이 동기화되지 않음:**

```bash
# ArgoCD 애플리케이션 상태 확인
kubectl get applications -n argocd

# 특정 애플리케이션 확인
kubectl describe application DataHub-operator -n argocd
```


## 다음 단계

인프라가 배포되면 이제 모든 DataHub 예제를 실행할 수 있습니다:

- [Datahub CLI를 사용한 데이터 수집](/docs/datastacks/databases/datahub-on-eks/cli-ingestion)


## 정리

모든 리소스를 제거하려면 전용 정리 스크립트를 사용합니다:

```bash
# 스택 디렉토리로 이동
cd data-on-eks/data-stacks/datahub-on-eks

# 정리 스크립트 실행
./cleanup.sh
```

:::warning

이 명령은 모든 리소스와 데이터를 삭제합니다. 먼저 중요한 데이터를 백업했는지 확인하세요.

:::


:::note

**정리 실패 시:**
- 동일한 명령을 다시 실행: `./cleanup.sh`
- 모든 리소스가 삭제될 때까지 계속 다시 실행
- 일부 AWS 리소스는 여러 번의 정리 시도가 필요한 종속성이 있을 수 있습니다

:::
