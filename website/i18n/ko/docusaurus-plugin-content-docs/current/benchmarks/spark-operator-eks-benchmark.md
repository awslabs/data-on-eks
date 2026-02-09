---
sidebar_position: 3
sidebar_label: Kubeflow Spark Operator 벤치마크
---

# Kubeflow Spark Operator 벤치마크
이 문서는 Amazon EKS에서 Kubeflow Spark Operator의 규모 테스트를 수행하기 위한 포괄적인 가이드입니다. 주요 목표는 수천 개의 작업을 제출하고 스트레스 상황에서의 동작을 분석하여 Spark Operator의 성능, 확장성 및 안정성을 평가하는 것입니다.

이 가이드는 다음에 대한 단계별 접근 방식을 제공합니다:

- 대규모 작업 제출을 위한 **Spark Operator 구성** 단계
- 성능 최적화를 위한 **인프라 설정** 수정
- **Locust**를 사용한 부하 테스트 실행 세부 사항
- Spark Operator 메트릭과 Kubernetes 메트릭 모니터링을 위한 **Grafana 대시보드**

### 벤치마크 테스트가 필요한 이유
벤치마크 테스트는 대규모 작업 제출을 처리할 때 Spark Operator의 효율성과 신뢰성을 평가하는 중요한 단계입니다. 이러한 테스트는 다음에 대한 귀중한 인사이트를 제공합니다:

- **성능 병목 현상 식별:** 시스템이 높은 부하에서 어려움을 겪는 영역을 정확히 파악합니다.
- **최적화된 리소스 활용 보장:** CPU, 메모리 및 기타 리소스가 효율적으로 사용되도록 합니다.
- **높은 워크로드에서 시스템 안정성 평가:** 극한 조건에서 시스템이 성능과 신뢰성을 유지하는 능력을 테스트합니다.

이러한 테스트를 수행함으로써 Spark Operator가 실제 고수요 시나리오를 효과적으로 처리할 수 있음을 보장할 수 있습니다.

### 사전 요구 사항

