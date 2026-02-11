---
title: Apache Flink
sidebar_label: Apache Flink
sidebar_position: 2
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';


## 개요

이 문서는 Apache Flink와 Flink Kubernetes Operator에 대한 개요를 제공합니다. 아키텍처, 모범 사례를 다루며, EKS의 Flink 클러스터에 스트리밍 작업을 제출하는 방법을 보여주는 간단한 예제를 포함합니다.

## 사전 요구 사항

- Flink on EKS 인프라 배포: [인프라 설정](./infra.md)



## Apache Flink 소개

[Apache Flink](https://flink.apache.org/)는 대량의 데이터를 처리하도록 설계된 오픈 소스 통합 스트림 처리 및 배치 처리 프레임워크입니다. 내결함성과 정확히 한 번(exactly-once) 시맨틱으로 빠르고 안정적이며 확장 가능한 데이터 처리를 제공합니다.
Flink의 주요 기능은 다음과 같습니다:
- **분산 처리**: Flink는 분산 방식으로 대량의 데이터를 처리하도록 설계되어 수평적 확장이 가능하고 내결함성을 제공합니다.
- **스트림 처리 및 배치 처리**: Flink는 스트림 처리와 배치 처리 모두를 위한 API를 제공합니다. 이는 데이터가 생성되는 실시간으로 처리하거나 배치로 처리할 수 있음을 의미합니다.
- **내결함성(Fault Tolerance)**: Flink에는 노드 장애, 네트워크 파티션 및 기타 유형의 장애를 처리하기 위한 내장 메커니즘이 있습니다.
- **정확히 한 번 시맨틱(Exactly-once Semantics)**: Flink는 장애가 발생하더라도 각 레코드가 정확히 한 번만 처리되도록 보장하는 exactly-once 처리를 지원합니다.
- **낮은 지연 시간**: Flink의 스트리밍 엔진은 낮은 지연 시간 처리에 최적화되어 있어 실시간 데이터 처리가 필요한 사용 사례에 적합합니다.
- **확장성**: Flink는 풍부한 API와 라이브러리 세트를 제공하여 특정 사용 사례에 맞게 쉽게 확장하고 커스터마이징할 수 있습니다.

## 아키텍처

EKS를 활용한 Flink 아키텍처 하이레벨 설계.

![Flink Design UI](img/flink-design.png)

## Flink Kubernetes Operator
[Flink Kubernetes Operator](https://nightlies.apache.org/flink/flink-kubernetes-operator-docs-main/)는 Kubernetes에서 Flink 클러스터를 관리하기 위한 강력한 도구입니다. Flink Kubernetes Operator(Operator)는 Apache Flink 애플리케이션의 전체 배포 수명 주기를 관리하는 컨트롤 플레인 역할을 합니다. Operator는 Helm을 사용하여 Kubernetes 클러스터에 설치할 수 있습니다. Flink Operator의 핵심 역할은 Flink 애플리케이션의 전체 프로덕션 수명 주기를 관리하는 것입니다.
1. 애플리케이션 실행, 일시 중지 및 삭제
2. 상태 저장 및 비상태 애플리케이션 업그레이드
3. 세이브포인트(Savepoint) 트리거 및 관리
4. 오류 처리, 잘못된 업그레이드 롤백

Flink Operator는 Kubernetes API의 확장인 두 가지 유형의 커스텀 리소스(CR)를 정의합니다.

<Tabs>
<TabItem value="FlinkDeployment" label="FlinkDeployment">


**FlinkDeployment**
- FlinkDeployment CR은 **Flink Application** 및 **Session Cluster** 배포를 정의합니다.
- Application 배포는 Application 모드에서 전용 Flink 클러스터에 단일 작업 배포를 관리합니다.
- Session 클러스터를 사용하면 기존 Session 클러스터에서 여러 Flink 작업을 실행할 수 있습니다.

    <details>
    <summary>Session Cluster용 FlinkDeployment</summary>

    ```yaml
    apiVersion: flink.apache.org/v1beta1
    kind: FlinkDeployment
    metadata:
      namespace: default
      name: basic-session-cluster
    spec:
      image: docker.io/library/flink:2.0.0-java17
      flinkVersion: v2_0
      flinkConfiguration:
        taskmanager.numberOfTaskSlots: "2"
      serviceAccount: flink
      jobManager:
        resource:
          memory: "2048m"
          cpu: 1
      taskManager:
        resource:
          memory: "2048m"
          cpu: 1
    ```
    </details>

</TabItem>

<TabItem value="FlinkSessionJob" label="FlinkSessionJob">

**FlinkSessionJob**
- `FlinkSessionJob` CR은 **Session 클러스터**에서 세션 작업을 정의하며 각 Session 클러스터는 여러 `FlinkSessionJob`을 실행할 수 있습니다.
- Session 배포는 작업 관리를 제공하지 않고 Flink Session 클러스터를 관리합니다

    <details>
    <summary>기존 "basic-session-cluster" 세션 클러스터 배포를 사용하는 FlinkSessionJob</summary>

    ```yaml
    apiVersion: flink.apache.org/v1beta1
    kind: FlinkSessionJob
    metadata:
      name: basic-session-job-example
    spec:
      deploymentName: basic-session-cluster
    ```

    </details>

</TabItem>
</Tabs>

:::info
Session 클러스터는 yaml 스펙에서 `job`이 정의되지 않는다는 점만 다를 뿐 Application 클러스터와 유사한 스펙을 사용합니다.
:::

:::info
Flink 문서에 따르면 프로덕션 환경에서는 Application 모드의 FlinkDeployment를 사용하는 것이 권장됩니다.
:::

배포 유형 외에도 Flink Kubernetes Operator는 두 가지 배포 모드를 지원합니다: `Native` 및 `Standalone`.

<Tabs>
<TabItem value="Native" label="Native">

**Native**

- Native 클러스터 배포는 기본 배포 모드이며 클러스터를 배포할 때 Flink의 내장 Kubernetes 통합을 사용합니다.
- Flink 클러스터는 Kubernetes와 직접 통신하여 Kubernetes 리소스를 관리할 수 있습니다. 예를 들어 TaskManager 파드를 동적으로 할당하고 해제합니다.
- Flink Native는 자체 클러스터 관리 시스템을 구축하거나 기존 관리 시스템과 통합하려는 고급 사용자에게 유용할 수 있습니다.
- Flink Native는 작업 스케줄링 및 실행 측면에서 더 많은 유연성을 제공합니다.
- 표준 Operator 사용의 경우 Native 모드에서 자체 Flink 작업을 실행하는 것이 권장됩니다.

```yaml
apiVersion: flink.apache.org/v1beta1
kind: FlinkDeployment
...
spec:
...
mode: native
```
</TabItem>

<TabItem value="Standalone" label="Standalone">

**Standalone**

- Standalone 클러스터 배포는 단순히 Kubernetes를 Flink 클러스터가 실행되는 오케스트레이션 플랫폼으로 사용합니다.
- Flink는 Kubernetes에서 실행되고 있다는 것을 인식하지 못하므로 모든 Kubernetes 리소스는 Kubernetes Operator에 의해 외부에서 관리되어야 합니다.

    ```yaml
    apiVersion: flink.apache.org/v1beta1
    kind: FlinkDeployment
    ...
    spec:
    ...
    mode: standalone
    ```

</TabItem>
</Tabs>

## Kubernetes에서 Flink 작업 실행을 위한 모범 사례
Kubernetes에서 Flink를 최대한 활용하기 위한 몇 가지 모범 사례는 다음과 같습니다:

- **Kubernetes Operator 사용**: Flink Kubernetes Operator를 설치하고 사용하여 Kubernetes에서 Flink 클러스터의 배포 및 관리를 자동화합니다.
- **전용 네임스페이스에 배포**: Flink Kubernetes Operator를 위한 별도의 네임스페이스와 Flink 작업/워크로드를 위한 다른 네임스페이스를 생성합니다. 이렇게 하면 Flink 작업이 격리되고 자체 리소스를 가질 수 있습니다.
- **고품질 스토리지 사용**: Flink 체크포인트와 세이브포인트를 Amazon S3 또는 다른 내구성 있는 외부 스토리지와 같은 고품질 스토리지에 저장합니다. 이러한 스토리지 옵션은 안정적이고 확장 가능하며 대용량 데이터에 대한 내구성을 제공합니다.
- **리소스 할당 최적화**: 최적의 성능을 보장하기 위해 Flink 작업에 충분한 리소스를 할당합니다. Flink 컨테이너에 대한 리소스 요청과 제한을 설정하여 이를 수행할 수 있습니다.
- **적절한 네트워크 격리**: Kubernetes Network Policies를 사용하여 동일한 Kubernetes 클러스터에서 실행되는 다른 워크로드로부터 Flink 작업을 격리합니다. 이렇게 하면 Flink 작업이 다른 워크로드의 영향을 받지 않고 필요한 네트워크 액세스를 가질 수 있습니다.
- **Flink 최적 구성**: 사용 사례에 맞게 Flink 설정을 조정합니다. 예를 들어 입력 데이터의 크기에 따라 Flink 작업이 적절하게 확장되도록 Flink의 병렬성 설정을 조정합니다.
- **체크포인트 및 세이브포인트 사용**: Flink 애플리케이션 상태의 주기적 스냅샷에는 체크포인트를 사용하고, 애플리케이션 업그레이드 또는 다운그레이드와 같은 고급 사용 사례에는 세이브포인트를 사용합니다.
- **체크포인트와 세이브포인트를 적절한 위치에 저장**: 체크포인트는 Amazon S3 또는 다른 내구성 있는 외부 스토리지와 같은 분산 파일 시스템이나 키-값 저장소에 저장합니다. 세이브포인트는 Amazon S3와 같은 내구성 있는 외부 스토리지에 저장합니다.

## Flink 업그레이드
Flink Operator는 Flink 작업에 대한 세 가지 업그레이드 모드를 제공합니다. 최신 정보는 [Flink 업그레이드 문서](https://nightlies.apache.org/flink/flink-kubernetes-operator-docs-main/docs/custom-resource/job-management/#stateful-and-stateless-application-upgrades)를 확인하세요.

1. **stateless**: 빈 상태에서 비상태 애플리케이션 업그레이드
2. **last-state**: 모든 애플리케이션 상태에서 빠른 업그레이드(실패한 작업도 포함), 항상 최신 체크포인트 정보를 사용하므로 정상적인 작업이 필요하지 않습니다. HA 메타데이터가 손실되면 수동 복구가 필요할 수 있습니다.
3. **savepoint**: 업그레이드에 세이브포인트 사용, 최대 안전성을 제공하고 백업/포크 지점으로 사용 가능. 세이브포인트는 업그레이드 프로세스 중에 생성됩니다. 세이브포인트 생성을 위해서는 Flink 작업이 실행 중이어야 합니다. 작업이 비정상 상태인 경우 마지막 체크포인트가 사용됩니다(kubernetes.operator.job.upgrade.last-state-fallback.enabled가 false로 설정되지 않은 경우). 마지막 체크포인트를 사용할 수 없는 경우 작업 업그레이드가 실패합니다.

:::info
프로덕션에서는 `last-state` 또는 `savepoint` 모드가 권장됩니다
:::


### 예제: 스트리밍 작업 제출

이 예제는 EKS 클러스터에 샘플 Flink 스트리밍 작업을 제출하는 과정을 안내합니다. 작업은 체크포인트와 세이브포인트에 S3를 사용하는 `flink-sample-job.yaml` 파일에 정의되어 있습니다.

먼저 환경을 구성하고 Terraform에서 생성한 S3 버킷을 식별하기 위해 다음 환경 변수를 설정합니다.

```bash
# 생성된 클러스터를 사용하도록 kubeconfig 업데이트
aws eks update-kubeconfig --name  data-on-eks --alias data-on-eks

export FLINK_DIR=$(git rev-parse --show-toplevel)/data-stacks/flink-on-eks
export S3_BUCKET=$(terraform -chdir=$FLINK_DIR/terraform/_local output -raw s3_bucket_id_spark_history_server)
```

다음으로 `flink-sample-job.yaml` 매니페스트를 검토합니다. 샘플 스트리밍 작업을 실행하는 `FlinkDeployment`를 정의합니다. 체크포인트, 세이브포인트 및 고가용성에 대한 구성이 모두 S3 버킷을 가리키는 것을 확인하세요.

이제 매니페스트를 적용하여 Flink 작업을 배포합니다. `envsubst` 명령은 YAML 파일의 `$S3_BUCKET` 변수를 대체합니다.

```bash
cat $FLINK_DIR/examples/flink-sample-job.yaml | envsubst | kubectl apply -f -
```

방금 배포한 `flink-sample-job.yaml`의 주요 구성을 이해해 보겠습니다.

<details>
<summary>FlinkDeployment 매니페스트 분석</summary>

`FlinkDeployment` 매니페스트에는 Kubernetes에서 Flink 애플리케이션이 어떻게 실행되는지 정의하는 구성이 있습니다. 이 예제에서 보여주는 주요 기능은 다음과 같습니다:

- **S3에 중앙 집중식 상태 관리**: 모든 상태 관련 정보는 공유 S3 버킷에 저장되도록 구성됩니다. 여기에는 다음이 포함됩니다:
  - `state.checkpoints.dir`: 내구성 있는 체크포인트 저장용.
  - `high-availability.storageDir`: JobManager 페일오버에 필요한 메타데이터용.
  - `execution.checkpointing.savepoint-dir`: 수동 또는 주기적으로 트리거되는 세이브포인트용.

- **Kubernetes 네이티브 고가용성**: 작업은 `high-availability.type: kubernetes`로 구성됩니다. 이는 Zookeeper와 같은 외부 시스템에 의존하는 대신 리더 선출에 Kubernetes를 사용하므로 고가용성을 활성화하는 현대적이고 권장되는 접근 방식입니다.

- **자동화된 Operator 기능**: 매니페스트는 강력한 자동화를 위해 Flink Operator를 활용합니다:
  - `kubernetes.operator.periodic.savepoint.interval: 1h`: 매시간 자동으로 세이브포인트를 생성하여 작업 상태의 일관된 백업을 제공합니다.
  - `kubernetes.operator.deployment.rollback.enabled: "true"`: 업그레이드가 실패하면 마지막으로 알려진 안정적인 상태로 자동 롤백을 활성화합니다.

- **`podTemplate`을 사용한 파드 커스터마이징**: `podTemplate`은 Flink 파드에 대한 세밀한 제어를 허용합니다:
  - `nodeSelector`: Flink 파드가 스트리밍 워크로드에 최적화된 노드에 스케줄링되도록 합니다(`NodeGroupType: "StreamingOptimized"`).
  - `ENABLE_BUILT_IN_PLUGINS`: 이 환경 변수는 Flink가 S3와 통신할 수 있도록 하는 데 필수적인 `flink-s3-fs-presto` 플러그인을 로드하는 데 사용됩니다.

</details>

Flink 배포 상태를 모니터링할 수 있습니다. `JobManager` 배포와 `TaskManager` 파드가 생성됩니다.

```bash
kubectl get deployments -n flink-team-a
NAME            READY   UP-TO-DATE   AVAILABLE   AGE
basic-example   1/1     1            1           5m9s

kubectl get pods -n flink-team-a
NAME                            READY   STATUS    RESTARTS   AGE
basic-example-bf467dff7-zwhgc   1/1     Running   0          102s
basic-example-taskmanager-1-1   1/1     Running   0          87s
basic-example-taskmanager-1-2   1/1     Running   0          87s

kubectl get services -n flink-team-a
NAME                 TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)    AGE
basic-example-rest   ClusterIP   172.20.74.9   <none>        8081/TCP   3m43s
```

작업의 Flink Web UI에 액세스하려면 `kubectl port-forward`를 사용하여 UI 포트를 로컬 머신으로 포워딩합니다.

```bash
kubectl port-forward svc/basic-example-rest 8081 -n flink-team-a
```

![Flink Job UI](img/flink1.png)
![Flink Job UI](img/flink2.png)
![Flink Job UI](img/flink3.png)
![Flink Job UI](img/flink4.png)
![Flink Job UI](img/flink5.png)




### 정리

:::caution
AWS 계정에 원치 않는 요금이 부과되지 않도록 이 배포 중에 생성된 모든 AWS 리소스를 삭제하세요
:::


```bash
cd $FLINK_DIR
./cleanup.sh
```
