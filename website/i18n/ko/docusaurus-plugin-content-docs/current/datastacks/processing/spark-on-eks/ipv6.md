---
title: IPv6 네트워킹
sidebar_position: 13
---

이 가이드는 IPv6가 활성화된 Amazon EKS 클러스터에서 Apache Spark를 배포하고 실행하는 방법을 설명합니다.

:::info 전제 조건
이 가이드는 `data-on-eks` 리포지토리를 복제하고 Spark 스택을 배포했다고 가정합니다.
:::

---

## 단계 1: Terraform에서 IPv6 활성화

IPv6가 활성화된 클러스터를 배포하려면 `data-stacks/spark-on-eks/terraform/data-stack.tfvars` 파일을 열고 `enable_ipv6` 변수를 `true`로 설정합니다.

```hcl title="data-stacks/spark-on-eks/terraform/data-stack.tfvars"
enable_ipv6 = true
```

이 변수를 `true`로 설정하면 자동으로 다음이 구성됩니다:

* **EKS 클러스터:** EKS 클러스터와 네트워킹 구성 요소가 IPv6 CIDR 블록으로 프로비저닝됩니다.
* **Spark Operator:** Spark Operator 컨트롤러가 IPv6를 통해 통신하도록 필요한 JVM 인수(`-Djava.net.preferIPv6Addresses=true`)로 구성됩니다.

설정을 활성화한 후 `data-stacks/spark-on-eks` 디렉토리에서 배포 스크립트를 실행합니다:

```bash
./deploy.sh
```

<details>
<summary>일반적인 문제</summary>

#### 오류: AmazonEKS_CNI_IPv6_Policy가 존재하지 않음

**발생 시기:** AWS 계정에서 첫 IPv6 배포 시 또는 정책이 이전에 삭제된 경우.

IPv6를 지원하는 솔루션을 배포할 때 다음 오류가 발생합니다:

```
Error: attaching IAM Policy (arn:aws:iam::1234567890:policy/AmazonEKS_CNI_IPv6_Policy)
to IAM Role (core-node-group-eks-node-group-20241111182906854800000003):
operation error IAM: AttachRolePolicy, https response error StatusCode: 404,
RequestID: 9c99395a-ce3d-4a05-b119-538470a3a9f7,
NoSuchEntity: Policy arn:aws:iam::1234567890:policy/AmazonEKS_CNI_IPv6_Policy
does not exist or is not attachable.
```

Amazon VPC CNI 플러그인은 IPv6 주소를 할당하기 위해 IAM 권한이 필요하므로 IAM 정책을 생성하고 CNI가 사용할 역할과 연결해야 합니다. 그러나 각 IAM 정책 이름은 동일한 AWS 계정에서 고유해야 합니다. 이로 인해 정책이 Terraform 스택의 일부로 생성되고 여러 번 배포되면 충돌이 발생합니다.

이 오류를 해결하려면 아래 명령을 사용하여 수동으로 정책을 생성합니다. 이 작업은 AWS 계정당 한 번만 수행하면 되며, 정책은 여러 EKS 클러스터에서 재사용할 수 있습니다.


#### 해결 방법:

1. 다음 텍스트를 복사하여 vpc-cni-ipv6-policy.json이라는 파일에 저장합니다.

```sh
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AssignIpv6Addresses",
                "ec2:DescribeInstances",
                "ec2:DescribeTags",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeInstanceTypes"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags"
            ],
            "Resource": [
                "arn:aws:ec2::*:network-interface/*"
            ]
        }
    ]
}
```

2. IAM 정책을 생성합니다.

```sh
aws iam create-policy --policy-name AmazonEKS_CNI_IPv6_Policy --policy-document file://vpc-cni-ipv6-policy.json
```

3. 정책이 성공적으로 생성되었는지 확인합니다:

```sh
aws iam get-policy --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AmazonEKS_CNI_IPv6_Policy
```

4. 배포 스크립트를 다시 실행합니다

```bash
./deploy.sh
```

</details>

---

## 단계 2: 배포 확인 (선택 사항)

배포가 완료되면 클러스터가 IPv6 모드에서 실행되고 있는지 확인할 수 있습니다.

<details>
<summary>확인 명령 보기</summary>

