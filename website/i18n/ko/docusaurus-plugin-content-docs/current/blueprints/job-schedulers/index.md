---
sidebar_position: 1
sidebar_label: 소개
---

# 작업 스케줄러

작업 스케줄러(Job Schedulers)는 많은 조직 인프라의 필수 구성 요소로, 복잡한 워크플로우를 자동화하고 관리하는 데 도움이 됩니다. Kubernetes에 배포되면 작업 스케줄러는 자동 스케일링, 롤링 업데이트, 자가 복구 기능과 같은 플랫폼의 기능을 활용하여 고가용성과 안정성을 보장할 수 있습니다. **Apache Airflow**, **Argo Workflow**, **Amazon MWAA**와 같은 도구는 Kubernetes 클러스터에서 작업을 관리하고 스케줄링하는 간단하고 효율적인 방법을 제공합니다.

이러한 도구는 데이터 파이프라인, 머신 러닝 워크플로우, 배치 처리를 포함한 광범위한 사용 사례에 적합합니다. Kubernetes의 강력한 기능을 활용함으로써 조직은 작업 스케줄러의 관리를 단순화하고 자동화하여 비즈니스의 다른 영역에 집중할 수 있는 리소스를 확보할 수 있습니다. 성장하는 도구 생태계와 광범위한 사용 사례 지원을 통해 Kubernetes는 프로덕션 환경에서 작업 스케줄러를 실행하기 위한 점점 더 인기 있는 선택지가 되고 있습니다.
다음은 데이터 워크로드에 사용되는 가장 인기 있는 작업 스케줄링 도구입니다.
이 섹션에서는 다음 도구에 대한 배포 패턴과 이러한 스케줄러를 사용하여 Spark/ML 작업을 트리거하는 예제를 제공합니다.

1. [Apache Airflow](https://airflow.apache.org/)
2. [Amazon Managed Workflows for Apache Airflow (MWAA)](https://docs.aws.amazon.com/mwaa/latest/userguide/what-is-mwaa.html)
3. [Argo Workflow](https://argoproj.github.io/workflows/)
4. [Prefect](https://www.prefect.io/)
5. [AWS Batch](https://aws.amazon.com/batch/)
