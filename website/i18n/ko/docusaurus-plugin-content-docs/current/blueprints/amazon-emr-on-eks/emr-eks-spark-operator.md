---
sidebar_position: 3
sidebar_label: Spark Operator가 포함된 EMR 런타임
---
import CollapsibleContent from '@site/src/components/CollapsibleContent';

# Spark Operator가 포함된 EMR 런타임

## 소개
이 게시물에서는 EMR Spark Operator가 포함된 EKS를 배포하고 EMR 런타임으로 샘플 Spark 작업을 실행하는 방법을 알아봅니다.

이 [예제](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/emr-eks-karpenter)에서는 Spark Operator 및 EMR 런타임을 사용하여 Spark 애플리케이션을 실행하는 데 필요한 다음 리소스를 프로비저닝합니다.

- 퍼블릭 엔드포인트(데모 목적으로만)가 있는 EKS 클러스터 컨트롤 플레인 생성
- 두 개의 관리형 노드 그룹
  - 시스템 중요 파드를 실행하기 위해 3개의 AZ가 있는 코어 노드 그룹. 예: Cluster Autoscaler, CoreDNS, 관측성, 로깅 등
  - Spark 작업을 실행하기 위한 단일 AZ가 있는 Spark 노드 그룹
- 하나의 데이터 팀 생성 (`emr-data-team-a`)
  - 팀을 위한 새 네임스페이스 생성
  - 팀 실행 역할을 위한 새 IAM 역할
- `emr-data-team-a`에 대한 IAM 정책
- NLB 및 NGINX 인그레스 컨트롤러를 통해 실행 중인 Spark 작업을 모니터링하도록 구성된 Spark History Server Live UI
- 다음 Kubernetes 애드온 배포
    - 관리형 애드온
        - VPC CNI, CoreDNS, KubeProxy, AWS EBS CSI 드라이버
    - 자체 관리형 애드온
        - HA가 있는 Metrics 서버, CoreDNS Cluster proportional Autoscaler, Cluster Autoscaler, Prometheus Server 및 Node Exporter, AWS for FluentBit, EKS용 CloudWatchMetrics


<CollapsibleContent header={<h2><span>EMR Spark Operator</span></h2>}>

Apache Spark용 Kubernetes Operator는 Kubernetes에서 Spark 애플리케이션을 지정하고 실행하는 것을 다른 워크로드를 실행하는 것처럼 쉽고 관용적으로 만드는 것을 목표로 합니다. Spark 애플리케이션을 Spark Operator에 제출하고 EMR 런타임을 활용하기 위해 EMR on EKS ECR 저장소에 호스팅된 Helm 차트를 사용합니다. 차트는 `ECR_URI/spark-operator` 경로에 저장됩니다. ECR 저장소는 이 [링크](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/setting-up-emr-runtime.html)에서 얻을 수 있습니다.

* SparkApplication 객체의 생성, 업데이트 및 삭제 이벤트를 감시하고 감시 이벤트에 따라 동작하는 SparkApplication 컨트롤러
* 컨트롤러로부터 받은 제출을 위해 spark-submit을 실행하는 제출 러너
* Spark 파드를 감시하고 컨트롤러에 파드 상태 업데이트를 보내는 Spark 파드 모니터
* 컨트롤러가 추가한 파드의 어노테이션을 기반으로 Spark 드라이버 및 익스큐터 파드에 대한 커스터마이제이션을 처리하는 Mutating Admission Webhook

</CollapsibleContent>

<CollapsibleContent header={<h2><span>솔루션 배포</span></h2>}>
### 사전 요구 사항:

머신에 다음 도구가 설치되어 있는지 확인하세요.

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### 배포

저장소를 복제합니다.

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

`analytics/terraform/emr-eks-karpenter`로 이동하여 `terraform init`을 실행합니다.

```bash
cd ./data-on-eks/analytics/terraform/emr-eks-karpenter
terraform init
```

:::info
EMR Spark Operator 애드온을 배포하려면 `variables.tf` 파일에서 아래 값을 `true`로 설정해야 합니다.

```hcl
variable "enable_emr_spark_operator" {
  description = "Enable the Spark Operator to submit jobs with EMR Runtime"
  default     = true
  type        = bool
}
```

:::

패턴 배포

```bash
terraform apply
```

적용하려면 `yes`를 입력합니다.

## 리소스 확인

`terraform apply`로 생성된 리소스를 확인해 보겠습니다.

Spark Operator 및 Amazon Managed Service for Prometheus를 확인합니다.

```bash

helm list --namespace spark-operator -o yaml

aws amp list-workspaces --alias amp-ws-emr-eks-karpenter

```

`Prometheus`, `Vertical Pod Autoscaler`, `Metrics Server` 및 `Cluster Autoscaler`에 대한 네임스페이스 `emr-data-team-a` 및 파드 상태를 확인합니다.

```bash
aws eks --region us-west-2 update-kubeconfig --name spark-operator-doeks # EKS 클러스터와 인증하기 위한 k8s 구성 파일 생성

kubectl get nodes # 출력에 EKS 관리형 노드 그룹 노드가 표시됩니다

kubectl get ns | grep emr-data-team # 출력에 데이터 팀용 emr-data-team-a가 표시됩니다

kubectl get pods --namespace=vpa  # 출력에 Vertical Pod Autoscaler 파드가 표시됩니다

kubectl get pods --namespace=kube-system | grep  metrics-server # 출력에 Metric Server 파드가 표시됩니다

kubectl get pods --namespace=kube-system | grep  cluster-autoscaler # 출력에 Cluster Autoscaler 파드가 표시됩니다
```

</CollapsibleContent>

<CollapsibleContent header={<h2><span>Karpenter로 샘플 Spark 작업 실행</span></h2>}>

예제 디렉토리로 이동하여 Spark 작업을 제출합니다.

```bash
cd data-on-eks/analytics/terraform/emr-eks-karpenter/examples/emr-spark-operator
kubectl apply -f pyspark-pi-job.yaml
```

아래 명령을 사용하여 작업 상태를 모니터링합니다.
Karpenter에 의해 트리거된 새 노드가 표시되고 YuniKorn이 이 노드에 드라이버 파드 1개와 익스큐터 파드 2개를 예약합니다.

```bash
kubectl get pods -n spark-team-a -w
```
</CollapsibleContent>

<CollapsibleContent header={<h2><span>정리</span></h2>}>

이 스크립트는 모든 리소스가 올바른 순서로 삭제되도록 `-target` 옵션을 사용하여 환경을 정리합니다.

```bash
cd analytics/terraform/emr-eks-karpenter && chmod +x cleanup.sh
./cleanup.sh
```
</CollapsibleContent>

:::caution

AWS 계정에 원치 않는 비용이 청구되지 않도록 이 배포 중에 생성된 모든 AWS 리소스를 삭제하세요.

:::
