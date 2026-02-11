---
sidebar_position: 3
sidebar_label: Spark on EKS 모범 사례
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '@site/src/components/CollapsibleContent';

# Spark on EKS 모범 사례

이 페이지는 Amazon Elastic Kubernetes Service(EKS)에서 Apache Spark 워크로드를 배포, 관리 및 최적화하기 위한 포괄적인 모범 사례와 가이드라인을 제공하는 것을 목표로 합니다. 이를 통해 조직이 Amazon EKS의 컨테이너화된 환경에서 Spark 애플리케이션을 대규모로 성공적으로 실행하고 확장할 수 있습니다.

EKS에서 Spark를 배포하려면 대부분의 모범 사례가 이미 통합된 [블루프린트](https://awslabs.github.io/data-on-eks/docs/blueprints/data-analytics/spark-operator-yunikorn)를 활용할 수 있습니다. 이 가이드에 설명된 대로 특정 애플리케이션 요구 사항 및 환경 제약 조건에 맞게 구성을 조정하여 이 블루프린트를 추가로 사용자 정의할 수 있습니다.

## EKS 네트워킹
### VPC 및 서브넷 크기 조정
#### VPC IP 주소 고갈

EKS 클러스터가 추가 Spark 워크로드와 함께 확장됨에 따라 클러스터가 관리하는 Pod 수는 쉽게 수천 개로 늘어날 수 있으며, 각각 IP 주소를 소비합니다. VPC 내의 IP 주소는 제한되어 있고 더 큰 VPC를 다시 생성하거나 현재 VPC의 CIDR 블록을 확장하는 것이 항상 가능하지 않기 때문에 이는 문제를 야기합니다.

워커 노드와 Pod 모두 IP 주소를 소비합니다. 기본적으로 VPC CNI는 `WARM_ENI_TARGET=1`로 설정되어 있어 `ipamd`가 Pod IP 할당을 위해 사용 가능한 IP의 "전체 ENI"를 `ipamd` 웜 풀(warm pool)에 유지해야 함을 의미합니다.

#### IP 주소 고갈 해결책
VPC에 대한 IP 고갈 해결 방법이 존재하지만, 추가적인 운영 복잡성을 도입하고 고려해야 할 중요한 영향이 있습니다. 따라서 새 EKS 클러스터의 경우 성장을 위해 Pod 네트워킹에 사용할 서브넷을 과도하게 프로비저닝하는 것이 좋습니다.

IP 주소 고갈을 해결하려면 VPC에 보조 CIDR 블록을 추가하고 이러한 추가 주소 범위에서 새 서브넷을 생성한 다음, 이 확장된 서브넷에 워커 노드를 배포하는 것을 고려하세요.

더 많은 서브넷을 추가하는 것이 옵션이 아닌 경우, CNI 구성 변수를 조정하여 IP 주소 할당을 최적화해야 합니다. [MINIMUM_IP_TARGET 구성](/docs/bestpractices/networking#avoid-using-warm_ip_target-in-large-clusters-or-cluster-with-a-lot-of-churn)을 참조하세요.


### CoreDNS 권장 사항
#### DNS 조회 스로틀링
Kubernetes에서 실행되는 Spark 애플리케이션은 익스큐터(executor)가 외부 서비스와 통신할 때 대량의 DNS 조회를 생성합니다.

이는 Kubernetes의 DNS 확인 모델이 모든 새 연결에 대해 각 Pod가 클러스터의 DNS 서비스(kube-dns 또는 CoreDNS)를 쿼리해야 하고, 작업 실행 중에 Spark 익스큐터가 외부 서비스와 통신하기 위해 자주 새 연결을 생성하기 때문입니다. 기본적으로 Kubernetes는 Pod 수준에서 DNS 결과를 캐시하지 않으므로, 각 익스큐터 Pod는 이전에 확인된 호스트 이름에 대해서도 새 DNS 조회를 수행해야 합니다.

이 동작은 여러 익스큐터 Pod가 동일한 외부 서비스 엔드포인트를 동시에 확인하려고 시도하는 분산 특성으로 인해 Spark 애플리케이션에서 증폭됩니다. 이는 데이터 수집, 처리 중 및 외부 데이터베이스나 셔플 서비스에 연결할 때 발생합니다.

DNS 트래픽이 CoreDNS 레플리카당 초당 1024 패킷을 초과하면 DNS 요청이 스로틀링되어 `unknownHostException` 오류가 발생합니다.

#### 해결책
워크로드가 확장됨에 따라 CoreDNS를 스케일링하는 것이 좋습니다. 구현 선택 사항에 대한 자세한 내용은 [CoreDNS 스케일링](/docs/bestpractices/networking#scaling-coredns)을 참조하세요.

또한 CoreDNS 메트릭을 지속적으로 모니터링하는 것이 좋습니다. 자세한 정보는 [EKS 네트워킹 모범 사례](https://docs.aws.amazon.com/eks/latest/best-practices/monitoring_eks_workloads_for_network_performance_issues.html#_monitoring_coredns_traffic_for_dns_throttling_issues)를 참조하세요.


### AZ 간 트래픽 줄이기

#### AZ 간 비용
셔플 단계에서 Spark 익스큐터는 서로 데이터를 교환해야 할 수 있습니다. Pod가 여러 가용 영역(AZ)에 분산되어 있는 경우, 이 셔플 작업은 특히 네트워크 I/O 측면에서 매우 비용이 많이 들 수 있으며, 이는 AZ 간 트래픽 비용으로 청구됩니다.

#### 해결책
Spark 워크로드의 경우 익스큐터 Pod와 워커 노드를 동일한 AZ에 배치하는 것이 좋습니다. 동일한 AZ에 워크로드를 배치하면 두 가지 주요 목적이 있습니다:
* AZ 간 트래픽 비용 절감
* 익스큐터/Pod 간 네트워크 지연 시간 감소

동일한 AZ에 Pod를 배치하는 방법은 [AZ 간 네트워크 최적화](/docs/bestpractices/networking#inter-az-network-optimization)를 참조하세요.

## Karpenter 권장 사항

[Karpenter](https://karpenter.sh/docs/)는 Spark의 동적 리소스 스케일링 요구에 맞는 빠른 노드 프로비저닝 기능을 제공하여 EKS에서의 Spark 배포를 향상시킵니다. 이 자동화된 스케일링 솔루션은 필요에 따라 적절한 크기의 노드를 가져와 리소스 활용률과 비용 효율성을 개선합니다. 또한 사전 구성된 노드 그룹이나 수동 개입 없이 Spark 작업이 원활하게 확장될 수 있어 운영 관리가 단순화됩니다.

다음은 Spark 워크로드를 실행하면서 컴퓨팅 노드를 스케일링하기 위한 Karpenter 권장 사항입니다. 전체 Karpenter 구성 세부 정보는 [Karpenter 문서](https://karpenter.sh/docs/)를 참조하세요.

드라이버(driver)와 익스큐터(executor) Pod를 위한 별도의 NodePool을 생성하는 것을 고려하세요.

### 드라이버 NodePool
Spark 드라이버는 단일 Pod이며 Spark 애플리케이션의 전체 수명 주기를 관리합니다. Spark 드라이버 Pod를 종료하면 사실상 전체 Spark 작업이 종료됩니다.
* 드라이버 NodePool은 항상 `on-demand` 노드만 사용하도록 구성하세요. Spark 드라이버 Pod가 스팟 인스턴스에서 실행되면 스팟 인스턴스 회수로 인한 예기치 않은 종료에 취약해져, 계산 손실과 중단된 처리가 발생하고 재시작을 위한 수동 개입이 필요합니다.
* 드라이버 NodePool에서 [`consolidation`](https://karpenter.sh/docs/concepts/disruption/#consolidation)을 비활성화하세요.
* `node selectors` 또는 `taints/tolerations`를 사용하여 드라이버 Pod를 지정된 드라이버 NodePool에 배치하세요.

### 익스큐터 NodePool
#### 스팟 인스턴스 구성
[Amazon EC2 예약 인스턴스](https://aws.amazon.com/ec2/pricing/reserved-instances/) 또는 [Savings Plans](https://aws.amazon.com/savingsplans/)가 없는 경우, 익스큐터에 [Amazon EC2 스팟 인스턴스](https://aws.amazon.com/ec2/spot/)를 사용하여 데이터플레인 비용을 절감하는 것을 고려하세요.

스팟 인스턴스가 중단되면 익스큐터가 종료되고 사용 가능한 노드에서 다시 스케줄링됩니다. 중단 동작 및 노드 종료 관리에 대한 자세한 내용은 `중단 처리` 섹션을 참조하세요.

#### 인스턴스 및 용량 유형 선택

노드 풀에서 여러 인스턴스 유형을 사용하면 다양한 스팟 인스턴스 풀에 액세스할 수 있어 사용 가능한 인스턴스 옵션에서 가격과 용량 모두에 최적화하면서 용량 가용성이 증가합니다.

`가중치 NodePool`을 사용하면 우선 순위 순서로 배열된 가중치 NodePool을 사용하여 노드 선택을 최적화할 수 있습니다. 각 NodePool에 다른 가중치를 할당하여 스팟(가장 높은 가중치), Graviton, AMD, Intel(가장 낮은 가중치) 순서와 같은 선택 계층 구조를 설정할 수 있습니다.

#### 통합(Consolidation) 구성
Spark 익스큐터 Pod에 대해 `consolidation`을 활성화하면 클러스터 리소스 활용률이 향상될 수 있지만, 작업 성능과의 균형을 맞추는 것이 중요합니다. 빈번한 통합 이벤트는 익스큐터가 셔플 데이터와 RDD 블록을 재계산해야 하므로 Spark 작업의 실행 시간이 느려질 수 있습니다.

이 영향은 장기 실행 Spark 작업에서 특히 두드러집니다. 이를 완화하려면 통합 간격을 신중하게 조정하는 것이 필수적입니다.

정상적인 익스큐터 Pod 종료를 활성화하세요:
* `spark.executor.decommission.enabled=true`: 익스큐터의 정상적인 해제를 활성화하여 종료 전에 현재 작업을 완료하고 캐시된 데이터를 전송할 수 있습니다. 이는 익스큐터에 스팟 인스턴스를 사용할 때 특히 유용합니다.

* `spark.storage.decommission.enabled=true`: 종료 전에 해제 중인 익스큐터에서 다른 활성 익스큐터로 캐시된 RDD 블록의 마이그레이션을 활성화하여 데이터 손실과 재계산 필요성을 방지합니다.


Spark 익스큐터에서 계산된 중간 데이터를 저장하는 다른 방법을 알아보려면 [스토리지 모범 사례](#storage-best-practices)를 참조하세요.

#### Karpenter 통합/스팟 종료 중 중단 처리

노드가 종료 예정일 때 익스큐터를 갑자기 종료하는 대신 제어된 해제를 수행하세요. 이를 위해:
* Spark 워크로드에 적절한 TerminationGracePeriod 값을 구성하세요.
* 익스큐터 인식 종료 처리를 구현하세요.
* 노드가 해제되기 전에 셔플 데이터가 저장되었는지 확인하세요.

Spark는 종료 동작을 제어하기 위한 네이티브 구성을 제공합니다:

**익스큐터 중단 제어**
* **구성**:
* `spark.executor.decommission.enabled`
* `spark.executor.decommission.forceKillTimeout`
이 구성은 스팟 인스턴스 중단 또는 Karpenter 통합 이벤트로 인해 익스큐터가 종료될 수 있는 시나리오에서 특히 유용합니다. 활성화되면 익스큐터는 작업 수락을 중지하고 드라이버에게 해제 상태를 알려 정상적으로 종료됩니다.

**익스큐터의 BlockManager 동작 제어**
* **구성**:
* `spark.storage.decommission.enabled`
* `spark.storage.decommission.shuffleBlocks.enabled`
* `spark.storage.decommission.rddBlocks.enabled`
* `spark.storage.decommission.fallbackStorage.path`
이러한 설정은 해제 중인 익스큐터에서 다른 사용 가능한 익스큐터 또는 대체 스토리지 위치로 셔플 및 RDD 블록의 마이그레이션을 활성화합니다. 이 접근 방식은 셔플 데이터나 RDD 블록을 재계산할 필요성을 줄여 작업 완료 시간과 리소스 효율성을 개선하는 데 도움이 됩니다.

## 고급 스케줄링 고려 사항
### 기본 Kubernetes 스케줄러 동작

기본 Kubernetes 스케줄러는 `least allocated` 접근 방식을 사용합니다. 이 전략은 클러스터 전체에 Pod를 균등하게 분산시켜 가용성을 유지하고 더 적은 노드에 더 많은 Pod를 패킹하는 대신 모든 노드에서 균형 잡힌 리소스 활용을 유지하는 것을 목표로 합니다.

반면 `Most allocated` 접근 방식은 가장 많은 양의 할당된 리소스가 있는 노드를 선호하여 이미 많이 할당된 노드에 더 많은 Pod를 패킹합니다. 이 접근 방식은 Pod 스케줄링 시간에 선택된 노드에서 높은 활용률을 목표로 하여 노드의 더 나은 통합으로 이어지므로 Spark 작업에 유리합니다. 이 옵션을 활성화한 사용자 정의 kube-scheduler를 활용하거나 더 고급 오케스트레이션을 위해 특별히 구축된 사용자 정의 스케줄러를 활용해야 합니다.

### 사용자 정의 스케줄러

사용자 정의 스케줄러는 배치 및 고성능 컴퓨팅 워크로드에 맞춤화된 고급 기능을 제공하여 Kubernetes의 네이티브 스케줄링 기능을 향상시킵니다. 사용자 정의 스케줄러는 빈 패킹(bin-packing)을 최적화하고 특정 애플리케이션 요구에 맞춤화된 스케줄링을 제공하여 리소스 할당을 향상시킵니다. 다음은 Kubernetes에서 Spark 워크로드를 실행하기 위한 인기 있는 사용자 정의 스케줄러입니다.
* [Apache Yunikorn](https://yunikorn.apache.org/)
* [Volcano](https://volcano.sh/en/)

Yunikorn과 같은 사용자 정의 스케줄러를 활용하는 장점:
* 복잡한 리소스 관리를 가능하게 하는 계층적 큐 시스템 및 구성 가능한 정책.
* 모든 관련 Pod(예: Spark 익스큐터)가 함께 시작되도록 보장하여 리소스 낭비를 방지하는 갱 스케줄링(gang scheduling).
* 다양한 테넌트와 워크로드 간의 리소스 공정성.


### Yunikorn과 Karpenter는 어떻게 함께 작동하나요?

Karpenter와 Yunikorn은 Kubernetes에서 워크로드 관리의 다른 측면을 처리하여 서로 보완합니다:

* **Karpenter**는 노드 프로비저닝 및 스케일링에 집중하여 리소스 수요에 따라 노드를 추가하거나 제거할 시기를 결정합니다.

* **Yunikorn**은 큐 관리, 리소스 공정성, 갱 스케줄링과 같은 고급 기능을 통해 스케줄링에 애플리케이션 인식을 가져옵니다.

일반적인 워크플로에서 Yunikorn은 먼저 애플리케이션 인식 정책과 큐 우선 순위에 따라 Pod를 스케줄합니다. 이러한 Pod가 클러스터 리소스 부족으로 인해 보류 상태로 남아 있으면 Karpenter가 이러한 보류 중인 Pod를 감지하고 이를 수용할 적절한 노드를 프로비저닝합니다. 이 통합은 효율적인 Pod 배치(Yunikorn)와 최적의 클러스터 스케일링(Karpenter)을 모두 보장합니다.

Spark 워크로드의 경우 이 조합이 특히 효과적입니다: Yunikorn은 익스큐터가 애플리케이션 SLA 및 종속성에 따라 스케줄되도록 보장하고, Karpenter는 이러한 특정 요구 사항을 충족하는 올바른 노드 유형을 사용할 수 있도록 보장합니다.


## 스토리지 모범 사례
### 노드 스토리지
기본적으로 워커 노드의 EBS 루트 볼륨은 20GB로 설정됩니다. Spark 익스큐터는 셔플 데이터, 중간 결과 및 임시 파일과 같은 임시 데이터에 로컬 스토리지를 사용합니다. 워커 노드에 연결된 이 기본 20GB 루트 볼륨 스토리지는 크기와 성능 모두에서 제한적일 수 있습니다. 성능 및 스토리지 크기 요구 사항을 해결하려면 다음 옵션을 고려하세요:
* 중간 Spark 데이터를 위한 충분한 공간을 제공하도록 루트 볼륨 용량을 확장하세요. 각 익스큐터가 처리할 데이터셋의 평균 크기와 Spark 작업의 복잡성을 기반으로 최적의 용량을 결정해야 합니다.
* 더 나은 I/O 및 지연 시간을 가진 고성능 스토리지를 구성하세요.
* 임시 데이터 스토리지를 위해 워커 노드에 추가 볼륨을 마운트하세요.
* 익스큐터 Pod에 직접 연결할 수 있는 동적으로 프로비저닝된 PVC를 활용하세요.

### PVC 재사용
이 옵션을 사용하면 익스큐터가 종료된 후에도(통합 활동 또는 스팟 인스턴스의 경우 선점으로 인해) Spark 익스큐터와 연결된 PVC를 재사용할 수 있습니다.

이를 통해 PVC에서 중간 셔플 데이터와 캐시된 데이터를 보존할 수 있습니다. Spark가 종료된 익스큐터를 대체하기 위해 새 익스큐터 Pod를 요청하면 시스템은 종료된 익스큐터에 속한 기존 PVC를 재사용하려고 시도합니다. 이 옵션은 다음 구성으로 활성화할 수 있습니다:

`spark.kubernetes.executor.reusePersistentVolume=true`

### 외부 셔플 서비스
Apache Celeborn과 같은 외부 셔플 서비스를 활용하여 컴퓨팅과 스토리지를 분리하여 Spark 익스큐터가 로컬 디스크 대신 외부 셔플 서비스에 데이터를 쓸 수 있게 하세요. 이를 통해 익스큐터 종료 또는 통합으로 인한 데이터 손실 및 데이터 재계산 위험을 줄일 수 있습니다.

또한 특히 `Spark 동적 리소스 할당`이 활성화된 경우 더 나은 리소스 관리가 가능합니다. 외부 셔플 서비스를 통해 Spark는 동적 리소스 할당 중에 익스큐터가 제거된 후에도 셔플 데이터를 보존하여 새 익스큐터가 추가될 때 셔플 데이터를 재계산할 필요가 없습니다. 이를 통해 리소스가 필요하지 않을 때 더 효율적인 스케일 다운이 가능합니다.

또한 외부 셔플 서비스의 성능 영향을 고려하세요. 더 작은 데이터셋이나 셔플 데이터 볼륨이 낮은 애플리케이션의 경우, 외부 셔플 서비스를 설정하고 관리하는 오버헤드가 이점보다 클 수 있습니다.

외부 셔플 서비스는 작업당 500GB에서 1TB를 초과하는 셔플 데이터 볼륨 또는 여러 시간에서 여러 날에 걸쳐 실행되는 장기 실행 Spark 애플리케이션을 다룰 때 권장됩니다.

Kubernetes에서의 배포 및 Apache Spark와의 통합 구성은 이 [Celeborn 문서](https://celeborn.apache.org/docs/latest/deploy_on_k8s/)를 참조하세요.
