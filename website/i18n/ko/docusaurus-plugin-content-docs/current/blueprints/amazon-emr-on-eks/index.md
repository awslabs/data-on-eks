---
sidebar_position: 1
sidebar_label: 소개
---

# Amazon EMR on EKS
Amazon EMR on EKS를 사용하면 Amazon Elastic Kubernetes Service(EKS) 클러스터에서 온디맨드로 Apache Spark 작업을 제출할 수 있습니다. EMR on EKS를 사용하면 분석 워크로드를 동일한 Amazon EKS 클러스터의 다른 Kubernetes 기반 애플리케이션과 통합하여 리소스 활용도를 개선하고 인프라 관리를 단순화할 수 있습니다.

## EMR on EKS의 이점

### 관리 단순화
오늘날 EC2에서 Apache Spark에 대해 얻는 것과 동일한 EMR 이점을 EKS에서도 얻을 수 있습니다. 여기에는 완전 관리형 Apache Spark 2.4 및 3.0 버전, 자동 프로비저닝, 스케일링, 성능 최적화 런타임, 작업 작성을 위한 EMR Studio 및 디버깅을 위한 Apache Spark UI와 같은 도구가 포함됩니다.

### 비용 절감
EMR on EKS를 사용하면 컴퓨팅 리소스를 Apache Spark 애플리케이션과 다른 Kubernetes 애플리케이션 간에 공유할 수 있습니다. 리소스는 온디맨드로 할당 및 제거되어 이러한 리소스의 과잉 프로비저닝이나 과소 활용을 제거하여 사용한 리소스에 대해서만 비용을 지불하므로 비용을 절감할 수 있습니다.

### 성능 최적화
EKS에서 분석 애플리케이션을 실행하면 공유 Kubernetes 클러스터의 기존 EC2 인스턴스를 재사용하고 분석 전용 새 EC2 인스턴스 클러스터를 만드는 시작 시간을 피할 수 있습니다. 또한 EMR on EKS로 성능 최적화 Spark를 실행하면 EKS의 표준 Apache Spark에 비해 [3배 더 빠른 성능](https://aws.amazon.com/blogs/big-data/amazon-emr-on-amazon-eks-provides-up-to-61-lower-costs-and-up-to-68-performance-improvement-for-spark-workloads/)을 얻을 수 있습니다.

## Terraform을 사용한 EMR on EKS 배포 패턴

다음 Terraform 템플릿을 배포할 수 있습니다.

- [Karpenter가 포함된 EMR on EKS](./emr-eks-karpenter.md): EMR on EKS를 처음 사용하는 경우 **여기서 시작**하세요. 이 템플릿은 EMR on EKS 클러스터를 배포하고 [Karpenter](https://karpenter.sh/) 를 사용하여 Spark 작업을 스케일링합니다.
- [Spark Operator가 포함된 EMR on EKS](./emr-eks-spark-operator.md): 이 템플릿은 Spark 작업 관리를 위한 Spark Operator가 포함된 EMR on EKS 클러스터를 배포합니다.
