---
title: EKS 기반 Kafka
sidebar_position: 4
---
import CollapsibleContent from '@site/src/components/CollapsibleContent';

# Apache Kafka
[Apache Kafka](https://kafka.apache.org/)는 수천 개의 기업에서 고성능 데이터 파이프라인, 스트리밍 분석, 데이터 통합 및 미션 크리티컬 애플리케이션에 사용하는 오픈소스 분산 이벤트 스트리밍 플랫폼입니다. 이 블루프린트는 Zookeeper가 필요 없는 중요한 아키텍처 개선인 **KRaft(Kafka Raft) 모드**를 사용하여 Kafka를 구현합니다.

## KRaft란 무엇이며 왜 사용하는가?
KRaft 모드는 Kafka 배포를 단순화하고 확장성을 향상시키며 전반적인 시스템 성능을 개선합니다. 내장된 합의 프로토콜을 사용함으로써 KRaft는 운영 복잡성을 줄이고 잠재적으로 브로커 시작 시간을 단축하며 메타데이터 작업을 더 잘 처리할 수 있게 합니다. 이러한 아키텍처 전환을 통해 Kafka는 더 큰 클러스터를 더 효율적으로 관리할 수 있어 이벤트 스트리밍 인프라를 간소화하고 미래 확장성 요구에 대비하려는 조직에 매력적인 옵션이 됩니다.

## Apache Kafka용 Strimzi
[Strimzi](https://strimzi.io/)는 다양한 배포 구성에서 Kubernetes에 Apache Kafka 클러스터를 실행하는 방법을 제공합니다. Strimzi는 Operator Pattern을 기반으로 kubectl 및/또는 GitOps를 사용하여 Kubernetes에서 Kafka를 배포하고 관리하기 위한 보안과 간단한 구성을 결합합니다.

버전 `0.32.0`부터 Strimzi는 KRaft를 사용한 Kafka 클러스터 배포를 완벽하게 지원하여 조직이 이 새로운 아키텍처를 더 쉽게 활용할 수 있게 합니다. Strimzi를 사용하면 커스텀 리소스 정의(CRD)와 operator를 활용하여 구성 및 수명주기 관리의 복잡성을 처리하면서 Kubernetes에서 KRaft 모드의 Kafka 클러스터를 원활하게 배포하고 관리할 수 있습니다.

## 아키텍처

:::info

아키텍처 다이어그램 작업 중

:::

<CollapsibleContent header={<h2><span>관리형 대안</span></h2>}>

### Amazon Managed Streaming for Apache Kafka (MSK)
[Amazon Managed Streaming for Apache Kafka(Amazon MSK)](https://aws.amazon.com/msk/)는 Apache Kafka를 사용하여 스트리밍 데이터를 처리하는 애플리케이션을 구축하고 실행할 수 있는 완전관리형 서비스입니다. Amazon MSK는 클러스터 생성, 업데이트 및 삭제와 같은 컨트롤 플레인 작업을 제공합니다. 데이터 생성 및 소비와 같은 Apache Kafka 데이터 플레인 작업을 사용할 수 있습니다. 오픈소스 버전의 Apache Kafka를 실행합니다. 이는 기존 애플리케이션, 도구 및 파트너와 Apache Kafka 커뮤니티의 플러그인이 지원됨을 의미합니다. Amazon MSK를 사용하여 [지원되는 Apache Kafka 버전](https://docs.aws.amazon.com/msk/latest/developerguide/supported-kafka-versions.html)에 나열된 모든 Apache Kafka 버전을 사용하는 클러스터를 만들 수 있습니다. Amazon MSK는 클러스터 기반 또는 서버리스 배포 유형을 제공합니다.

### Amazon Kinesis Data Streams (KDS)
[Amazon Kinesis Data Streams(KDS)](https://aws.amazon.com/kinesis/data-streams/)를 사용하면 사용자가 대량의 데이터 레코드 스트림을 실시간으로 수집하고 처리할 수 있습니다. Kinesis Data Streams 애플리케이션이라고 하는 데이터 처리 애플리케이션을 만들 수 있습니다. 일반적인 Kinesis Data Streams 애플리케이션은 데이터 스트림에서 데이터를 데이터 레코드로 읽습니다. 처리된 레코드를 대시보드로 보내거나, 경고 생성에 사용하거나, 가격 책정 및 광고 전략을 동적으로 변경하거나, 다양한 다른 AWS 서비스로 데이터를 보낼 수 있습니다. Kinesis Data Streams는 Kinesis Client Library(KCL), Apache Flink, Apache Spark Streaming을 포함한 스트림 처리 프레임워크 선택을 지원합니다. 서버리스이며 자동으로 확장됩니다.

</CollapsibleContent>

<CollapsibleContent header={<h2><span>Kafka 자체 관리 시 스토리지 고려 사항</span></h2>}>

Kafka 클러스터의 가장 일반적인 리소스 병목 현상은 네트워크 처리량, 스토리지 처리량, [Amazon Elastic Block Store(EBS)](https://aws.amazon.com/ebs/)와 같은 네트워크 연결 스토리지를 사용하는 브로커의 브로커와 스토리지 백엔드 간의 네트워크 처리량입니다.

### EBS를 영구 스토리지 백엔드로 사용하는 장점
1. **향상된 유연성과 빠른 복구:** 내결함성은 일반적으로 클러스터 내의 브로커(서버) 복제 및/또는 크로스 AZ 또는 리전 복제본 유지를 통해 달성됩니다. EBS 볼륨의 수명주기는 Kafka 브로커와 독립적이므로 브로커가 실패하고 교체해야 하는 경우 실패한 브로커에 연결된 EBS 볼륨을 교체 브로커에 다시 연결할 수 있습니다. 교체 브로커에 필요한 대부분의 복제 데이터는 이미 EBS 볼륨에서 사용 가능하며 다른 브로커에서 네트워크를 통해 복사할 필요가 없습니다. 이렇게 하면 교체 브로커를 현재 작업에 맞게 빠르게 설정하는 데 필요한 복제 트래픽을 대부분 피할 수 있습니다.
2. **적시 확장:** EBS 볼륨의 특성은 사용 중에 수정할 수 있습니다. 브로커 스토리지는 피크에 맞춰 프로비저닝하거나 추가 브로커를 추가하는 대신 시간이 지남에 따라 자동으로 확장할 수 있습니다.
3. **자주 액세스하는 처리량 집약적 워크로드에 최적화:** st1과 같은 볼륨 유형은 상대적으로 저렴한 비용으로 제공되고 큰 1 MiB I/O 블록 크기, 볼륨당 최대 500 IOPS를 지원하며 TB당 최대 250 MB/s 버스트, TB당 40 MB/s 기준 처리량, 볼륨당 최대 500 MB/s 처리량 버스트 기능을 포함하므로 적합할 수 있습니다.

### AWS에서 Kafka를 자체 관리할 때 어떤 EBS 볼륨을 사용해야 하나요?
* 범용 SSD 볼륨 **gp3**는 균형 잡힌 가격과 성능으로 널리 사용되며, 스토리지(최대 16TiB), IOPS(최대 16,000) 및 처리량(최대 1,000MiB/s)을 **독립적으로** 프로비저닝할 수 있습니다.
* **st1**은 자주 액세스하는 처리량 집약적 워크로드를 위한 저비용 HDD 옵션으로 최대 500 IOPS와 500 MiB/s를 제공합니다.
* Zookeeper와 같은 중요한 애플리케이션의 경우 프로비저닝된 IOPS 볼륨(**io2 Block Express, io2**)이 더 높은 내구성을 제공합니다.

### 성능상의 이유로 NVMe SSD 인스턴스 스토리지는 어떨까요?
EBS가 유연성과 관리 용이성을 제공하는 반면, 일부 고성능 사용 사례에서는 로컬 NVMe SSD 인스턴스 스토리지를 사용하면 이점을 얻을 수 있습니다. 이 접근 방식은 상당한 성능 향상을 제공할 수 있지만 데이터 지속성과 운영 복잡성 측면에서 트레이드오프가 있습니다.

#### NVMe SSD 인스턴스 스토리지의 고려 사항 및 과제
1. **데이터 지속성:** 로컬 스토리지는 휘발성입니다. 인스턴스가 실패하거나 종료되면 해당 스토리지의 데이터가 손실됩니다. 특히 클러스터가 큰 경우(수백 TB의 데이터) 복제 전략과 재해 복구 계획을 신중하게 고려해야 합니다.
2. **클러스터 업그레이드:** Kafka 또는 EKS 업그레이드가 더 복잡해집니다. 로컬 스토리지가 있는 노드를 변경하기 전에 데이터가 제대로 마이그레이션되거나 복제되었는지 확인해야 합니다.
3. **확장 복잡성:** 클러스터 확장에 데이터 리밸런싱이 필요할 수 있으며, 이는 네트워크 연결 스토리지를 사용하는 것보다 더 시간이 많이 걸리고 리소스 집약적일 수 있습니다.
4. **인스턴스 유형 종속:** 적절한 로컬 스토리지 옵션이 있는 인스턴스를 선택해야 하므로 인스턴스 유형 선택이 더 제한됩니다.

#### 언제 로컬 스토리지 사용을 고려해야 하나요?
1. 모든 밀리초의 지연 시간이 중요한 매우 높은 성능 요구 사항이 있는 경우
2. 데이터 내구성을 위해 Kafka의 복제에 의존하면서 개별 노드 장애 시 잠재적인 데이터 손실을 감수할 수 있는 사용 사례

로컬 스토리지는 성능 이점을 제공할 수 있지만 특히 EKS와 같은 동적 환경에서 운영 과제와 신중하게 비교하는 것이 중요합니다. 대부분의 사용 사례에서는 유연성과 더 쉬운 관리를 위해 EBS 스토리지로 시작하고 트레이드오프가 정당화되는 특정 고성능 시나리오에서만 로컬 스토리지를 고려하는 것이 좋습니다.

</CollapsibleContent>

<CollapsibleContent header={<h2><span>솔루션 배포</span></h2>}>

이 [예제](https://github.com/awslabs/data-on-eks/tree/main/streaming/kafka)에서는 EKS에서 Kafka 클러스터를 실행하기 위해 다음 리소스를 프로비저닝합니다.

이 예제는 새로운 VPC에 Kafka가 포함된 EKS 클러스터를 배포합니다.

- 새 샘플 VPC, 3개의 프라이빗 서브넷 및 3개의 퍼블릭 서브넷 생성
- 퍼블릭 서브넷용 인터넷 게이트웨이 및 프라이빗 서브넷용 NAT Gateway 생성
- 하나의 관리형 노드 그룹이 있는 퍼블릭 엔드포인트(데모 목적으로만)를 가진 EKS 클러스터 컨트롤 플레인 생성
- Metrics server, Karpenter, 자체 관리형 ebs-csi-driver, Strimzi Kafka Operator, Grafana Operator 배포
- Strimzi Kafka Operator는 `strimzi-kafka-operator` 네임스페이스에 배포된 Apache Kafka용 Kubernetes Operator입니다. Operator는 기본적으로 모든 네임스페이스의 `kafka`를 감시하고 처리합니다.

### 사전 요구 사항
다음 도구가 로컬 머신에 설치되어 있는지 확인하세요.

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### 배포

저장소 복제:

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

예제 디렉토리 중 하나로 이동하고 `install.sh` 스크립트를 실행합니다:

```bash
cd data-on-eks/streaming/kafka
chmod +x install.sh
./install.sh
```

:::info

이 배포는 20~30분이 소요될 수 있습니다.

:::

## 배포 확인

### kube config 생성

kube config 파일을 생성합니다.

```bash
aws eks --region $AWS_REGION update-kubeconfig --name kafka-on-eks
```

### 노드 확인

배포가 Core Node 그룹용으로 약 3개의 노드를 생성했는지 확인합니다:

```bash
kubectl get nodes
```

다음과 유사한 출력이 표시됩니다:

```text
NAME                                       STATUS   ROLES    AGE     VERSION
ip-10-1-0-193.eu-west-1.compute.internal   Ready    <none>   5h32m   v1.31.0-eks-a737599
ip-10-1-1-231.eu-west-1.compute.internal   Ready    <none>   5h32m   v1.31.0-eks-a737599
ip-10-1-2-20.eu-west-1.compute.internal    Ready    <none>   5h32m   v1.31.0-eks-a737599
```
</CollapsibleContent>

<CollapsibleContent header={<h2><span>Kafka 클러스터 생성</span></h2>}>

## Kafka 클러스터 매니페스트 배포

Kafka 클러스터 전용 네임스페이스 생성:

```bash
kubectl create namespace kafka
```

Kafka 클러스터 매니페스트 배포:

```bash
kubectl apply -f kafka-manifests/
```

Grafana에 Strimzi Kafka 대시보드 배포:

```bash
kubectl apply -f monitoring-manifests/
```

### Karpenter가 프로비저닝한 노드 확인

이제 Core Node 그룹용 3개의 노드와 3개의 AZ에 걸친 Kafka 브로커용 6개의 노드, 총 약 9개의 노드가 표시되는지 확인합니다:

```bash
kubectl get nodes
```

다음과 유사한 출력이 표시됩니다:

```text
NAME                                       STATUS   ROLES    AGE     VERSION
ip-10-1-1-231.eu-west-1.compute.internal   Ready    <none>   5h32m   v1.31.0-eks-a737599
ip-10-1-2-20.eu-west-1.compute.internal    Ready    <none>   5h32m   v1.31.0-eks-a737599
ip-10-1-0-193.eu-west-1.compute.internal   Ready    <none>   5h32m   v1.31.0-eks-a737599
ip-10-1-0-151.eu-west-1.compute.internal   Ready    <none>   62m     v1.31.0-eks-5da6378
ip-10-1-0-175.eu-west-1.compute.internal   Ready    <none>   62m     v1.31.0-eks-5da6378
ip-10-1-1-104.eu-west-1.compute.internal   Ready    <none>   62m     v1.31.0-eks-5da6378
ip-10-1-1-106.eu-west-1.compute.internal   Ready    <none>   62m     v1.31.0-eks-5da6378
ip-10-1-2-4.eu-west-1.compute.internal     Ready    <none>   62m     v1.31.0-eks-5da6378
ip-10-1-2-56.eu-west-1.compute.internal    Ready    <none>   62m     v1.31.0-eks-5da6378
```

### Kafka 브로커 및 컨트롤러 확인

Strimzi Operator가 생성한 Kafka 브로커 및 컨트롤러 파드와 상태를 확인합니다.

```bash
kubectl get strimzipodsets.core.strimzi.io -n kafka
```

다음과 유사한 출력이 표시됩니다:

```text
NAME                 PODS   READY PODS   CURRENT PODS   AGE
cluster-broker       3      3            3              64m
cluster-controller   3      3            3              64m
```

KRaft 모드에서 Kafka 클러스터를 생성했는지 확인합니다:

```bash
kubectl get kafka.kafka.strimzi.io -n kafka
```

다음과 유사한 출력이 표시됩니다:

```text
NAME      DESIRED KAFKA REPLICAS   DESIRED ZK REPLICAS   READY   METADATA STATE   WARNINGS
cluster                                                  True    KRaft            True
```

### 실행 중인 Kafka 파드 확인
Kafka 클러스터의 파드가 실행 중인지 확인합니다:

```bash
kubectl get pods -n kafka
```

다음과 유사한 출력이 표시됩니다:

```text
NAME                                      READY   STATUS    RESTARTS   AGE
cluster-broker-0                          1/1     Running   0          24m
cluster-broker-1                          1/1     Running   0          15m
cluster-broker-2                          1/1     Running   0          8m31s
cluster-controller-3                      1/1     Running   0          16m
cluster-controller-4                      1/1     Running   0          7m8s
cluster-controller-5                      1/1     Running   0          7m48s
cluster-cruise-control-74f5977f48-l8pzp   1/1     Running   0          24m
cluster-entity-operator-d46598d9c-xgwnh   2/2     Running   0          24m
cluster-kafka-exporter-5ff5ff4675-2cz9m   1/1     Running   0          24m
```
</CollapsibleContent>

<CollapsibleContent header={<h2><span>Kafka 토픽 생성 및 샘플 테스트 실행</span></h2>}>

하나의 kafka 토픽을 생성하고 샘플 프로듀서 스크립트를 실행하여 kafka 토픽에 새 메시지를 생성합니다.

### Kafka 토픽 생성

이 명령을 실행하여 `kafka` 네임스페이스에 `test-topic`이라는 새 토픽을 생성합니다:

```bash
kubectl apply -f examples/kafka-topics.yaml
```

토픽이 생성되었는지 확인합니다:

```bash
kubectl get kafkatopic.kafka.strimzi.io -n kafka
```

다음과 유사한 출력이 표시됩니다:

```text
NAME         CLUSTER   PARTITIONS   REPLICATION FACTOR   READY
test-topic   cluster   12           3                    True
```

`test-topic` 토픽의 상태를 확인합니다.

```bash
kubectl exec -it cluster-broker-0 -c kafka -n kafka -- /bin/bash -c "/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092"
```

다음과 유사한 출력이 표시됩니다:

```text
strimzi.cruisecontrol.metrics
strimzi.cruisecontrol.modeltrainingsamples
strimzi.cruisecontrol.partitionmetricsamples
test-topic
```

### 샘플 Kafka 프로듀서 실행

Kafka 프로듀서용과 Kafka 컨슈머용으로 두 개의 터미널을 엽니다. 다음 명령을 실행하고 `>` 프롬프트가 표시될 때까지 엔터를 두 번 누릅니다. 임의의 내용을 입력합니다. 이 데이터는 `test-topic`에 기록됩니다.

```bash
kubectl -n kafka run kafka-producer -ti --image=quay.io/strimzi/kafka:0.43.0-kafka-3.8.0 --rm=true --restart=Never -- bin/kafka-console-producer.sh --bootstrap-server cluster-kafka-bootstrap:9092 --topic test-topic
```

### 샘플 Kafka 컨슈머 실행

이제 다른 터미널에서 Kafka 컨슈머 파드를 실행하여 `test-topic`에 기록된 데이터를 확인할 수 있습니다.

```bash
kubectl -n kafka run kafka-consumer -ti --image=quay.io/strimzi/kafka:0.43.0-kafka-3.8.0 --rm=true --restart=Never -- bin/kafka-console-consumer.sh --bootstrap-server cluster-kafka-bootstrap:9092 --topic test-topic --from-beginning
```

### Kafka 프로듀서 및 컨슈머 출력

![img.png](img/kafka-consumer.png)

</CollapsibleContent>

<CollapsibleContent header={<h2><span>Kafka용 Grafana 대시보드</span></h2>}>

### Grafana 로그인
다음 명령을 실행하여 Grafana 대시보드에 로그인합니다.

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 8080:80 -n kube-prometheus-stack
```
브라우저에서 로컬 [Grafana Web UI](http://localhost:8080/) 를 엽니다.

사용자 이름으로 `admin`을 입력하고 아래 명령으로 AWS Secrets Manager에서 **password**를 추출할 수 있습니다.

```bash
aws secretsmanager get-secret-value --secret-id kafka-on-eks-grafana --region $AWS_REGION --query "SecretString" --output text
```

### Strimzi Kafka 대시보드 열기

[http://localhost:8080/dashboards](http://localhost:8080/dashboards)에서 `Dashboards` 페이지로 이동한 다음 `General`을 클릭하고 `Strimzi Kafka`를 클릭합니다.

배포 중에 생성된 아래의 내장 Kafka 대시보드가 표시됩니다:

![Kafka Brokers Dashboard](img/kafka-brokers.png)

</CollapsibleContent>

<CollapsibleContent header={<h2><span>정리</span></h2>}>

환경을 정리하려면 다음 명령을 실행하고 EKS 클러스터를 생성할 때 사용한 것과 동일한 리전을 입력합니다:

```bash
cd data-on-eks/streaming/kafka
chmod +x cleanup.sh
./cleanup.sh
```

:::info

20~30분이 소요될 수 있습니다.

:::
</CollapsibleContent>
