---
sidebar_position: 2
sidebar_label: Trino on EKS 모범 사례
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '@site/src/components/CollapsibleContent';

# Trino on EKS 모범 사례
[Trino](https://trino.io/)를 [Amazon Elastic Kubernetes Service](https://aws.amazon.com/eks/)(EKS)에 배포하면 클라우드 네이티브 확장성과 함께 분산 쿼리 처리를 제공합니다. 조직은 [Karpenter](https://karpenter.sh/)를 사용하여 Trino의 강력함과 EKS의 확장성 및 유연성을 결합하면서 워크로드 요구 사항에 맞는 특정 컴퓨팅 인스턴스와 스토리지 솔루션을 선택하여 비용을 최적화할 수 있습니다.

이 가이드는 EKS에서 Trino를 배포하기 위한 처방적 지침을 제공합니다. 최적의 구성, 효과적인 리소스 관리 및 비용 절감 전략을 통해 높은 확장성과 낮은 비용을 달성하는 데 중점을 둡니다. Hive 및 Iceberg와 같은 인기 있는 파일 형식에 대한 상세한 구성을 다룹니다. 이러한 구성은 원활한 데이터 액세스를 보장하고 성능을 최적화합니다. 우리의 목표는 효율적이고 비용 효과적인 Trino 배포를 설정하는 데 도움을 주는 것입니다.

EKS에서 Trino를 배포하기 위한 [배포 준비가 완료된 블루프린트](https://awslabs.github.io/data-on-eks/docs/blueprints/distributed-databases/trino)가 있으며, 여기서 논의된 모범 사례가 통합되어 있습니다.

이러한 모범 사례를 참조하여 근거와 추가 최적화/미세 조정에 대해 알아보세요.

<CollapsibleContent header={<h2><span>Trino 기본 사항</span></h2>}>
이 섹션에서는 Trino의 핵심 아키텍처, 기능, 사용 사례 및 에코시스템에 대한 참조와 함께 다룹니다.

### 핵심 아키텍처

Trino는 고성능 분석 및 빅데이터 처리를 위해 설계된 강력한 분산 SQL 쿼리 엔진입니다. 주요 구성 요소는 다음과 같습니다:

- 분산 코디네이터-워커 모델
- 인메모리 처리 아키텍처
- MPP(Massively Parallel Processing) 실행
- 동적 쿼리 최적화 엔진
- 자세한 내용은 [여기](https://trino.io/docs/current/overview/concepts.html#architecture)에서 확인할 수 있습니다.

### 주요 기능

Trino는 데이터 처리 기능을 향상시키는 여러 기능을 제공합니다.

- 쿼리 연합(Query Federation)
- 여러 데이터 소스에 대한 동시 쿼리
- 이기종 데이터 환경 지원
- 실시간 데이터 처리 기능
- 다양한 데이터 소스를 위한 통합 SQL 인터페이스

### 커넥터 에코시스템

Trino는 적절한 커넥터로 카탈로그를 구성하고 표준 SQL 클라이언트를 통해 연결하여 다양한 데이터 소스에 대한 SQL 쿼리를 가능하게 합니다.

- 다음을 포함한 50개 이상의 [프로덕션 준비 커넥터](https://trino.io/ecosystem/data-source):
  - 클라우드 스토리지(AWS S3)
  - 관계형 데이터베이스(PostgreSQL, MySQL, SQL Server)
  - NoSQL 저장소(MongoDB, Cassandra)
  - 데이터 레이크(Apache Hive, Apache Iceberg, Delta Lake)
  - 스트리밍 플랫폼(Apache Kafka)

### 쿼리 최적화

- 고급 비용 기반 옵티마이저
- 동적 필터링
- 적응형 쿼리 실행
- 정교한 메모리 관리
- 컬럼형 처리 지원
- [여기](https://trino.io/docs/current/optimizer.html)에서 자세히 읽어보세요.

### 사용 사례

Trino는 다음과 같은 주요 사용 사례를 다룹니다:

- 대화형 분석
- 데이터 레이크 쿼리
- ETL 처리
- 애드혹 분석
- 실시간 대시보드
- 크로스 플랫폼 데이터 연합

</CollapsibleContent>

<CollapsibleContent header={<h2><span>EKS 클러스터 구성</span></h2>}>

## EKS 클러스터 생성

- 클러스터 범위: 이중화를 위해 여러 AZ에 EKS 클러스터를 배포합니다.
- 컨트롤 플레인 로깅: 감사 및 진단 목적으로 컨트롤 플레인 로깅을 활성화합니다.
- Kubernetes 버전: 최신 EKS 버전 사용

### EKS 애드온

오픈 소스 Helm 차트 대신 EKS API를 통해 [Amazon EKS 관리형 애드온](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)을 사용하세요. EKS 팀이 이러한 애드온을 유지 관리하고 EKS 클러스터 버전에 맞게 자동으로 업데이트합니다.
- VPC CNI: IP 주소 사용을 최적화하기 위해 사용자 정의 설정으로 [Amazon VPC CNI](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html) 플러그인을 설치하고 구성합니다.
- CoreDNS: 내부 DNS 확인을 위해 CoreDNS가 배포되었는지 확인합니다.
- KubeProxy: Kubernetes 네트워크 프록시 기능을 위해 KubeProxy를 배포합니다.

:::tip
EKS 클러스터를 시작하고 Trino를 배포할 계획이라면 이러한 구성 세부 사항을 따르세요.
:::

### 프로비저닝
Karpenter 또는 [관리형 노드 그룹](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html)(MNG)을 사용하여 기본 컴퓨팅 리소스를 프로비저닝하고 확장할 수 있습니다.

#### 필수 구성 요소를 위한 관리형 노드 그룹
MNG는 시작 템플릿을 사용하고, Auto Scaling 그룹을 활용하며, Kubernetes Cluster Autoscaler와 통합됩니다.

#### 온디맨드 노드 그룹
- Trino 코디네이터와 최소 하나의 워커와 같은 중요한 구성 요소를 실행하기 위해 온디맨드 인스턴스용 관리형 노드 그룹을 설정합니다. 이 설정은 핵심 운영의 안정성과 신뢰성을 보장합니다.
  - **사용 사례**: Trino 코디네이터와 필수 워커 노드를 실행하는 데 이상적입니다.

#### 스팟 인스턴스 노드 그룹
- 비용 효율적으로 추가 워커 노드를 추가하기 위해 스팟 인스턴스용 관리형 노드 그룹을 구성합니다. 스팟 인스턴스는 비용을 줄이면서 가변적인 워크로드를 처리하는 데 적합합니다.
  - **사용 사례**: SLA 바인딩이 없는 비용에 민감한 작업에 대해 워커 노드를 확장하는 데 가장 적합합니다.

#### 추가 구성
- **단일 AZ 배포**: 데이터 전송 비용을 최소화하고 지연 시간을 줄이기 위해 단일 가용 영역 내에 노드 그룹을 배포합니다.
- **인스턴스 유형**: 메모리 집약적 워크로드를 위한 r6g.4xlarge와 같이 워크로드 요구 사항에 맞는 인스턴스 유형을 선택합니다.

### 노드 스케일링을 위한 Karpenter
Karpenter는 60초 이내에 노드를 프로비저닝하고, 혼합 인스턴스/아키텍처를 지원하며, 네이티브 EC2 API를 활용하고, 동적 리소스 할당을 제공합니다.

#### 노드 풀 설정
Karpenter를 사용하여 스팟 및 온디맨드 인스턴스를 모두 포함하는 동적 노드 풀을 생성합니다. Trino 워커와 코디네이터가 필요에 따라 적절한 인스턴스 유형(온디맨드 또는 스팟)에서 시작되도록 레이블을 적용합니다.
<details>
  <summary> EC2 Graviton 인스턴스를 사용한 Karpenter 노드 풀 예제</summary>
  ```
  apiVersion: karpenter.sh/v1
  kind: NodePool
  metadata:
  name: trino-sql-karpenter
  spec:
  template:
  metadata:
  labels:
  NodePool: trino-sql-karpenter
  spec:
  nodeClassRef:
  group: karpenter.k8s.aws
  kind: EC2NodeClass
  name: trino-karpenter
  requirements:
  - key: "karpenter.sh/capacity-type"
  operator: In
  values: ["on-demand"]
  - key: "kubernetes.io/arch"
  operator: In
  values: ["arm64"]
  - key: "karpenter.k8s.aws/instance-category"
  operator: In
  values: ["r"]
  - key: "karpenter.k8s.aws/instance-family"
  operator: In
  values: ["r6g", "r7g", "r8g"]
  - key: "karpenter.k8s.aws/instance-size"
  operator: In
  values: ["2xlarge", "4xlarge"]
  disruption:
  consolidationPolicy: WhenEmptyOrUnderutilized
  consolidateAfter: 60s
  limits:
  cpu: "1000"
  memory: 1000Gi
  weight: 100
  ```
</details>

Karpenter 노드 풀 설정의 예는 [DoEKS 저장소](https://github.com/awslabs/data-on-eks/blob/f8dda1ae530902b77ee123661265caa09d97969b/distributed-databases/trino/karpenter.tf#L100)와 [EC2 노드 클래스 구성](https://github.com/awslabs/data-on-eks/blob/f8dda1ae530902b77ee123661265caa09d97969b/distributed-databases/trino/karpenter.tf#L65)에서도 볼 수 있습니다.

### 혼합 인스턴스
워크로드 요구 사항에 따라 작은 것부터 큰 것까지 다양한 인스턴스 크기에 대한 액세스를 보장하고 유연성을 향상시키기 위해 동일한 인스턴스 풀 내에서 혼합 인스턴스 유형을 구성합니다.


:::tip[주요 권장 사항]
:::
- Karpenter 사용: Trino 클러스터의 더 나은 스케일링과 간소화된 관리를 위해 Karpenter 사용을 선호합니다. 더 빠른 노드 프로비저닝, 혼합 인스턴스 유형에 대한 향상된 유연성, 더 나은 리소스 효율성을 제공합니다. Karpenter는 MNG보다 우수한 스케일링 기능을 제공하여 분석 애플리케이션에서 보조(워커) 노드를 스케일링하는 데 선호되는 선택입니다.
- 전용 노드: 사용 가능한 리소스를 완전히 활용하기 위해 노드당 하나의 Trino Pod를 배포합니다.
- DaemonSet 리소스 할당: 노드 안정성을 유지하기 위해 필수 시스템 DaemonSet에 충분한 CPU와 메모리를 예약합니다.
- 코디네이터 배치: 신뢰성을 보장하기 위해 항상 온디맨드 노드에서 Trino 코디네이터를 실행합니다.
- 워커 분산: 비용 효율성과 가용성의 균형을 맞추기 위해 워커 노드에 온디맨드 및 스팟 인스턴스를 혼합 사용합니다.
- 관리형 노드 그룹 사용: MNG는 워크로드의 복원력 목적의 구성 요소와 관측성 도구와 같은 클러스터의 다른 구성 요소에 사용해야 합니다.
</CollapsibleContent>

<CollapsibleContent header={<span><h2>EKS에서 Trino 설정</h2></span>}>
Helm은 EKS에서 Trino 배포를 간소화합니다. 구성 관리를 위해 [공식 Helm 차트](https://github.com/trinodb/charts) 또는 커뮤니티 차트를 사용하여 Helm을 통해 설치하는 것을 권장합니다.

## 설정

* 공식 Helm 차트 또는 커뮤니티 차트를 사용하여 Trino 설치
* 각 클러스터(ETL, 대화형, BI)에 대해 별도의 Helm 릴리스 생성

### 구성 단계

* 클러스터별로 고유한 `values.yaml` 파일 정의
* Pod 리소스 구성:
  * CPU/메모리 요청 설정
  * CPU/메모리 제한 설정
  * 코디네이터 리소스 지정
  * 워커 리소스 지정
* Pod 스케줄링 설정:
  * nodeSelector 구성
  * 어피니티 규칙 구성

### 배포

각 워크로드 유형에 대해 해당 값 파일과 함께 별도의 Helm 구성을 사용합니다. 예를 들어:
```
# ETL 클러스터
helm install etl-trino trino-chart -f etl-values.yaml

# 대화형 클러스터
helm install interactive-trino trino-chart -f interactive-values.yaml

# BI 클러스터
helm install analytics-trino trino-chart -f analytics-values.yaml
```

Trino는 MPP(Massively Parallel Processing) 아키텍처를 가진 분산 쿼리 엔진으로 작동합니다. 시스템은 코디네이터와 여러 워커라는 두 가지 주요 구성 요소로 구성됩니다.

#### 코디네이터는 다음을 수행하는 중앙 관리 노드 역할을 합니다:

- 들어오는 쿼리 처리
- 쿼리 실행 구문 분석 및 계획
- 워크로드 스케줄링 및 모니터링
- 워커 노드 관리
- 최종 사용자를 위한 결과 통합

#### 워커는 다음을 수행하는 실행 노드입니다:

- 할당된 작업 실행
- 다양한 소스의 데이터 처리
- 중간 결과 공유
- 데이터 소스 커넥터와 통신
- 검색 서비스를 통해 코디네이터에 등록

EKS에 배포되면 코디네이터와 워커 구성 요소 모두 EKS 클러스터 내에서 Pod로 실행됩니다. 시스템은 카탈로그에 스키마와 참조를 저장하여 특수 커넥터를 통해 다양한 데이터 소스에 액세스할 수 있게 합니다. 이 아키텍처를 통해 Trino는 여러 노드에 쿼리 처리를 분산하여 대규모 데이터 운영에 대한 성능과 확장성을 개선할 수 있습니다.


### Trino 코디네이터 구성

코디네이터는 쿼리 계획 및 오케스트레이션을 처리하며, 워커 노드보다 적은 리소스가 필요합니다. 코디네이터 Pod는 데이터 처리보다는 쿼리 계획에 집중하므로 워커보다 적은 리소스가 필요합니다. 다음은 고가용성과 효율적인 리소스 사용을 위한 주요 구성 설정입니다.

#### 쿼리 계획 및 조정 작업에 충분한 리소스 구성

* 메모리: 40Gi
* CPU: 4-6 코어

#### 고가용성 설정

* 레플리카: 2개의 코디네이터 인스턴스
* Pod Disruption Budget: 유지 관리 중 코디네이터 가용성 보장
* Pod Anti-Affinity: 별도의 노드에 코디네이터 스케줄링
* 내결함성을 개선하기 위해 여러 코디네이터가 동일한 노드에서 실행되지 않도록 항상 Pod Anti-Affinity를 구성합니다.

### Exchange Manager 구성

- 쿼리 실행 중 중간 데이터를 처리합니다.
- 내결함성과 확장성을 개선하기 위해 데이터를 외부 스토리지로 오프로드합니다.

#### S3로 Exchange Manager 구성

#### S3 설정
- `s3://your-exchange-bucket`으로 설정
- `exchange.s3.region`: AWS 리전으로 설정
- `exchange.s3.iam-role`: S3 액세스를 위해 IAM 역할 사용
- `exchange.s3.max-error-retries`: 복원력을 위해 증가
- `exchange.s3.upload.part-size`: 성능 최적화를 위해 조정(예: 64MB)
#### 권장 사항
- 보안 - IAM 역할이 필요한 최소 권한을 갖도록 보장
- 성능 - `upload.part-size` 및 동시 연결 조정
- 비용 관리 - S3 비용 모니터링 및 수명 주기 정책 구현

## Trino Pod 리소스 요청 vs 제한

Kubernetes는 리소스 요청과 제한을 사용하여 컨테이너 리소스를 효과적으로 관리합니다. 다음은 다양한 Trino Pod 유형에 대해 최적화하는 방법입니다:

### 워커 Pod

- resources.requests를 resources.limits보다 약간 낮게 설정합니다(예: 10-20% 차이).
- 이 접근 방식은 리소스 고갈을 방지하면서 효율적인 리소스 할당을 보장합니다.

### 코디네이터 Pod

- 리소스 제한을 요청보다 20-30% 높게 구성합니다.
- 이 전략은 예측 가능한 스케줄링을 유지하면서 버스트 용량을 제공하여 가끔 발생하는 사용량 급증에 대응합니다.

### 이 전략의 이점

- 스케줄링 개선: Kubernetes가 정확한 리소스 요청을 기반으로 정보에 입각한 결정을 내려 Pod 배치를 최적화합니다.
- 리소스 보호: 잘 정의된 제한은 리소스 고갈을 방지하여 다른 클러스터 워크로드를 보호합니다.
- 버스트 처리: 더 높은 제한은 일시적인 리소스 급증을 원활하게 관리할 수 있게 합니다.
- 안정성 향상: 적절한 리소스 할당은 Pod 퇴출 위험을 줄이고 전체 클러스터 안정성을 개선합니다.


### 오토스케일링 구성

Trino 클러스터에서 이벤트 기반 스케일링을 통한 동적 워크로드 관리를 위해 [KEDA](https://keda.sh/)를 구현하는 것을 권장합니다. Amazon EKS에서 KEDA와 Karpenter의 조합은 스케일링 문제를 해결하는 강력한 오토스케일링 솔루션을 만듭니다. KEDA는 실시간 메트릭을 기반으로 세밀한 Pod 스케일링을 관리하고, Karpenter는 효율적인 노드 프로비저닝을 처리합니다. 함께 수동 스케일링 프로세스를 대체하여 성능 개선과 비용 최적화를 모두 제공합니다.

#### KEDA 구성
- 클러스터에 KEDA Helm 릴리스 추가
- Trino Helm 값에 JVM/JMX Exporter 구성 추가, serviceMonitor 활성화
```
configProperties: |-
      hostPort: localhost:{{- .Values.jmx.registryPort }}
      startDelaySeconds: 0
      ssl: false
      lowercaseOutputName: false
      lowercaseOutputLabelNames: false
      whitelistObjectNames: ["trino.execution:name=QueryManager","trino.execution:name=SqlTaskManager","trino.execution.executor:name=TaskExecutor","trino.memory:name=ClusterMemoryManager","java.lang:type=Runtime","trino.memory:type=ClusterMemoryPool,name=general","java.lang:type=Memory","trino.memory:type=MemoryPool,name=general"]
      autoExcludeObjectNameAttributes: true
      excludeObjectNameAttributes:
        "java.lang:type=OperatingSystem":
          - "ObjectName"
        "java.lang:type=Runtime":
          - "ClassPath"
          - "SystemProperties"
      rules:
      - pattern: ".*"
```
- CPU 및 QueuedQueries를 추적하는 trino용 KEDA scaledObject 배포. 여기서 'target' CPU 백분율은 Graviton 인스턴스의 물리적 코어를 활용하기 위해 85%로 설정됩니다.
```
triggers:
  - type: cpu
    metricType: Utilization
    metadata:
      value: '85'  # Target CPU utilization percentage
  - type: prometheus
    metricType: Value
    metadata:
      serverAddress: http://kube-prometheus-stack-prometheus.kube-prometheus-stack.svc.cluster.local:9090
      threshold: '1'
      metricName: queued_queries
      query: sum by (job) (avg_over_time(trino_execution_QueryManager_QueuedQueries{job="trino"}[1m]))
```

## 파일 캐싱

파일 캐싱은 스토리지 시스템과 쿼리 작업에 세 가지 주요 이점을 제공합니다. 첫째, 동일한 파일의 반복적인 검색을 방지하여 스토리지 부하를 줄입니다. 캐시된 파일은 동일한 워커에서 여러 쿼리에 재사용될 수 있기 때문입니다. 둘째, 반복적인 네트워크 전송을 제거하고 로컬 파일 복사본에 액세스할 수 있게 하여 쿼리 성능을 크게 향상시킬 수 있으며, 이는 원본 스토리지가 다른 네트워크나 리전에 있을 때 특히 유용합니다. 마지막으로, 네트워크 트래픽과 스토리지 액세스를 최소화하여 쿼리 비용을 절감합니다.

다음은 파일 캐싱을 구현하기 위한 기본 구성입니다.

```
fs.cache.enabled=true
fs.cache.directories=/tmp/cache/
fs.cache.preferred-hosts-count=10 # 클러스터 크기에 따라 호스트 수가 결정됩니다. 최적의 성능을 유지하기 위해 호스트 수를 작게 유지하는 것이 좋습니다.
```

:::note
캐시 디렉토리에 로컬 SSD 스토리지가 있는 인스턴스를 구성하여 I/O 속도와 전체 쿼리 성능을 크게 향상시킵니다.
:::

</CollapsibleContent>

<CollapsibleContent header={<h2><span>컴퓨팅, 스토리지 및 네트워킹 모범 사례</span></h2>}>

<CollapsibleContent header={<span><h2>컴퓨팅 모범 사례</h2></span>}>

## 컴퓨팅 선택

Amazon Elastic Compute Cloud(EC2)는 표준, 컴퓨팅 최적화, 메모리 최적화, I/O 최적화 구성을 포함한 인스턴스 패밀리 및 프로세서를 통해 다양한 컴퓨팅 옵션을 제공합니다. [유연한 가격 모델](https://aws.amazon.com/ec2/pricing/)인 온디맨드, Compute Savings Plan, 예약 또는 스팟 인스턴스를 통해 이러한 인스턴스를 구매할 수 있습니다. 적절한 인스턴스 유형을 선택하면 비용을 최적화하고, 성능을 극대화하며, 지속 가능성 목표를 지원할 수 있습니다. EKS를 사용하면 이러한 컴퓨팅 리소스를 워크로드 요구 사항에 정확하게 맞출 수 있습니다. 특히 Trino 분산 클러스터의 경우 컴퓨팅 선택이 클러스터 성능에 직접적인 영향을 미칩니다.

:::tip[주요 권장 사항]
:::
- [AWS Graviton 기반 인스턴스](https://aws.amazon.com/ec2/graviton/) 사용: Graviton 인스턴스는 성능을 개선하면서 인스턴스 비용을 낮추고, 지속 가능성 목표를 달성하는 데도 도움이 됩니다.
- Karpenter 사용: Trino 클러스터의 더 나은 스케일링과 간소화된 관리를 위해 Karpenter 사용을 선호합니다.
- 절감 효과를 극대화하기 위해 스팟 인스턴스를 다양화합니다. [EC2 스팟 모범 사례에서 자세한 내용을 확인할 수 있습니다](https://aws.amazon.com/blogs/compute/best-practices-to-optimize-your-amazon-ec2-spot-instances-usage/). EC2 스팟 인스턴스와 함께 [내결함성 실행](http://localhost:3000/data-on-eks/docs/blueprints/distributed-databases/trino#example-3-optional-fault-tolerant-execution-in-trino) 사용

</CollapsibleContent>

<CollapsibleContent header={<span><h2>네트워킹 모범 사례</h2></span>}>

## 네트워킹 계획

Pod 전반에 걸친 Trino의 분산 특성으로 인해 최적의 성능을 보장하기 위해 네트워킹 모범 사례를 구현해야 합니다. 적절한 구현은 복원력을 개선하고, IP 고갈을 방지하며, Pod 초기화 오류를 줄이고, 지연 시간을 최소화합니다. Pod 네트워킹은 Kubernetes 운영의 핵심을 형성합니다. Amazon EKS는 Pod와 호스트가 네트워크 레이어를 공유하는 언더레이 모드에서 작동하는 VPC CNI 플러그인을 사용합니다. 이를 통해 클러스터와 VPC 환경 모두에서 일관된 IP 주소 지정이 보장됩니다.

### VPC CNI 애드온
Amazon VPC CNI 플러그인은 IP 주소 할당을 효율적으로 관리하도록 사용자 정의할 수 있습니다. 기본적으로 Amazon VPC CNI는 노드당 두 개의 Elastic Network Interface(ENI)를 할당합니다. 이러한 ENI는 특히 더 큰 인스턴스 유형에서 많은 IP 주소를 예약합니다. Trino는 일반적으로 노드당 하나의 Pod와 DaemonSet Pod(로깅 및 네트워킹용)를 위한 몇 개의 IP 주소만 필요하므로, CNI를 구성하여 IP 주소 할당을 제한하고 오버헤드를 줄일 수 있습니다.

VPC CNI 애드온에 대한 다음 설정은 EKS API, Terraform 또는 기타 Infrastructure-as-Code(IaC) 도구를 사용하여 적용할 수 있습니다. 자세한 내용은 공식 문서인 VPC CNI Prefix 및 IP Target을 참조하세요.

### VPC CNI 애드온 구성

필요한 IP 수만 할당하도록 구성을 조정하여 노드당 IP 주소 제한:
- MINIMUM_IP_TARGET: 노드당 예상되는 Pod 수로 설정합니다(예: 30).
- WARM_IP_TARGET: 웜 IP 풀을 최소화하기 위해 1로 설정합니다.
- ENABLE_PREFIX_DELEGATION: 개별 보조 IP 주소 대신 워커 노드에 IP 프리픽스를 할당하여 IP 주소 효율성을 개선합니다. 이 접근 방식은 더 작고 집중된 IP 주소 풀을 활용하여 VPC 내의 네트워크 주소 사용량(NAU)을 줄입니다.

#### 샘플 VPC CNI 구성

```
vpc-cni = {
  preserve = true
  configuration_values = jsonencode({
    env = {
      MINIMUM_IP_TARGET           = "30"
      WARM_IP_TARGET              = "1"
      ENABLE_PREFIX_DELEGATION    = "true"
    }
  })
}
```

:::tip[주요 권장 사항]
:::
<b>프리픽스 위임 활성화:</b> VPC CNI 플러그인은 각 노드에 16개의 IPv4 주소 블록(/28 프리픽스)을 할당하는 프리픽스 위임을 지원합니다. 이 기능은 노드당 필요한 ENI 수를 줄입니다. 프리픽스 위임을 사용하면 EC2 네트워크 주소 사용량(NAU)을 낮추고, 네트워크 관리 복잡성을 줄이며, 운영 비용을 절감할 수 있습니다.

#### 네트워킹 관련 추가 모범 사례는 [네트워킹 가이드](../networking/networking.md)를 참조하세요.

</CollapsibleContent>

<CollapsibleContent header={<span><h2>스토리지 모범 사례</h2></span>}>

이 섹션에서는 EKS에서 Trino와 함께 최적의 스토리지 관리를 위한 AWS 서비스에 중점을 둡니다.

## Amazon S3를 기본 스토리지로

- 자주 액세스하는 Trino 쿼리 데이터에 S3 Standard 사용
- 다양한 액세스 패턴을 가진 데이터에 S3 Intelligent-Tiering 구현
- 저장 데이터에 대해 S3 서버 측 암호화(SSE-S3 또는 SSE-KMS) 활성화
- 적절한 버킷 정책 및 IAM 역할을 통한 액세스 구성
- 더 나은 쿼리 성능을 위해 S3 버킷 프리픽스를 전략적으로 사용
- 쿼리 성능을 개선하기 위해 Trino와 S3 Select 사용


### 코디네이터 및 워커를 위한 EBS 스토리지

- 더 나은 성능/비용 비율을 위해 gp3 EBS 볼륨 사용
- KMS를 사용하여 EBS 암호화 활성화
- 스필(spill) 디렉토리 요구 사항에 따라 EBS 볼륨 크기 조정
- 백업 전략을 위해 EBS 스냅샷 사용 고려

### 성능 최적화

- 특정 워크로드에서 쿼리 성능을 개선하기 위해 S3 Select 구현
- 대규모 데이터셋에 AWS Partition Index 사용
- 모니터링을 위해 CloudWatch에서 S3 요청 메트릭 활성화
- gp3 볼륨에 대한 적절한 읽기/쓰기 IOPS 구성
- 데이터를 효과적으로 파티셔닝하기 위해 S3 프리픽스 사용

### 데이터 수명 주기 관리

- 자동화된 데이터 관리를 위해 S3 수명 주기 정책 구현
- S3 스토리지 클래스를 적절히 사용:
    - 핫 데이터를 위한 Standard
    - 가변 액세스 패턴을 위한 Intelligent-Tiering
    - 덜 자주 액세스하는 데이터를 위한 Standard-IA
- 중요한 데이터셋에 버전 관리 구성

### 비용 최적화

- 스토리지 비용을 최적화하기 위해 S3 스토리지 클래스 분석 사용
- S3 요청 패턴 모니터링 및 최적화
- 오래된 데이터를 더 저렴한 스토리지 티어로 이동하기 위해 S3 수명 주기 정책 구현
- 스토리지 지출을 추적하기 위해 Cost Explorer 사용

### 보안 및 컴플라이언스

- S3 액세스를 위해 VPC 엔드포인트 구현
- 암호화 키 관리를 위해 AWS KMS 사용
- 감사 목적으로 S3 액세스 로깅 활성화
- 적절한 IAM 역할 및 정책 구성
- API 활동 모니터링을 위해 AWS CloudTrail 활성화

:::note
특정 워크로드 특성 및 요구 사항에 따라 이러한 사례를 조정하는 것을 잊지 마세요.
:::

#### S3 관련 모범 사례에 대한 자세한 이해는 [Amazon S3를 사용한 Trino 모범 사례](https://trino.io/assets/blog/trino-fest-2024/aws-s3.pdf)를 참조하세요.

</CollapsibleContent>

</CollapsibleContent>

<CollapsibleContent header={<span><h2>Trino 커넥터 구성</h2></span>}>
Trino는 커넥터라는 특수 어댑터를 통해 데이터 소스에 연결합니다. Hive 및 Iceberg 커넥터를 통해 Trino는 Parquet 및 ORC(Optimized Row Columnar)와 같은 컬럼형 파일 형식을 읽을 수 있습니다. 적절한 커넥터 구성은 최적의 쿼리 성능과 시스템 호환성을 보장합니다.

:::tip[주요 권장 사항]
:::
- **격리**: 다른 데이터 소스 또는 환경에 별도의 카탈로그 사용
- **보안**: 적절한 인증 및 권한 부여 메커니즘 구현
- **성능**: 데이터 형식 및 쿼리 패턴에 따라 커넥터 설정 최적화
- **리소스 관리**: 각 커넥터의 워크로드 요구 사항에 맞게 메모리 및 CPU 설정 조정

Amazon EKS에서 Hive 및 Iceberg와 같은 파일 형식과 Trino를 통합하려면 신중한 구성과 모범 사례 준수가 필요합니다. 커넥터를 올바르게 설정하고 리소스 할당을 최적화하여 데이터 액세스 효율성을 보장합니다. 쿼리 성능 설정을 미세 조정하여 비용을 낮게 유지하면서 높은 확장성을 달성합니다. 이러한 단계는 EKS에서 Trino의 기능을 극대화하는 데 중요합니다. 데이터 볼륨 및 쿼리 복잡성과 같은 요소에 집중하여 특정 워크로드에 맞게 구성을 조정합니다. 최적의 결과를 유지하기 위해 시스템 성능을 지속적으로 모니터링하고 필요에 따라 설정을 조정합니다.

<CollapsibleContent header={<span><h2>Hive</h2></span>}>

## Hive 커넥터 구성

Hive 커넥터를 사용하면 Trino가 HDFS 또는 Amazon S3에 저장된 Parquet, ORC 또는 Avro와 같은 파일 형식을 사용하여 Hive 데이터 웨어하우스에 저장된 데이터를 쿼리할 수 있습니다.

### Hive 구성 파라미터

- **커넥터 이름**: `hive`
- **메타스토어**: AWS Glue Data Catalog를 메타스토어로 사용합니다.
- **파일 형식**: Parquet, ORC, Avro 등 지원.
- **S3 통합**: 데이터 액세스를 위한 S3 권한 구성.

### 샘플 Hive 카탈로그 구성

```
connector.name=hive
hive.metastore=glue
hive.metastore.glue.region=us-west-2
hive.s3.aws-access-key=YOUR_ACCESS_KEY
hive.s3.aws-secret-key=YOUR_SECRET_KEY
hive.s3.iam-role=arn:aws:iam::123456789012:role/YourIAMRole
hive.s3.endpoint=s3.us-west-2.amazonaws.com
hive.s3.path-style-access=true
hive.s3.ssl.enabled=true
hive.security=legacy
```

:::tip[주요 권장 사항]
:::
### 메타스토어 구성

- 확장성과 관리 용이성을 위해 AWS Glue를 Hive 메타스토어로 사용
- `hive.metastore=glue`로 설정하고 리전 지정

### 인증

- S3에 대한 보안 액세스를 위해 IAM 역할(`hive.s3.iam-role`) 사용
- IAM 역할이 필요한 최소 권한을 갖도록 보장

### 성능 최적화

- **Parquet 및 ORC**: 더 나은 압축과 쿼리 성능을 위해 Parquet 또는 ORC와 같은 컬럼형 파일 형식 사용
- **파티셔닝**: 쿼리 스캔 시간을 줄이기 위해 자주 필터링되는 컬럼을 기반으로 테이블 파티셔닝
- **캐싱**:
  - 메타스토어 호출을 줄이기 위해 `hive.metastore-cache-ttl`로 메타데이터 캐싱 활성화
  - 파일 상태 캐싱을 위해 `hive.file-status-cache-size` 및 `hive.file-status-cache-ttl` 구성

### 데이터 압축

- 스토리지 비용을 줄이고 I/O 성능을 개선하기 위해 S3에 저장된 데이터에 대해 압축 활성화

### 보안 고려 사항

- **암호화**: S3에 저장된 데이터에 대해 서버 측 암호화(SSE) 또는 클라이언트 측 암호화 사용

- **액세스 제어**: 필요한 경우 Ranger 또는 AWS Lake Formation을 사용하여 세분화된 액세스 제어 구현

- **SSL/TLS**: 전송 중 데이터를 암호화하기 위해 `hive.s3.ssl.enabled=true` 보장
</CollapsibleContent>

<CollapsibleContent header={<span><h2>Iceberg</h2></span>}>

## Iceberg 커넥터 구성
Iceberg 커넥터를 사용하면 Trino가 스키마 진화 및 숨겨진 파티셔닝과 같은 기능을 지원하며 대규모 분석 데이터셋을 위해 설계된 Apache Iceberg 테이블에 저장된 데이터와 상호 작용할 수 있습니다.

### 구성 파라미터

- **커넥터 이름**: iceberg
- **카탈로그 유형**: AWS Glue 또는 Hive 메타스토어 사용
- **파일 형식**: Parquet, ORC 또는 Avro
- **S3 통합**: Hive 커넥터와 유사하게 S3 설정 구성

### 샘플 Iceberg 카탈로그 구성

```properties
connector.name=iceberg
iceberg.catalog.type=glue
iceberg.file-format=PARQUET
iceberg.catalog.glue.region=us-west-2
iceberg.catalog.glue.iam-role=arn:aws:iam::123456789012:role/YourIAMRole
iceberg.register-table-procedure.enabled=true
hive.s3.aws-access-key=YOUR_ACCESS_KEY
hive.s3.aws-secret-key=YOUR_SECRET_KEY
hive.s3.iam-role=arn:aws:iam::123456789012:role/YourIAMRole
hive.s3.endpoint=s3.us-west-2.amazonaws.com
hive.s3.path-style-access=true
hive.s3.ssl.enabled=true
```

:::tip[주요 권장 사항]
:::

### 카탈로그 구성
- 중앙 집중식 스키마 관리를 위해 AWS Glue를 카탈로그로 사용
- `iceberg.catalog.type=glue`로 설정하고 리전 지정
- Iceberg REST Catalog 프로토콜 사용
 `iceberg.catalog.type=rest`
  `iceberg.rest-catalog.uri=https://iceberg-with-rest:8181/'`

####   파일 형식
- 최적의 성능을 위해 Parquet 또는 ORC 사용
- `iceberg.file-format=PARQUET` 설정

#### 스키마 진화
- Iceberg는 테이블 재작성 없이 스키마 진화를 지원
- 테이블 등록을 허용하기 위해 `iceberg.register-table-procedure.enabled=true` 보장

#### 파티셔닝
- 쿼리 구문을 단순화하고 성능을 개선하기 위해 Iceberg의 숨겨진 파티셔닝 기능 활용

#### 인증
- S3 및 Glue에 대한 보안 액세스를 위해 IAM 역할 사용
- Iceberg 작업에 필요한 권한이 역할에 있는지 확인

### 성능 최적화

#### 스냅샷 관리
- 성능 저하를 방지하기 위해 정기적으로 오래된 스냅샷 만료
- `iceberg.expire-snapshots.min-snapshots-to-keep` 및 `iceberg.expire-snapshots.max-ref-age` 설정 사용

#### 메타데이터 캐싱
- 메타스토어 호출을 줄이기 위해 캐싱 활성화
- 캐싱 기간을 위해 `iceberg.catalog.cache-ttl` 조정

#### 병렬 처리
- 읽기 성능을 최적화하기 위해 분할 크기 및 병렬 처리 설정 구성
- `iceberg.max-partitions-per-scan` 및 `iceberg.max-splits-per-node` 조정

### 보안 고려 사항

#### 데이터 암호화
- 저장 및 전송 중 암호화 구현

#### 액세스 제어
- IAM 정책을 사용하여 세분화된 권한 적용

#### 컴플라이언스
- 스키마 진화 기능 사용 시 데이터 거버넌스 정책 준수 보장

</CollapsibleContent>
</CollapsibleContent>

<CollapsibleContent header={<span><h2>대규모 쿼리 최적화</h2></span>}>

## 가이드

Trino에서 대규모 쿼리를 최적화하기 위한 일반 가이드는 아래에서 찾을 수 있습니다. 자세한 내용은 [쿼리 옵티마이저](https://trino.io/docs/current/optimizer.html)를 참조하세요.

### 메모리 관리
- 컨테이너에서 쿼리 수준까지 적절한 할당 보장
- 최적화된 임계값으로 메모리 스필링 활성화

### 쿼리 최적화
- 더 나은 병렬 처리를 위해 initialHashPartitions 증가
- 자동 조인 분산 및 재정렬 사용
- 효율적인 처리를 위해 분할 배치 크기 최적화

### 리소스 관리
- 최대 리소스 활용을 위해 노드당 하나의 Pod 적용
- 시스템 프로세스를 위한 리소스를 예약하면서 충분한 CPU 할당
- 가비지 컬렉션 설정 최적화

### Exchange 관리
- Exchange 데이터를 위해 최적화된 설정으로 S3 사용
- 동시 연결 증가 및 업로드 파트 크기 조정

:::tip[주요 권장 사항]
:::
- **모니터링**: 실시간 메트릭을 위해 Prometheus 및 Grafana와 같은 도구 사용
- **테스트**: 프로덕션 전에 구성을 검증하기 위해 워크로드/POC 시뮬레이션
- **인스턴스 선택**: 개선된 가격 대비 성능을 위해 최신 세대 Graviton 인스턴스(Graviton3, Graviton4) 고려
- **네트워크 대역폭**: 병목 현상을 방지하기 위해 인스턴스가 적절한 네트워크 대역폭을 제공하는지 확인

</CollapsibleContent>
