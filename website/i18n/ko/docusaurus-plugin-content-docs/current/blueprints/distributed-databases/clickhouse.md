---
sidebar_position: 4
sidebar_label: ClickHouse
---
# EKS 기반 ClickHouse
[ClickHouse](https://clickhouse.com/)는 Apache 2.0 라이선스로 오픈소스된 온라인 분석 처리(OLAP)를 위한 고성능 열 지향(column-oriented) SQL 데이터베이스 관리 시스템(DBMS)입니다.


OLAP는 다양한 관점에서 비즈니스 데이터를 분석하는 데 사용할 수 있는 소프트웨어 기술입니다. 조직은 웹사이트, 애플리케이션, 스마트 미터, 내부 시스템과 같은 여러 데이터 소스에서 데이터를 수집하고 저장합니다. OLAP는 이 데이터를 결합하고 범주로 그룹화하여 전략적 계획을 위한 실행 가능한 인사이트를 제공함으로써 조직이 증가하는 정보량을 처리하고 활용할 수 있도록 돕습니다. 예를 들어, 소매업체는 색상, 크기, 비용, 위치와 같은 판매하는 모든 제품에 대한 데이터를 저장합니다. 소매업체는 또한 주문한 상품 이름과 총 판매 금액과 같은 고객 구매 데이터를 다른 시스템에 수집합니다. OLAP는 데이터셋을 결합하여 어떤 색상 제품이 더 인기 있는지 또는 제품 배치가 판매에 어떤 영향을 미치는지와 같은 질문에 답할 수 있습니다.

**ClickHouse의 주요 이점은 다음과 같습니다:**

* 실시간 분석(Real-Time Analytics): ClickHouse는 실시간 데이터 수집 및 분석을 처리할 수 있어 모니터링, 로깅, 이벤트 데이터 처리와 같은 사용 사례에 적합합니다.
* 고성능(High Performance): ClickHouse는 분석 워크로드에 최적화되어 빠른 쿼리 실행과 높은 처리량을 제공합니다.
* 확장성(Scalability): ClickHouse는 여러 노드에 걸쳐 수평으로 확장하도록 설계되어 사용자가 분산 클러스터 전체에서 페타바이트의 데이터를 저장하고 처리할 수 있습니다. 고가용성과 내결함성을 위해 샤딩 및 복제를 지원합니다.
* 열 지향 스토리지(Column-Oriented Storage): ClickHouse는 행이 아닌 열별로 데이터를 구성하여 효율적인 압축과 특히 집계 및 대규모 데이터셋 스캔을 포함하는 쿼리에 대해 더 빠른 쿼리 처리를 가능하게 합니다.
* SQL 지원(SQL Support): ClickHouse는 SQL의 하위 집합을 지원하여 이미 SQL 기반 데이터베이스에 익숙한 개발자와 분석가가 익숙하고 쉽게 사용할 수 있습니다.
* 통합 데이터 형식(Integrated Data Formats): ClickHouse는 CSV, JSON, Apache Avro, Apache Parquet을 포함한 다양한 데이터 형식을 지원하여 다양한 유형의 데이터를 수집하고 쿼리하는 데 유연합니다.

**EKS에 ClickHouse를 배포하려면** AWS 파트너이자 [ClickHouse Kubernetes Operator](https://github.com/Altinity/clickhouse-operator) 관리자인 Altinity의 [ClickHouse on EKS 블루프린트](https://github.com/Altinity/terraform-aws-eks-clickhouse)를 권장합니다. 블루프린트 또는 operator에 문제가 있으면 해당 Altinity GitHub 저장소에 이슈를 생성해 주세요.