Kubernetes 노드의 내부 IP 주소를 확인할 수 있습니다. 출력의 `INTERNAL-IP` 열에 IPv6 주소가 표시되어야 합니다.
```bash
kubectl get node -o custom-columns='NODE_NAME:.metadata.name,INTERNAL-IP:.status.addresses[?(@.type=="InternalIP")].address'

# 예제 출력
NODE_NAME                                 INTERNAL-IP
ip-10-1-0-212.us-west-2.compute.internal  2600:1f13:520:1303:c87:4a71:b9ea:417c
ip-10-1-26-137.us-west-2.compute.internal 2600:1f13:520:1304:15b2:b8a3:7f63:cbfa
ip-10-1-46-28.us-west-2.compute.internal  2600:1f13:520:1305:5ee5:b994:c0c2:e4da
```

Pod IP를 검사하여 IPv6 주소를 받고 있는지 확인할 수도 있습니다.
```bash
kubectl get pods -A -o custom-columns='NAME:.metadata.name,NodeIP:.status.hostIP,PodIP:status.podIP'

# 예제 출력
NAME                                                     NodeIP                                  PodIP
karpenter-5fd95dffb8-l8j26                               2600:1f13:520:1304:15b2:b8a3:7f63:cbfa  2600:1f13:520:1304:a79b::
karpenter-5fd95dffb8-qpv55                               2600:1f13:520:1303:c87:4a71:b9ea:417c   2600:1f13:520:1303:60ac::
```

</details>

---

## 단계 3: IPv6용 Spark 작업 구성

`data-stacks/spark-on-eks/examples/pyspark-pi-job.yaml`의 예제 매니페스트에는 필요한 IPv6 설정이 주석 처리되어 있습니다. 작업에 대해 주석을 해제해야 합니다.

#### A. Driver 서비스용 SparkConf 업데이트

이렇게 하면 Spark Driver의 네트워크 서비스가 IPv6 주소를 받아 Executor가 연결할 수 있습니다.

```yaml title="pyspark-pi-job.yaml"
spec:
  sparkConf:
    # ...
    # ipv6 구성
    "spark.kubernetes.driver.service.ipFamilies": "IPv6"
    "spark.kubernetes.driver.service.ipFamilyPolicy": "SingleStack"
```

#### B. Driver 및 Executor용 IMDS 엔드포인트 구성

이것은 Spark가 Amazon S3와 같은 다른 AWS 서비스에 안전하게 접근할 수 있도록 하는 데 중요합니다.

:::info IMDS란 무엇이며 왜 필요한가요?

EC2 인스턴스 메타데이터 서비스(IMDS)는 인스턴스 ID와 같은 인스턴스에 대한 데이터를 제공하고 Amazon S3와 같은 서비스에 접근하기 위한 임시 AWS 자격 증명을 가져오는 데도 사용되는 모든 EC2 인스턴스에서 사용할 수 있는 서비스입니다.

기본적으로 AWS SDK는 고정된 IPv4 엔드포인트(`http://169.254.169.254`)를 사용하여 IMDS에 연결합니다. IPv6 클러스터에서 Pod는 이 IPv4 주소에 도달할 수 없는 네트워크 환경에 있을 수 있습니다.

`AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE` 환경 변수를 `IPv6`로 설정하면 AWS SDK가 대신 IPv6 엔드포인트(`http://[fd00:ec2::254]`)를 사용하도록 지시합니다. 이 기능은 **Nitro 기반 EC2 인스턴스**에서만 지원됩니다.
:::

Driver와 Executor Pod 모두에 이 환경 변수를 설정해야 합니다.

```yaml title="pyspark-pi-job.yaml"
spec:
  driver:
    # ...
    # IMDS와 통신할 때 ipv6를 사용하도록 java sdk에 지시
    env:
      - name: AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE
        value: IPv6
---
spec:
  executor:
    # ...
    # IMDS와 통신할 때 ipv6를 사용하도록 java sdk에 지시
    env:
      - name: AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE
        value: IPv6
```

:::caution
IMDS 엔드포인트를 구성하지 않으면 Amazon S3와 상호 작용하는 모든 Spark 작업이 인증 오류로 실패합니다.
:::

---

## 정리

진행 중인 요금을 피하려면 메인 [인프라 배포 가이드](./infra.md#cleanup)의 지침을 따라 리소스를 정리합니다. IPv4 및 IPv6 배포 모두 동일한 프로세스가 적용됩니다.