- 벤치마크 테스트를 실행하기 전에 [여기](https://awslabs.github.io/data-on-eks/docs/blueprints/data-analytics/spark-operator-yunikorn#deploy) 지침에 따라 **Spark Operator** EKS 클러스터를 배포했는지 확인하세요.
- 필요한 AWS 리소스 및 EKS 구성 수정 권한에 대한 액세스.
- 부하 테스트를 위한 **Terraform**, **Kubernetes**, **Locust**에 대한 친숙함.

### 클러스터 업데이트

벤치마크 테스트를 위해 클러스터를 준비하려면 다음 수정 사항을 적용하세요:

**1단계: Spark Operator Helm 구성 업데이트**

[analytics/terraform/spark-k8s-operator/addons.tf](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/addons.tf) 파일에서 지정된 Spark Operator Helm 값의 주석을 해제하세요(`-- Start`에서 `-- End` 섹션까지). 그런 다음 terraform apply를 실행하여 변경 사항을 적용하세요.

이러한 업데이트는 다음을 보장합니다:
- Spark Operator와 webhook Pod가 Karpenter를 사용하여 전용 `c5.9xlarge` 인스턴스에 배포됩니다.
- 인스턴스는 `6000`개 애플리케이션 제출을 처리하기 위한 `36 vCPU`를 제공합니다.
- Controller Pod와 Webhook Pod 모두에 높은 CPU 및 메모리 리소스가 할당됩니다.

업데이트된 구성은 다음과 같습니다:

```yaml
enable_spark_operator = true
  spark_operator_helm_config = {
    version = "2.1.0"
    timeout = "120"
    values = [
      <<-EOT
        controller:
          replicas: 1
          # -- 조정 동시성, 더 높은 값은 메모리 사용량을 증가시킬 수 있습니다.
          # -- 인스턴스에서 더 많은 코어를 활용하기 위해 10에서 20으로 증가
          workers: 20
          # -- YuniKorn이 배포될 때 True로 변경
          batchScheduler:
            enable: false
            # default: "yunikorn"
#  -- 시작: Spark Operator 규모 테스트를 위해 코드에서 이 섹션의 주석 해제
          # -- Spark Operator는 CPU 바운드이므로 대규모 작업 제출 처리를 위해 더 많은 CPU 추가 또는 컴퓨팅 최적화 인스턴스 사용
          nodeSelector:
            NodeGroupType: spark-operator-benchmark
          resources:
            requests:
              cpu: 33000m
              memory: 50Gi
        webhook:
          nodeSelector:
            NodeGroupType: spark-operator-benchmark
          resources:
            requests:
              cpu: 1000m
              memory: 10Gi
#  -- 종료: Spark Operator 규모 테스트를 위해 코드에서 이 섹션의 주석 해제
        spark:
          jobNamespaces:
            - default
            - spark-team-a
            - spark-team-b
            - spark-team-c
          serviceAccount:
            create: false
          rbac:
            create: false
        prometheus:
          metrics:
            enable: true
            port: 8080
            portName: metrics
            endpoint: /metrics
            prefix: ""
          podMonitor:
            create: true
            labels: {}
            jobLabel: spark-operator-podmonitor
            podMetricsEndpoint:
              scheme: http
              interval: 5s
      EOT
    ]
  }
```

**2단계: 대규모 클러스터를 위한 Prometheus 모범 사례**

- 200개 노드에 걸쳐 32,000개 이상의 Pod를 효율적으로 모니터링하려면 Prometheus가 증가된 CPU 및 메모리 할당이 있는 전용 노드에서 실행되어야 합니다. Prometheus Helm 차트에서 NodeSelector를 사용하여 Prometheus가 코어 노드 그룹에 배포되도록 하세요. 이렇게 하면 워크로드 Pod의 간섭을 방지할 수 있습니다.
- 규모에서 **Prometheus**는 상당한 CPU와 메모리를 소비할 수 있으므로 전용 인프라에서 실행하면 앱과 경쟁하지 않습니다. 노드 선택기나 테인트를 사용하여 모니터링 구성 요소(Prometheus, Grafana 등)에만 노드 또는 노드 풀을 할당하는 것이 일반적입니다.
- Prometheus는 메모리 집약적이며 수백 또는 수천 개의 Pod를 모니터링할 때 상당한 CPU도 요구합니다.
- 전용 리소스 할당(그리고 Kubernetes 우선순위 클래스나 QoS를 사용하여 Prometheus를 선호)하면 스트레스 상황에서 모니터링을 안정적으로 유지하는 데 도움이 됩니다.
- 전체 관측 스택(메트릭, 로그, 추적)은 규모에서 인프라 리소스의 약 1/3을 소비할 수 있으므로 그에 따라 용량을 계획하세요.
- 처음부터 충분한 메모리와 CPU를 할당하고 Prometheus에 대해 엄격한 낮은 제한 없이 요청을 선호하세요. 예를 들어, Prometheus가 약 8 GB가 필요하다고 예상되면 4 GB로 제한하지 마세요. Prometheus용으로 전체 노드나 노드의 큰 부분을 예약하는 것이 좋습니다.

**3단계: 높은 Pod 밀도를 위한 VPC CNI 구성:**

[analytics/terraform/spark-k8s-operator/eks.tf](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/eks.tf)를 수정하여 `vpc-cni` 애드온에서 `prefix delegation`을 활성화하세요. 이렇게 하면 노드당 Pod 용량이 `110에서 200`으로 증가합니다.

```hcl
cluster_addons = {
  vpc-cni = {
    configuration_values = jsonencode({
      env = {
        ENABLE_PREFIX_DELEGATION = "true"
        WARM_PREFIX_TARGET       = "1"
      }
    })
  }
}
```

**중요 참고:** 이러한 변경 후 `terraform apply`를 실행하여 VPC CNI 구성을 업데이트하세요.

**4단계: Spark 부하 테스트를 위한 전용 노드 그룹 생성**

Spark 작업 Pod를 배치하기 위해 **spark_operator_bench**라는 전용 관리형 노드 그룹을 생성했습니다. Spark 부하 테스트 Pod용으로 `m6a.4xlarge` 인스턴스로 `200노드` 관리형 노드 그룹을 구성했습니다. 사용자 데이터는 `노드당 최대 220개 Pod`를 허용하도록 수정되었습니다.

**참고:** 이 단계는 정보 제공용이며 수동으로 변경 사항을 적용할 필요가 없습니다.

```hcl
spark_operator_bench = {
  name        = "spark_operator_bench"
  description = "x86 또는 ARM을 사용하는 EBS가 있는 Spark Operator 벤치마크용 관리형 노드 그룹"

  min_size     = 0
  max_size     = 200
  desired_size = 0
  ...

  cloudinit_pre_nodeadm = [
    {
      content_type = "application/node.eks.aws"
      content      = <<-EOT
        ---
        apiVersion: node.eks.aws/v1alpha1
        kind: NodeConfig
        spec:
          kubelet:
            config:
              maxPods: 220
      EOT
    }
  ]
...

}
```

**5단계: 노드 그룹 최소 크기를 200으로 수동 업데이트**

:::caution

200개 노드를 실행하면 상당한 비용이 발생할 수 있습니다. 이 테스트를 독립적으로 실행할 계획이라면 예산 타당성을 보장하기 위해 사전에 비용을 신중하게 추정하세요.

:::

처음에는 `min_size = 0`으로 설정합니다. 부하 테스트를 시작하기 전에 AWS 콘솔에서 `min_size`와 `desired_size`를 `200`으로 업데이트하세요. 이렇게 하면 부하 테스트에 필요한 모든 노드가 미리 생성되어 모든 DaemonSet이 실행됩니다.

### 부하 테스트 구성 및 실행

대규모 동시 작업 제출을 시뮬레이션하기 위해 Spark Operator 템플릿을 동적으로 생성하고 여러 사용자를 시뮬레이션하여 동시에 작업을 제출하는 **Locust** 스크립트를 개발했습니다.

**1단계: Python 가상 환경 설정**
로컬 머신(Mac 또는 데스크톱)에서 Python 가상 환경을 생성하고 필요한 종속성을 설치하세요:

```
cd analytics/terraform/spark-k8s-operator/examples/benchmark/spark-operator-benchmark-kit
python3.12 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

**2단계: 부하 테스트 실행**
다음 명령을 실행하여 부하 테스트를 시작하세요:

```sh
locust --headless --only-summary -u 3 -r 1 \
--job-limit-per-user 2000 \
--jobs-per-min 1000 \
--spark-namespaces spark-team-a,spark-team-b,spark-team-c
```

이 명령은:
- **3명의 동시 사용자**로 테스트를 시작합니다.
- 각 사용자는 **분당 1000개 작업** 비율로 **2000개 작업**을 제출합니다.
- 이 명령으로 총 **6000개 작업**이 제출됩니다. 각 Spark 작업은 **6개 Pod**(1개 드라이버와 5개 실행기 Pod)로 구성됩니다.
- **200개 노드**에 걸쳐 **3개 네임스페이스**를 사용하여 **36,000개 Pod**를 생성합니다.

- Locust 스크립트는 다음 위치의 Spark 작업 템플릿을 사용합니다: `analytics/terraform/spark-k8s-operator/examples/benchmark/spark-operator-benchmark-kit/spark-app-with-webhook.yaml`.

- Spark 작업은 지정된 기간 동안 대기하는 간단한 `spark-pi-sleep.jar`를 사용합니다. 테스트 이미지는 다음에서 사용할 수 있습니다: `public.ecr.aws/data-on-eks/spark:pi-sleep-v0.0.2`

### 결과 확인
부하 테스트는 약 1시간 동안 실행됩니다. 이 시간 동안 Grafana를 사용하여 Spark Operator 메트릭, 클러스터 성능 및 리소스 활용도를 모니터링할 수 있습니다. 모니터링 대시보드에 액세스하려면 아래 단계를 따르세요:

**1단계: Grafana 서비스 포트 포워딩**
다음 명령을 실행하여 로컬 포트 포워딩을 생성하고 로컬 머신에서 Grafana에 액세스할 수 있게 하세요:

```sh
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n kube-prometheus-stack
```
이렇게 하면 로컬 시스템의 포트 3000이 클러스터 내부의 Grafana 서비스에 매핑됩니다.

**2단계: Grafana 액세스**
Grafana에 로그인하려면 관리자 자격 증명이 저장된 시크릿 이름을 검색하세요:

```bash
terraform output grafana_secret_name
```

그런 다음 검색된 시크릿 이름을 사용하여 AWS Secrets Manager에서 자격 증명을 가져오세요:

```bash
aws secretsmanager get-secret-value --secret-id <grafana_secret_name_output> --region $AWS_REGION --query "SecretString" --output text
```

**3단계: Grafana 대시보드 액세스**
1. 웹 브라우저를 열고 [http://localhost:3000](http://localhost:3000) 으로 이동합니다.
2. 사용자 이름을 `admin`으로 입력하고 이전 명령에서 검색한 비밀번호를 입력합니다.
3. Spark Operator 부하 테스트 대시보드로 이동하여 시각화하세요:

- 제출된 Spark 작업 수.
- 클러스터 전체 CPU 및 메모리 소비.
- Pod 스케일링 동작 및 리소스 할당.

## 결과 요약

:::tip

자세한 분석은 [Kubeflow Spark Operator 웹사이트](https://www.kubeflow.org/docs/components/spark-operator/overview/)를 참조하세요.

:::

**CPU 활용도:**

- Spark Operator 컨트롤러 Pod는 CPU 바운드로, 피크 처리 시 36개 코어 모두를 활용합니다.
- CPU 제약이 작업 처리 속도를 제한하여 컴퓨팅 파워가 확장성의 핵심 요소가 됩니다.

**메모리 사용량:**
- 메모리 소비는 처리된 애플리케이션 수에 관계없이 안정적으로 유지됩니다.
- 이는 메모리가 병목이 아니며 RAM을 늘려도 성능이 향상되지 않음을 나타냅니다.

**작업 처리 속도:**
- Spark Operator는 분당 약 130개 앱을 처리합니다.
- 처리 속도는 CPU 제한으로 제한되어 추가 컴퓨팅 리소스 없이는 더 이상 확장이 불가능합니다.

**작업 처리 시간:**
- 2,000개 애플리케이션 처리에 약 15분.
- 4,000개 애플리케이션 처리에 약 30분.
- 이 수치는 관찰된 분당 130개 앱 처리 속도와 일치합니다.

**작업 대기열 기간 메트릭 신뢰성:**
- 기본 작업 대기열 기간 메트릭은 16분을 초과하면 신뢰할 수 없게 됩니다.
- 높은 동시성에서 이 메트릭은 대기열 처리 시간에 대한 정확한 인사이트를 제공하지 못합니다.

**API 서버 성능 영향:**
- 높은 워크로드 조건에서 Kubernetes API 요청 기간이 크게 증가합니다.
- 이는 Spark Operator 자체의 제한이 아니라 Spark가 실행기 Pod를 자주 쿼리하기 때문입니다.
- 증가된 API 서버 부하는 클러스터 전체의 작업 제출 지연 시간과 모니터링 성능에 영향을 미칩니다.

## 정리

**1단계: 노드 그룹 축소**

불필요한 비용을 피하려면 먼저 **spark_operator_bench** 노드 그룹의 최소 및 원하는 노드 수를 0으로 설정하여 축소하세요:

1. AWS 콘솔에 로그인합니다.
2. EKS 섹션으로 이동합니다.
3. **spark_operator_bench** 노드 그룹을 찾아 선택합니다.
4. 노드 그룹을 편집하고 Min Size와 Desired Size를 0으로 업데이트합니다.
5. 변경 사항을 저장하여 노드를 축소합니다.

**2단계: 클러스터 삭제**
노드가 축소되면 다음 스크립트를 사용하여 클러스터 해제를 진행할 수 있습니다:

```sh
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator && chmod +x cleanup.sh
./cleanup.sh
```
