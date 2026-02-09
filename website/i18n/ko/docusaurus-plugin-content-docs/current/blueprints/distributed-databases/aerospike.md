---
sidebar_position: 5
sidebar_label: Aerospike
---

# EKS 기반 Aerospike Database Enterprise
[Aerospike Database Enterprise Edition](https://aerospike.com)은 실시간 미션 크리티컬 애플리케이션을 위해 설계된 고성능 분산 NoSQL 데이터베이스입니다. Aerospike와 Amazon Elastic Kubernetes Service(EKS)를 통합하면 Aerospike의 강력한 데이터 관리 기능과 Kubernetes 오케스트레이션 능력이 결합됩니다. 이 통합을 통해 조직은 EKS의 유연하고 탄력적인 환경 내에서 Aerospike의 예측 가능한 서브밀리초 성능과 원활한 확장성을 활용할 수 있습니다. [Aerospike Kubernetes Operator(AKO)](https://aerospike.com/docs/cloud/kubernetes/operator)를 활용하면 EKS에서 Aerospike 클러스터의 배포와 관리가 자동화되어 효율적인 운영과 복잡성 감소가 보장됩니다.

## EKS에서 Aerospike의 주요 이점
* **예측 가능한 저지연(Low Latency)**: Aerospike는 서브밀리초 응답 시간을 보장하며, 이는 사기 탐지, 추천 엔진, 실시간 입찰 시스템과 같이 즉각적인 데이터 액세스가 필요한 애플리케이션에 중요합니다.

* **원활한 확장성(Scalability)**: Aerospike의 하이브리드 메모리 아키텍처(Hybrid-Memory Architecture)는 성능 저하 없이 테라바이트에서 페타바이트까지 데이터 증가를 수용하는 효율적인 수평 및 수직 스케일링을 가능하게 합니다. EKS에 배포하면 다양한 워크로드 요구를 효과적으로 충족하기 위한 동적 리소스 할당이 가능합니다.

* **고가용성 및 탄력성(Resilience)**: Cross-Datacenter Replication(XDR)과 같은 기능을 통해 Aerospike는 지리적으로 분산된 클러스터 전반에 걸친 비동기 데이터 복제를 위한 세밀한 제어를 제공합니다. 이를 통해 데이터 가용성과 데이터 로컬리티 규정 준수가 보장됩니다. EKS는 여러 가용 영역에 걸쳐 워크로드를 분산하여 이러한 탄력성을 향상시킵니다.

* **운영 효율성(Operational Efficiency)**: Aerospike Kubernetes Operator는 Aerospike 클러스터의 구성, 스케일링 및 업그레이드와 같은 일상적인 작업을 자동화합니다. 이를 통해 운영 복잡성과 오버헤드가 줄어들어 팀이 인프라 관리 대신 가치 제공에 집중할 수 있습니다.

* **비용 최적화(Cost Optimization)**: Aerospike의 효율적인 리소스 사용과 EKS의 유연한 인프라를 활용하면 기존 배포에 비해 상당한 비용 절감을 달성할 수 있습니다. 하드웨어 풋프린트를 줄이면서 고성능을 제공하는 Aerospike의 능력은 낮은 총 소유 비용(TCO)으로 이어집니다.

## 커뮤니티 및 지원
도움과 커뮤니티 참여를 위해:
* **Aerospike 문서**: 포괄적인 가이드와 참조 자료는 [Aerospike Documentation](https://aerospike.com/docs)에서 확인할 수 있습니다.

* **GitHub 저장소**: aerospike-kubernetes-operator [GitHub 저장소](https://github.com/aerospike/aerospike-kubernetes-operator)에서 AKO 소스 코드에 액세스하고 이슈를 보고하고 기여할 수 있습니다.

* **커뮤니티 포럼**: [Aerospike Community Forum](https://discuss.aerospike.com)에서 토론에 참여하고 조언을 구할 수 있습니다.

Amazon EKS에 Aerospike Database Enterprise Edition을 배포하면 조직은 Aerospike의 고성능 데이터 관리와 Kubernetes 오케스트레이션 기능의 결합된 강점을 활용하여 실시간 데이터 애플리케이션을 위한 확장 가능하고 탄력적이며 비용 효율적인 솔루션을 구현할 수 있습니다.

## EKS에 Aerospike 배포
EKS 클러스터에 Aerospike Database Enterprise Edition을 배포하려면 AWS 파트너이자 [Aerospike Kubernetes Operator](https://github.com/aerospike/aerospike-kubernetes-operator) 관리자인 Aerospike가 유지 관리하는 [Aerospike on EKS 블루프린트](https://github.com/aerospike/aerospike-terraform-aws-eks)를 사용하는 것을 권장합니다.

블루프린트 또는 operator에 문제가 발생하면 관련 Aerospike GitHub 저장소에 보고해 주세요.
