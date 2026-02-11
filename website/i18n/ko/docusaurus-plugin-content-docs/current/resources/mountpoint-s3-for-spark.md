---
sidebar_position: 3
sidebar_label: Spark 워크로드용 Mountpoint-S3
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '@site/src/components/CollapsibleContent';

import CodeBlock from '@theme/CodeBlock';
import DaemonSetWithConfig from '!!raw-loader!@site/../analytics/terraform/spark-k8s-operator/examples/mountpoint-s3-spark/mountpoint-s3-daemonset.yaml';

# Spark 워크로드용 Mountpoint-S3
[SparkOperator](https://github.com/kubeflow/spark-operator)가 관리하는 [SparkApplication](https://www.kubeflow.org/docs/components/spark-operator/user-guide/using-sparkapplication/) Custom Resource Definition(CRD)으로 작업할 때 여러 의존성 JAR 파일을 처리하는 것은 상당한 과제가 될 수 있습니다. 전통적으로 이러한 JAR 파일은 컨테이너 이미지 내에 번들로 제공되어 여러 가지 비효율성을 초래합니다:

* **빌드 시간 증가:** 빌드 프로세스 중에 JAR 파일을 다운로드하고 추가하면 컨테이너 이미지의 빌드 시간이 크게 늘어납니다.
* **이미지 크기 증가:** JAR 파일을 컨테이너 이미지에 직접 포함하면 크기가 증가하여 작업을 실행하기 위해 이미지를 풀링할 때 다운로드 시간이 길어집니다.
* **빈번한 재빌드:** 의존성 JAR 파일에 대한 업데이트 또는 추가는 컨테이너 이미지를 재빌드하고 재배포해야 하므로 운영 오버헤드가 더욱 증가합니다.

[Mountpoint for Amazon S3](https://aws.amazon.com/s3/features/mountpoint/)는 이러한 과제에 대한 효과적인 솔루션을 제공합니다. 오픈 소스 파일 클라이언트인 Mountpoint-S3를 사용하면 컴퓨팅 인스턴스에 S3 버킷을 마운트하여 로컬 가상 파일 시스템으로 액세스할 수 있습니다. 로컬 파일 시스템 API 호출을 S3 객체에 대한 REST API 호출로 자동 변환하여 Spark 작업과 원활하게 통합됩니다.

## Mountpoint-S3란?

[Mountpoint-S3](https://github.com/awslabs/mountpoint-s3)는 AWS가 개발한 오픈 소스 파일 클라이언트로 파일 작업을 S3 API 호출로 변환하여 애플리케이션이 [Amazon S3](https://aws.amazon.com/s3/) 버킷을 로컬 디스크처럼 상호 작용할 수 있게 합니다. [Mountpoint for Amazon S3](https://aws.amazon.com/s3/features/mountpoint/)는 잠재적으로 많은 클라이언트에서 한 번에 대용량 객체에 대한 높은 읽기 처리량이 필요하고 한 번에 단일 클라이언트에서 새 객체를 순차적으로 쓰는 애플리케이션에 최적화되어 있습니다. 기존 S3 액세스 방법에 비해 상당한 성능 향상을 제공하여 데이터 집약적 워크로드나 AI/ML 학습에 이상적입니다.

[Mountpoint for Amazon S3](https://aws.amazon.com/s3/features/mountpoint/)는 주로 [AWS Common Runtime(CRT)](https://docs.aws.amazon.com/sdkref/latest/guide/common-runtime.html) 라이브러리를 기반으로 하여 높은 처리량 성능에 최적화되어 있습니다. CRT 라이브러리는 AWS 서비스에 맞게 특별히 조정된 고성능과 낮은 리소스 사용량을 제공하도록 설계된 라이브러리 및 모듈 모음입니다. 높은 처리량 성능을 가능하게 하는 CRT 라이브러리의 주요 기능은 다음과 같습니다:

 * **효율적인 I/O 관리:** CRT 라이브러리는 논블로킹 I/O 작업에 최적화되어 지연 시간을 줄이고 네트워크 대역폭 활용을 극대화합니다.
 * **가볍고 모듈식 설계:** 라이브러리는 최소한의 오버헤드로 가볍게 설계되어 높은 부하에서도 효율적으로 작동합니다. 모듈식 아키텍처는 필요한 구성 요소만 로드되도록 하여 성능을 더욱 향상시킵니다.
 * **고급 메모리 관리:** CRT는 메모리 사용량을 최소화하고 가비지 컬렉션 오버헤드를 줄이기 위해 고급 메모리 관리 기술을 사용하여 더 빠른 데이터 처리와 지연 시간 감소로 이어집니다.
 * **최적화된 네트워크 프로토콜:** CRT 라이브러리에는 AWS 환경에 특별히 조정된 HTTP/2와 같은 네트워크 프로토콜의 최적화된 구현이 포함되어 있습니다. 이러한 최적화는 대규모 Spark 워크로드에 중요한 S3와 컴퓨팅 인스턴스 간의 빠른 데이터 전송을 보장합니다.

## EKS에서 Mountpoint-S3 사용
Spark 워크로드의 경우 **Spark 애플리케이션을 위해 S3에 있는 외부 JAR 로드**에 특히 중점을 둡니다. Mountpoint-S3의 두 가지 주요 배포 전략을 살펴보겠습니다:
1. [EKS 관리형 애드온 CSI 드라이버](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)와 Persistent Volumes(PV) 및 Persistent Volume Claims(PVC) 활용
2. [USERDATA](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html) 스크립트 또는 DaemonSet을 사용하여 노드 수준에서 Mountpoint-S3 배포

첫 번째 접근 방식은 생성된 PV가 개별 Pod에서 사용할 수 있기 때문에 *Pod* 수준에서 마운트하는 것으로 간주됩니다. 두 번째 접근 방식은 S3가 호스트 노드 자체에 마운트되기 때문에 *노드* 수준에서 마운트하는 것으로 간주됩니다. 각 접근 방식은 아래에서 자세히 설명하며, 특정 사용 사례에 가장 효과적인 솔루션을 결정하는 데 도움이 되도록 각각의 강점과 고려 사항을 강조합니다.

| 메트릭              | Pod 수준 | 노드 수준 |
| :----------------: | :------ | :---- |
| 액세스 제어            |   서비스 역할과 RBAC를 통해 세분화된 액세스 제어를 제공하여 PVC 액세스를 특정 Pod로 제한합니다. 마운트된 S3 버킷이 노드의 모든 Pod에서 액세스할 수 있는 호스트 수준 마운트에서는 불가능합니다.   | 구성을 단순화하지만 Pod 수준 마운트가 제공하는 세분화된 제어가 부족합니다. |
| 확장성 및 오버헤드 |   개별 PVC 관리가 포함되어 대규모 환경에서 오버헤드가 증가할 수 있습니다.   | 구성 복잡성을 줄이지만 Pod 간 격리가 적습니다. |
| 성능 고려 사항|  개별 Pod에 대해 예측 가능하고 격리된 성능을 제공합니다.   | 동일한 노드의 여러 Pod가 동일한 S3 버킷에 액세스하면 경합이 발생할 수 있습니다. |
| 유연성 및 사용 사례 |  다른 Pod가 다른 데이터셋에 액세스해야 하거나 엄격한 보안 및 컴플라이언스 제어가 필요한 사용 사례에 가장 적합합니다.   | 노드의 모든 Pod가 동일한 데이터셋을 공유할 수 있는 환경(예: 배치 처리 작업 또는 공통 의존성이 필요한 Spark 작업 실행 시)에 이상적입니다. |

## 리소스 할당
Mountpoint-s3 솔루션을 구현하기 전에 AWS 클라우드 리소스를 할당해야 합니다. 아래 지침에 따라 Terraform 스택을 배포합니다. 리소스를 할당하고 EKS 환경을 설정한 후 Mountpoint-S3를 활용하는 두 가지 다른 접근 방식을 자세히 탐색할 수 있습니다.

<CollapsibleContent header={<h2><span>솔루션 리소스 배포</span></h2>}>

이 [예제](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/spark-k8s-operator)에서는 오픈 소스 Spark Operator로 Spark 작업을 실행하는 데 필요한 다음 리소스를 프로비저닝합니다.

이 예제는 새 VPC에 Spark K8s Operator를 실행하는 EKS 클러스터를 배포합니다.

- 새 샘플 VPC, 2개의 프라이빗 서브넷 및 2개의 퍼블릭 서브넷 생성
- 퍼블릭 서브넷용 인터넷 게이트웨이 및 프라이빗 서브넷용 NAT 게이트웨이 생성
- 코어 관리형 노드 그룹, 온디맨드 노드 그룹 및 Spark 워크로드용 스팟 노드 그룹과 함께 퍼블릭 엔드포인트(데모 목적으로만)가 있는 EKS 클러스터 컨트롤 플레인 생성
- Metrics server, Cluster Autoscaler, Spark-k8s-operator, Apache Yunikorn, Karpenter, Grafana, AMP 및 Prometheus 서버 배포

### 사전 요구 사항

다음 도구가 머신에 설치되어 있는지 확인하세요.

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### 배포

저장소를 복제합니다.

```bash
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks
export DOEKS_HOME=$(pwd)
```

DOEKS_HOME이 설정 해제된 경우 data-on-eks 디렉토리에서 `export
DATA_ON_EKS=$(pwd)`를 사용하여 항상 수동으로 설정할 수 있습니다.

예제 디렉토리 중 하나로 이동하여 `install.sh` 스크립트를 실행합니다.

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator
chmod +x install.sh
./install.sh
```

이제 설치 중에 생성된 버킷 이름을 보유하는 S3_BUCKET 변수를 생성합니다. 이 버킷은 이후 예제에서 출력 데이터를 저장하는 데 사용됩니다. S3_BUCKET이 설정 해제된 경우 다음 명령을 다시 실행할 수 있습니다.

```bash
export S3_BUCKET=$(terraform output -raw s3_bucket_id_spark_history_server)
echo $S3_BUCKET
```

</CollapsibleContent>

## 접근 방식 1: *Pod 수준*에서 EKS에 Mountpoint-S3 배포

Pod 수준에서 Mountpoint-S3를 배포하면 [EKS 관리형 애드온 CSI 드라이버](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)와 Persistent Volumes(PV) 및 Persistent Volume Claims(PVC)를 사용하여 Pod 내에 S3 버킷을 직접 마운트합니다. 이 방법을 사용하면 어떤 Pod가 특정 S3 버킷에 액세스할 수 있는지에 대한 세분화된 제어가 가능하여 필요한 워크로드만 필요한 데이터에 액세스할 수 있도록 합니다.

[Mountpoint-S3](https://github.com/awslabs/mountpoint-s3)가 활성화되고 PV가 생성되면 S3 버킷은 클러스터 수준 리소스가 되어 PV를 참조하는 PVC를 생성하여 모든 Pod가 액세스를 요청할 수 있습니다. 어떤 Pod가 특정 PVC에 액세스할 수 있는지에 대한 세분화된 제어를 달성하려면 네임스페이스 내에서 서비스 역할을 사용할 수 있습니다. Pod에 특정 서비스 계정을 할당하고 역할 기반 액세스 제어(RBAC) 정책을 정의하여 어떤 Pod가 특정 PVC에 바인딩할 수 있는지 제한할 수 있습니다. 이렇게 하면 권한이 부여된 Pod만 S3 버킷을 마운트할 수 있어 hostPath가 노드의 모든 Pod에서 액세스할 수 있는 호스트 수준 마운트에 비해 더 엄격한 보안 및 액세스 제어를 제공합니다.

이 접근 방식은 [EKS 관리형 애드온 CSI 드라이버](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)를 사용하여 단순화할 수도 있습니다. 그러나 이것은 taints/tolerations를 지원하지 않으므로 GPU와 함께 사용할 수 없습니다. 또한 Pod가 마운트를 공유하지 않아 캐시를 공유하지 않기 때문에 더 많은 S3 API 호출로 이어질 수 있습니다.

 이 접근 방식을 배포하는 방법에 대한 자세한 내용은 [배포 지침](https://awslabs.github.io/data-on-eks/docs/resources/mountpoint-s3)을 참조하세요.

## 접근 방식 2: *노드 수준*에서 EKS에 Mountpoint-S3 배포

노드 수준에서 S3 버킷을 마운트하면 빌드 시간을 줄이고 배포를 가속화하여 SparkApplication의 의존성 JAR 파일 관리를 간소화할 수 있습니다. **USERDATA** 또는 **DaemonSet**을 사용하여 구현할 수 있습니다. USERDATA는 [Mountpoint-S3](https://github.com/awslabs/mountpoint-s3)를 구현하는 데 선호되는 방법입니다. 그러나 EKS 클러스터에 중지할 수 없는 정적 노드가 있는 경우 DaemonSet 접근 방식이 대안을 제공합니다. DaemonSet 접근 방식을 구현하기 전에 활성화해야 하는 모든 보안 메커니즘을 이해해야 합니다.

### 접근 방식 2.1: USERDATA 사용

이 접근 방식은 노드가 초기화될 때 user-data 스크립트가 실행되므로 새 클러스터 또는 워크로드를 실행하도록 오토스케일링이 사용자 정의된 경우에 권장됩니다. 아래 스크립트를 사용하여 Pod를 호스팅하는 EKS 클러스터에서 노드를 초기화할 때 S3 버킷이 마운트되도록 노드를 업데이트할 수 있습니다. 아래 스크립트는 Mountpoint S3 패키지의 다운로드, 설치 및 실행을 설명합니다. 이 애플리케이션에 대해 설정되고 아래에 정의된 몇 가지 인수가 있으며 사용 사례에 따라 변경할 수 있습니다. 이러한 인수 및 기타 인수에 대한 자세한 내용은 [여기](https://github.com/awslabs/mountpoint-s3/blob/main/doc/CONFIGURATION.md#caching-configuration)에서 찾을 수 있습니다.

* metadata-ttl: jar 파일은 읽기 전용으로 사용되며 변경되지 않으므로 무기한으로 설정됩니다.
* allow-others: SSM을 사용할 때 노드가 마운트된 볼륨에 액세스할 수 있도록 설정됩니다.
* cache: 연속 재읽기를 위해 파일을 캐시에 저장하여 수행해야 하는 S3 API 호출을 제한하기 위해 캐싱을 활성화하도록 설정됩니다.

:::note
이러한 동일한 인수는 DaemonSet 접근 방식에서도 사용할 수 있습니다. 이 예제에서 설정된 이러한 인수 외에도 추가 [로깅 및 디버깅](https://github.com/awslabs/mountpoint-s3/blob/main/doc/LOGGING.md)을 위한 다른 옵션도 있습니다.
:::

[Karpenter](https://karpenter.sh/)로 오토스케일링할 때 이 방법은 더 많은 유연성과 성능을 허용합니다. 예를 들어 terraform 코드에서 Karpenter를 구성할 때 다양한 유형의 노드에 대한 user data는 워크로드에 따라 다른 버킷으로 고유할 수 있으므로 Pod가 스케줄되고 특정 의존성 세트가 필요할 때 Taints 및 Tolerations를 통해 Karpenter가 고유한 user data가 있는 특정 인스턴스 유형을 할당하여 Pod가 액세스할 수 있도록 의존성 파일이 있는 올바른 버킷이 노드에 마운트되도록 합니다. 또한 사용자 스크립트는 새로 할당된 노드가 구성된 OS에 따라 달라집니다.

#### USERDATA 스크립트:

```
#!/bin/bash
yum update -y
yum install -y wget
wget https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.rpm
yum install -y mount-s3.rpm mkdir -p /mnt/s3
/opt/aws/mountpoint-s3/bin/mount-s3 --metadata-ttl indefinite --allow-other --cache /tmp <S3_BUCKET_NAME> /mnt/s3
```

### 접근 방식 2.2: DaemonSet 사용

이 접근 방식은 기존 클러스터에 권장됩니다. 이 접근 방식은 2개의 리소스로 구성됩니다. 노드에 S3 Mount Point 패키지를 유지 관리하는 스크립트가 있는 ConfigMap과 클러스터의 모든 노드에서 Pod를 실행하여 노드에서 스크립트를 실행하는 DaemonSet입니다.

ConfigMap 스크립트는 60초마다 mountPoint를 확인하고 문제가 있으면 다시 마운트하는 루프를 실행합니다. 마운트 위치, 캐시 위치, S3 버킷 이름, 로그 파일 위치, 패키지 설치 URL 및 설치된 패키지 위치에 대해 변경할 수 있는 여러 환경 변수가 있습니다. 이러한 변수는 기본값으로 유지할 수 있으며 S3 버킷 이름만 실행하는 데 필요합니다.

DaemonSet Pod는 노드에 스크립트를 복사하고, 실행을 허용하도록 권한을 변경한 다음 마지막으로 스크립트를 실행합니다. Pod는 [nsenter](https://man7.org/linux/man-pages/man1/nsenter.1.html)에 액세스하기 위해 ```util-linux```를 설치하며, 이를 통해 Pod가 노드 공간에서 스크립트를 실행할 수 있어 S3 버킷이 Pod에 의해 노드에 직접 마운트될 수 있습니다.
:::danger
DaemonSet Pod는 ```securityContext```가 privileged여야 하고 ```hostPID```, ```hostIPC``` 및 ```hostNetwork```가 true로 설정되어야 합니다.
이러한 항목이 이 솔루션에 필요한 이유와 보안 영향에 대해 아래에서 검토하세요.
:::
1. ```securityContext: privileged```
    * **목적:** privileged 모드는 컨테이너에 호스트의 모든 리소스에 대한 완전한 액세스를 제공하며, 호스트의 루트 액세스와 유사합니다.
    * 소프트웨어 패키지를 설치하고, 시스템을 구성하고, S3 버킷을 호스트에 마운트하려면 컨테이너에 상승된 권한이 필요할 수 있습니다. privileged 모드가 없으면 컨테이너에 호스트 파일 시스템 및 네트워크 인터페이스에서 이러한 작업을 수행할 충분한 권한이 없을 수 있습니다.
2. hostPID
    * **목적:** nsenter를 사용하면 호스트의 PID 네임스페이스를 포함한 다양한 네임스페이스에 진입할 수 있습니다.
    * nsenter를 사용하여 호스트의 PID 네임스페이스에 진입할 때 컨테이너는 호스트의 PID 네임스페이스에 액세스해야 합니다. 따라서 ```hostPID: true```를 활성화하면 호스트의 프로세스와 상호 작용할 수 있으며, 이는 패키지 설치 또는 mountpoint-s3와 같은 호스트 수준 프로세스 가시성이 필요한 명령 실행에 중요합니다.
3. hostIPC
    * **목적:** hostIPC를 사용하면 컨테이너가 공유 메모리를 포함하는 호스트의 프로세스 간 통신 네임스페이스를 공유할 수 있습니다.
    * nsenter 명령 또는 실행할 스크립트가 호스트의 공유 메모리 또는 기타 IPC 메커니즘을 포함하는 경우 ```hostIPC: true```가 필요합니다. hostPID보다 덜 일반적이지만 특히 스크립트가 IPC에 의존하는 호스트 프로세스와 상호 작용해야 하는 경우 nsenter가 관련될 때 종종 함께 활성화됩니다.
4. hostNetwork
    * **목적:** hostNetwork를 사용하면 컨테이너가 호스트의 네트워크 네임스페이스를 사용할 수 있어 컨테이너가 호스트의 IP 주소와 네트워크 인터페이스에 액세스할 수 있습니다.
    * 설치 프로세스 중에 스크립트는 인터넷에서 패키지를 다운로드해야 할 수 있습니다(예: mountpoint-s3 패키지를 호스팅하는 저장소에서). ```hostNetwork: true```로 hostNetwork를 활성화하면 다운로드 프로세스가 호스트의 네트워크 인터페이스에 직접 액세스할 수 있어 네트워크 격리 문제를 방지합니다.
:::warning
이 샘플 코드는 작업을 실행하고 DaemonSet을 호스팅하기 위해 ```spark-team-a``` 네임스페이스를 사용합니다. 이는 주로 Terraform 스택이 이미 이 네임스페이스에 대한 [IRSA](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/setting-up-enable-IAM.html)를 설정하고 서비스 계정이 모든 S3 버킷에 액세스할 수 있도록 하기 때문입니다.
프로덕션에서 사용할 때는 최소 권한 정책을 따르고 [IAM 역할 모범 사례](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)를 따르는 자체 별도의 네임스페이스, 서비스 계정 및 IAM 역할을 생성해야 합니다.
:::

<details>
<summary> DaemonSet을 보려면 클릭하여 콘텐츠를 토글하세요!</summary>

<CodeBlock language="yaml">{DaemonSetWithConfig}</CodeBlock>
</details>


## Spark 작업 실행
다음은 DaemonSet을 사용한 접근 방식 2로 시나리오를 테스트하는 단계입니다:

1. [Spark Operator 리소스](#resource-allocation) 배포
2. S3 버킷 준비
    1. ``` cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator/examples/mountpoint-s3-spark/ ```
    2. ``` chmod +x copy-jars-to-s3.sh ```
    3. ``` ./copy-jars-to-s3.sh ```
3. Kubeconfig 설정
    1. ```aws eks update-kubeconfig --name spark-operator-doeks```
4. DaemonSet 적용
    1. ```kubectl apply -f mountpoint-s3-daemonset.yaml ```
4. Spark 작업 샘플 적용
    1. 1. ```kubectl apply -f mountpoint-s3-spark-job.yaml ```
4. 작업 실행 보기
    * 이 SparkApplication CRD가 실행되는 동안 로그를 볼 수 있는 몇 가지 다른 리소스가 있습니다. 이러한 각 로그는 모든 로그를 동시에 보기 위해 별도의 터미널에 있어야 합니다.
        1. **spark operator**
            1. ``` kubectl -n spark-operator get pods```
            2. spark operator pod의 이름을 복사합니다.
            2. ``` kubectl -n spark-operator logs -f <POD_NAME>```
        2. **spark-team-a Pod**
            1. SparkApplication의 드라이버 및 exec Pod에 대한 로그를 얻으려면 먼저 Pod가 실행 중인지 확인해야 합니다. wide 출력을 사용하면 Pod가 실행 중인 노드를 볼 수 있고 ```-w```를 사용하면 각 Pod의 상태 업데이트를 볼 수 있습니다.
            2. ``` kubectl -n spark-team-a get pods -o wide -w ```
        3. **driver Pod**
            1. 드라이버 Pod가 실행 중 상태가 되면(이전 터미널에서 볼 수 있음) 드라이버 Pod의 로그를 얻을 수 있습니다.
            2. ``` kubectl -n spark-team-a logs -f taxi-trip ```
        4. **exec Pod**
            1. exec Pod가 실행 중 상태가 되면(이전 터미널에서 볼 수 있음) exec Pod의 로그를 얻을 수 있습니다. 로그를 얻기 전에 exec-1이 실행 중인지 확인하세요. 그렇지 않으면 실행 중인 다른 exec Pod를 사용하세요.
            2. 2. ``` kubectl -n spark-team-a logs -f taxi-trip-exec-1 ```


## 확인
작업이 완료되면 exec 로그에서 처리를 위해 노드의 로컬 mountpoint-s3 위치에서 spark Pod로 파일이 복사되고 있음을 볼 수 있습니다.
```
24/08/13 00:08:46 INFO Utils: Copying /mnt/s3/jars/hadoop-aws-3.3.1.jar to /var/data/spark-5eae56b3-3999-4c2f-8004-afc46d1c82ba/spark-a433e7ce-db5d-4fd5-b344-abf751f43bd3/-14716855631723507720806_cache
24/08/13 00:08:46 INFO Utils: Copying /var/data/spark-5eae56b3-3999-4c2f-8004-afc46d1c82ba/spark-a433e7ce-db5d-4fd5-b344-abf751f43bd3/-14716855631723507720806_cache to /opt/spark/work-dir/./hadoop-aws-3.3.1.jar
24/08/13 00:08:46 INFO Executor: Adding file:/opt/spark/work-dir/./hadoop-aws-3.3.1.jar to class loader
24/08/13 00:08:46 INFO Executor: Fetching file:/mnt/s3/jars/aws-java-sdk-bundle-1.12.647.jar with timestamp 1723507720806
24/08/13 00:08:46 INFO Utils: Copying /mnt/s3/jars/aws-java-sdk-bundle-1.12.647.jar to /var/data/spark-5eae56b3-3999-4c2f-8004-afc46d1c82ba/spark-a433e7ce-db5d-4fd5-b344-abf751f43bd3/14156613201723507720806_cache
24/08/13 00:08:47 INFO Utils: Copying /var/data/spark-5eae56b3-3999-4c2f-8004-afc46d1c82ba/spark-a433e7ce-db5d-4fd5-b344-abf751f43bd3/14156613201723507720806_cache to /opt/spark/work-dir/./aws-java-sdk-bundle-1.12.647.jar
```
또한 spark-team-a Pod의 상태를 볼 때 다른 노드가 온라인으로 오는 것을 볼 수 있습니다. 이 노드는 SparkApplication을 실행하도록 최적화되어 있으며 온라인으로 오자마자 DaemonSet Pod도 스핀업되어 새 노드에서 실행을 시작하므로 해당 새 노드에서 실행되는 모든 Pod도 S3 버킷에 액세스할 수 있습니다. Systems Sessions Manager(SSM)를 사용하여 노드 중 하나에 연결하고 다음을 실행하여 mountpoint-s3 패키지가 다운로드 및 설치되었는지 확인할 수 있습니다:
* ```mount-s3 --version```

여러 Pod에 대해 노드 수준에서 mountpoint-S3를 사용하는 가장 큰 장점은 다른 Pod가 자체 API 호출을 수행하지 않고도 동일한 데이터에 액세스할 수 있도록 데이터를 캐시할 수 있다는 것입니다. *karpenter-spark-compute-optimized* 최적화 노드가 할당되면 Sessions Manager(SSM)를 사용하여 노드에 연결하고 작업이 실행되고 볼륨이 마운트될 때 파일이 노드에 캐시될 것인지 확인할 수 있습니다. 다음에서 캐시를 볼 수 있습니다:
* ```sudo ls /tmp/mountpoint-cache/```

## 결론

CRT 라이브러리를 활용하여 Mountpoint for Amazon S3는 S3에 저장된 대량의 데이터를 효율적으로 관리하고 액세스하는 데 필요한 높은 처리량과 낮은 지연 시간을 제공할 수 있습니다. 이를 통해 의존성 JAR 파일을 컨테이너 이미지와 별도로 외부에서 저장하고 관리하여 Spark 작업과 분리할 수 있습니다. 또한 JAR을 S3에 저장하면 여러 Pod가 이를 소비할 수 있어 S3가 더 큰 컨테이너 이미지에 비해 비용 효율적인 스토리지 솔루션을 제공하므로 비용이 절감됩니다. S3는 또한 거의 무제한의 스토리지를 제공하여 의존성을 쉽게 확장하고 관리할 수 있습니다.

Mountpoint-S3는 데이터 및 AI/ML 워크로드를 위해 S3 스토리지를 EKS와 통합하는 다재다능하고 강력한 방법을 제공합니다. PV 및 PVC를 사용하여 Pod 수준에서 배포하든, USERDATA 또는 DaemonSet을 사용하여 노드 수준에서 배포하든, 각 접근 방식에는 고유한 장점과 절충점이 있습니다. 이러한 옵션을 이해함으로써 EKS에서 데이터 및 AI/ML 워크플로를 최적화하기 위한 정보에 입각한 결정을 내릴 수 있습니다.
