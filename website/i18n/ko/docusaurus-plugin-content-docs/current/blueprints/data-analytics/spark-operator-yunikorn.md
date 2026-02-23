---
sidebar_position: 2
sidebar_label: YuniKorn이 포함된 Spark Operator
hide_table_of_contents: true
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '@site/src/components/CollapsibleContent';

import TaxiTripExecute from './_taxi_trip_exec.md'
import ReplaceS3BucketPlaceholders from './_replace_s3_bucket_placeholders.mdx';

import CodeBlock from '@theme/CodeBlock';

# YuniKorn이 포함된 Spark Operator

## 소개

Data on EKS 블루프린트의 EKS 클러스터 설계는 Spark Operator 및 배치 스케줄러인 Apache YuniKorn으로 Spark 애플리케이션을 실행하도록 최적화되어 있습니다. 이 블루프린트는 Karpenter를 활용하여 워커 노드를 스케일링하고, AWS for FluentBit을 로깅에 사용하며, Prometheus, Amazon Managed Prometheus 및 오픈 소스 Grafana를 관측성에 사용합니다. 또한 Spark History Server Live UI는 NLB 및 NGINX 인그레스 컨트롤러를 통해 실행 중인 Spark 작업을 모니터링하도록 구성됩니다.

<CollapsibleContent header={<h2><span>Karpenter를 사용한 Spark 워크로드</span></h2>}>

Karpenter를 오토스케일러로 사용하면 Spark 워크로드에 대한 관리형 노드 그룹 및 Cluster Autoscaler가 필요 없습니다. 이 설계에서 Karpenter와 해당 NodePool은 사용자 요구에 따라 인스턴스 유형을 동적으로 선택하여 온디맨드 및 스팟 인스턴스를 모두 생성하는 역할을 합니다. Karpenter는 더 효율적인 노드 스케일링과 더 빠른 응답 시간으로 Cluster Autoscaler에 비해 향상된 성능을 제공합니다. Karpenter의 주요 기능에는 리소스에 대한 수요가 없을 때 리소스 활용도를 최적화하고 비용을 절감하는 제로에서 스케일링하는 기능이 포함됩니다. 또한 Karpenter는 컴퓨팅, 메모리 및 GPU 집약적 작업과 같은 다양한 워크로드 유형에 필요한 인프라를 정의하는 데 더 큰 유연성을 허용하는 여러 NodePool을 지원합니다. 또한 Karpenter는 Kubernetes와 원활하게 통합되어 관찰된 워크로드 및 스케일링 이벤트에 따라 클러스터 크기를 자동으로 실시간으로 조정합니다. 이를 통해 Spark 애플리케이션 및 기타 워크로드의 끊임없이 변화하는 요구에 적응하는 보다 효율적이고 비용 효과적인 EKS 클러스터 설계가 가능합니다.

![img.png](img/eks-spark-operator-karpenter.png)

블루프린트는 아래 탭에서 Karpenter NodePool 및 EC2 클래스를 구성합니다.

<Tabs>
<TabItem value="spark-memory-optimized" label="spark-memory-optimized">

이 NodePool은 xlarge에서 8xlarge 크기까지의 r5d 인스턴스 유형을 사용하며, 더 많은 메모리가 필요한 Spark 작업에 적합합니다.

Karpenter 구성을 보려면 [여기에서 `addons.tf` 파일을 검토하세요](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/addons.tf#L177-L223)
</TabItem>

<TabItem value="spark-graviton-memory-optimized" label="spark-graviton-memory-optimized">

이 NodePool은 4xlarge에서 16xlarge 크기까지의 r6g, r6gd, r7g, r7gd 및 r8g 인스턴스 유형을 사용합니다

Karpenter 구성을 보려면 [여기에서 `addons.tf` 파일을 검토하세요](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/addons.tf#L117-L170)
</TabItem>


<TabItem value="spark-compute-optimized" label="spark-compute-optimized">

이 NodePool은 4xlarge에서 24xlarge 크기까지의 C5d 인스턴스 유형을 사용하며, 더 많은 CPU 시간이 필요한 Spark 작업에 적합합니다.

Karpenter 구성을 보려면 [여기에서 `addons.tf` 파일을 검토하세요](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/addons.tf#L63-L110)
</TabItem>

<TabItem value="spark-vertical-ebs-scale" label="spark-vertical-ebs-scale">

이 NodePool은 광범위한 EC2 인스턴스 유형을 사용하며, 인스턴스 부트스트래핑 시 보조 EBS 볼륨을 생성하고 마운트합니다. 이 볼륨 크기는 EC2 인스턴스의 코어 수에 따라 스케일링됩니다.
이는 Spark 워크로드에 사용할 수 있는 보조 스토리지 위치를 제공하여 인스턴스의 루트 볼륨에 대한 부하를 줄이고 시스템 데몬이나 kubelet에 대한 영향을 방지합니다. 더 큰 노드는 더 많은 파드를 수용할 수 있으므로 부트스트래핑은 더 큰 인스턴스에 대해 더 큰 볼륨을 생성합니다.

Karpenter 구성을 보려면 [여기에서 `addons.tf` 파일을 검토하세요](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/addons.tf#L230-L355)
</TabItem>

</Tabs>
</CollapsibleContent>

<CollapsibleContent header={<h2><span>Spark Shuffle 데이터용 NVMe SSD 인스턴스 스토리지</span></h2>}>

이 EKS 클러스터 설계의 NodePool은 Spark 워크로드의 shuffle 스토리지로 사용하기 위해 각 노드에 NVMe SSD 인스턴스 스토리지를 활용한다는 점에 유의해야 합니다. 이러한 고성능 스토리지 옵션은 모든 "d" 유형 인스턴스에서 사용할 수 있습니다.

Spark용 shuffle 스토리지로 NVMe SSD 인스턴스 스토리지를 사용하면 수많은 이점이 있습니다. 첫째, 지연 시간이 짧고 처리량이 높은 데이터 액세스를 제공하여 Spark의 shuffle 성능을 크게 향상시킵니다. 이를 통해 작업 완료 시간이 빨라지고 전반적인 애플리케이션 성능이 향상됩니다. 둘째, 로컬 SSD 스토리지를 사용하면 shuffle 작업 중 병목 현상이 될 수 있는 EBS 볼륨과 같은 원격 스토리지 시스템에 대한 의존도가 줄어듭니다. 이는 또한 shuffle 데이터용 추가 EBS 볼륨 프로비저닝 및 관리와 관련된 비용을 줄입니다. 마지막으로 NVMe SSD 스토리지를 활용하면 EKS 클러스터 설계가 더 나은 리소스 활용도와 향상된 성능을 제공하여 Spark 애플리케이션이 더 큰 데이터 세트를 처리하고 더 효율적으로 복잡한 분석 워크로드를 처리할 수 있습니다. 이 최적화된 스토리지 솔루션은 궁극적으로 Kubernetes에서 Spark 워크로드를 실행하기 위해 맞춤화된 더 확장 가능하고 비용 효과적인 EKS 클러스터에 기여합니다.

NVMe SSD 인스턴스 스토리지는 인스턴스가 시작될 때 부트스트래핑 스크립트에 의해 구성됩니다([Karpenter NodePool은 `instanceStorePolicy: RAID0`으로 구성됩니다](https://karpenter.sh/docs/concepts/nodeclasses/#specinstancestorepolicy)). NVMe 장치는 단일 RAID0(스트라이프) 어레이로 결합된 다음 `/mnt/k8s-disks/0`에 마운트됩니다. 이 디렉토리는 `/var/lib/kubelet`, `/var/lib/containerd` 및 `/var/log/pods`와 추가로 연결되어 해당 위치에 기록된 모든 데이터가 NVMe 장치에 저장되도록 합니다. 파드 내부에 기록된 데이터는 이러한 디렉토리 중 하나에 기록되므로 파드는 hostPath 마운트나 PersistentVolume을 활용하지 않고도 고성능 스토리지의 이점을 누릴 수 있습니다.

</CollapsibleContent>

<CollapsibleContent header={<h2><span>Spark Operator</span></h2>}>

Apache Spark용 Kubernetes Operator는 Kubernetes에서 Spark 애플리케이션을 지정하고 실행하는 것을 다른 워크로드를 실행하는 것처럼 쉽고 관용적으로 만드는 것을 목표로 합니다.

* SparkApplication 객체의 생성, 업데이트 및 삭제 이벤트를 감시하고 감시 이벤트에 따라 동작하는 SparkApplication 컨트롤러
* 컨트롤러로부터 받은 제출을 위해 spark-submit을 실행하는 제출 러너
* Spark 파드를 감시하고 컨트롤러에 파드 상태 업데이트를 보내는 Spark 파드 모니터
* 컨트롤러가 추가한 파드의 어노테이션을 기반으로 Spark 드라이버 및 익스큐터 파드에 대한 커스터마이제이션을 처리하는 Mutating Admission Webhook
* 오퍼레이터와 작업하기 위한 sparkctl이라는 명령줄 도구

다음 다이어그램은 Spark Operator 애드온의 다양한 컴포넌트가 상호 작용하고 함께 작동하는 방식을 보여줍니다.

![img.png](img/spark-operator.png)

</CollapsibleContent>

<CollapsibleContent header={<h2><span>솔루션 배포</span></h2>}>

이 [예제](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/spark-k8s-operator)에서는 오픈 소스 Spark Operator 및 Apache YuniKorn으로 Spark 작업을 실행하는 데 필요한 다음 리소스를 프로비저닝합니다.

이 예제는 새 VPC에 Spark K8s Operator를 실행하는 EKS 클러스터를 배포합니다.

- 새 샘플 VPC, 2개의 프라이빗 서브넷, 2개의 퍼블릭 서브넷 및 EKS 파드용 RFC6598 공간(100.64.0.0/10)에 2개의 서브넷을 생성합니다.
- 퍼블릭 서브넷용 인터넷 게이트웨이와 프라이빗 서브넷용 NAT 게이트웨이를 생성합니다.
- 퍼블릭 엔드포인트(데모 목적으로만)가 있는 EKS 클러스터 컨트롤 플레인을 생성하고 벤치마킹 및 코어 서비스용 관리형 노드 그룹과 Spark 워크로드용 Karpenter NodePool을 생성합니다.
- Metrics 서버, Spark-operator, Apache Yunikorn, Karpenter, Cluster Autoscaler, Grafana, AMP 및 Prometheus 서버를 배포합니다.

### 사전 요구 사항

머신에 다음 도구가 설치되어 있는지 확인하세요.

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

DOEKS_HOME이 설정 해제된 경우 data-on-eks 디렉토리에서 `export DATA_ON_EKS=$(pwd)`를 사용하여 항상 수동으로 설정할 수 있습니다.

예제 디렉토리 중 하나로 이동하여 `install.sh` 스크립트를 실행합니다.

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator
chmod +x install.sh
./install.sh
```

이제 설치 중에 생성된 버킷 이름을 보유하는 S3_BUCKET 변수를 만듭니다. 이 버킷은 이후 예제에서 출력 데이터를 저장하는 데 사용됩니다. S3_BUCKET이 설정 해제된 경우 다음 명령을 다시 실행할 수 있습니다.

```bash
export S3_BUCKET=$(terraform output -raw s3_bucket_id_spark_history_server)
echo $S3_BUCKET
```

</CollapsibleContent>

<CollapsibleContent header={<h2><span>Karpenter로 샘플 Spark 작업 실행</span></h2>}>

예제 디렉토리로 이동합니다. 이 파일에서 `<S3_BUCKET>` 자리 표시자를 앞서 생성한 버킷 이름으로 바꿔야 합니다. echo $S3_BUCKET을 실행하여 해당 값을 얻을 수 있습니다.

이를 자동으로 수행하려면 다음을 실행하면 됩니다. .old 백업 파일이 생성되고 자동으로 교체됩니다.


```bash
sed -i.old s/\<S3_BUCKET\>/${S3_BUCKET}/g ./pyspark-pi-job.yaml
```

Spark 작업 제출

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator/examples/karpenter
kubectl apply -f pyspark-pi-job.yaml
```

아래 명령을 사용하여 작업 상태를 모니터링합니다.
Karpenter에 의해 트리거된 새 노드가 표시되고 YuniKorn이 이 노드에 드라이버 파드 1개와 익스큐터 파드 2개를 예약합니다.

```bash
kubectl get pods -n spark-team-a -w
```

파드가 이미 완료된 경우 SparkApplication의 상태를 확인할 수 있습니다:
```bash
kubectl describe sparkapplication pyspark-pi-karpenter -n spark-team-a
```

여러 Karpenter NodePool, SSD 대신 동적 PVC로 EBS, YuniKorn Gang 스케줄링을 활용하기 위해 다음 예제를 시도해 볼 수 있습니다.

## S3에 샘플 데이터 넣기

<TaxiTripExecute />

## Spark shuffle 스토리지용 NVMe 임시 SSD 디스크

드라이버 및 익스큐터 shuffle 스토리지에 NVMe 기반 임시 SSD 디스크를 사용하는 예제 PySpark 작업

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator/examples/karpenter/
```
<!-- Docusaurus will not render the {props.filename} inside of a ```codeblock``` -->
<ReplaceS3BucketPlaceholders filename="./nvme-ephemeral-storage.yaml" />
```bash
sed -i.old s/\<S3_BUCKET\>/${S3_BUCKET}/g ./nvme-ephemeral-storage.yaml
```

이제 버킷 이름이 있으므로 Spark 작업을 생성할 수 있습니다.

```bash
kubectl apply -f nvme-ephemeral-storage.yaml
```

## shuffle 스토리지용 EBS 동적 PVC
드라이버 및 익스큐터 shuffle 스토리지에 동적 PVC를 사용하는 EBS ON_DEMAND 볼륨을 사용하는 예제 PySpark 작업

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator/examples/karpenter/
```
<!-- Docusaurus will not render the {props.filename} inside of a ```codeblock``` -->
<ReplaceS3BucketPlaceholders filename="./ebs-storage-dynamic-pvc.yaml" />
```bash
sed -i.old s/\<S3_BUCKET\>/${S3_BUCKET}/g ./ebs-storage-dynamic-pvc.yaml
```

이제 버킷 이름이 있으므로 Spark 작업을 생성할 수 있습니다.

```bash
kubectl apply -f ebs-storage-dynamic-pvc.yaml
```

## shuffle 스토리지용 NVMe 기반 SSD 디스크가 있는 Apache YuniKorn Gang 스케줄링

Apache YuniKorn 및 Spark Operator를 사용한 Gang 스케줄링 Spark 작업

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator/examples/karpenter/
```
<!-- Docusaurus will not render the {props.filename} inside of a ```codeblock``` -->
<ReplaceS3BucketPlaceholders filename="./nvme-storage-yunikorn-gang-scheduling.yaml" />
```bash
sed -i.old s/\<S3_BUCKET\>/${S3_BUCKET}/g ./nvme-storage-yunikorn-gang-scheduling.yaml
```

이제 버킷 이름이 있으므로 Spark 작업을 생성할 수 있습니다.

```bash
kubectl apply -f nvme-storage-yunikorn-gang-scheduling.yaml
```

</CollapsibleContent>

<CollapsibleContent header={<h2><span>Graviton 및 Intel이 포함된 Karpenter NodePool 가중치</span></h2>}>

## AWS Graviton 및 Intel EC2 인스턴스 모두에서 Spark 작업을 실행하기 위한 Karpenter NodePool 가중치 사용

고객은 종종 비용 절감과 기존 Intel 인스턴스에 비해 성능 향상으로 인해 Spark 작업을 실행하기 위해 AWS Graviton 인스턴스를 활용하려고 합니다. 그러나 일반적인 과제는 특히 수요가 높은 시기에 특정 리전이나 가용 영역에서 Graviton 인스턴스의 가용성입니다. 이를 해결하기 위해 동등한 Intel 인스턴스로의 [폴백 전략](https://karpenter.sh/docs/concepts/scheduling/#weighted-nodepools)이 필요합니다.

#### 솔루션
**단계 1: 다중 아키텍처 Spark Docker 이미지 생성**
먼저 다중 아키텍처 Docker 이미지를 생성하여 Spark 작업이 AWS Graviton(ARM 아키텍처) 및 Intel(AMD 아키텍처) 인스턴스 모두에서 실행될 수 있도록 합니다. 샘플 [Dockerfile](../../../../analytics/terraform/spark-k8s-operator/examples/docker/Dockerfile) 및 [Amazon Elastic Container Registry(ECR)에 이 이미지를 빌드하고 푸시하는 지침을 예제 디렉토리에서](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/spark-k8s-operator/examples/docker) 찾을 수 있습니다.

**단계 2: 가중치가 있는 두 개의 Karpenter NodePool 배포**
Graviton 인스턴스용과 Intel 인스턴스용으로 구성된 두 개의 별도 Karpenter NodePool을 배포합니다.

Graviton NodePool(ARM): Graviton NodePool의 가중치를 `100`으로 설정합니다. 이렇게 하면 Spark 워크로드에 Graviton 인스턴스가 우선시됩니다.

Intel NodePool(AMD): Intel NodePool의 가중치를 `50`으로 설정합니다. 이렇게 하면 Graviton 인스턴스를 사용할 수 없거나 최대 CPU 용량에 도달할 때 Karpenter가 Intel NodePool로 폴백합니다.

메모리 최적화 Karpenter NodePool은 이러한 가중치로 구성됩니다.

<Tabs>
<TabItem value="spark-memory-optimized" label="spark-memory-optimized">

이 NodePool은 xlarge에서 8xlarge 크기까지의 r5d 인스턴스 유형을 사용하며, 더 많은 메모리가 필요한 Spark 작업에 적합합니다.

Karpenter 구성을 보려면 [여기에서 `addons.tf` 파일을 검토하세요](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/addons.tf#L177-L223)
</TabItem>

<TabItem value="spark-graviton-memory-optimized" label="spark-graviton-memory-optimized">

이 NodePool은 4xlarge에서 16xlarge 크기까지의 r6g, r6gd, r7g, r7gd 및 r8g 인스턴스 유형을 사용합니다

Karpenter 구성을 보려면 [여기에서 `addons.tf` 파일을 검토하세요](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/addons.tf#L117-L170)
</TabItem>
</Tabs>

**단계 3: 두 NodePool을 모두 타겟팅하는 레이블 선택기 사용**
두 NodePool 모두 `multiArch: Spark` 레이블이 있으므로 해당 레이블과 일치하는 NodeSelector로 Spark 작업을 구성할 수 있습니다. 이렇게 하면 Karpenter가 두 메모리 최적화 NodePool에서 노드를 프로비저닝할 수 있으며, 위에서 구성한 가중치로 인해 Graviton 인스턴스부터 시작합니다.

```yaml
    nodeSelector:
      multiArch: Spark
```

</CollapsibleContent>


<CollapsibleContent header={<h2><span>정리</span></h2>}>

:::caution
AWS 계정에 원치 않는 비용이 청구되지 않도록 이 배포 중에 생성된 모든 AWS 리소스를 삭제하세요.
:::

이 스크립트는 모든 리소스가 올바른 순서로 삭제되도록 `-target` 옵션을 사용하여 환경을 정리합니다.

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator && chmod +x cleanup.sh
./cleanup.sh
```

</CollapsibleContent>
