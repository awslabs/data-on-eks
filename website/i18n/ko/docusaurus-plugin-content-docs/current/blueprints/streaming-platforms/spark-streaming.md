---
title: EKS에서 Kafka 기반 Spark Streaming
sidebar_position: 6
---

:::danger
**지원 중단 공지**

이 블루프린트는 **2024년 10월 27일**에 이 GitHub 저장소에서 지원 중단되고 최종적으로 제거될 예정입니다. 버그 수정 및 새로운 기능 추가가 이루어지지 않습니다. 이 블루프린트에 대한 수요와 관심 부족, 그리고 사용자나 고객이 적극적으로 사용하지 않는 블루프린트를 유지 관리하기 위한 리소스 할당의 어려움으로 인해 지원 중단이 결정되었습니다.

프로덕션에서 이 블루프린트를 사용하고 있다면 [adopters.md](https://github.com/awslabs/data-on-eks/blob/main/ADOPTERS.md) 페이지에 자신을 추가하고 저장소에 이슈를 제기해 주세요. 이를 통해 블루프린트를 재고하고 유지 관리를 계속할 수 있습니다. 그렇지 않으면 로컬 복사본을 만들거나 기존 태그를 사용하여 액세스할 수 있습니다.
:::


이 예제는 Spark Operator를 사용하여 Kafka(Amazon MSK)를 사용하는 프로듀서 및 컨슈머 스택을 만드는 방법을 보여줍니다. 주요 아이디어는 Apache Iceberg를 사용하여 Parquet 형식으로 데이터를 저장하면서 Kafka와 함께 작동하는 Spark Streaming을 보여주는 것입니다.

## 이 예제를 테스트하는 데 필요한 모든 애드온 및 인프라와 함께 EKS 클러스터 배포

### 저장소 복제

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

### Terraform 초기화

예제 디렉토리로 이동하고 초기화 스크립트 `install.sh`를 실행합니다.

```bash
cd data-on-eks/streaming/spark-streaming/terraform/
./install.sh
```

### Terraform 출력 내보내기

Terraform 스크립트가 완료되면 `sed` 명령에서 사용할 필요한 변수를 내보냅니다.

```bash
export CLUSTER_NAME=$(terraform output -raw cluster_name)
export PRODUCER_ROLE_ARN=$(terraform output -raw producer_iam_role_arn)
export CONSUMER_ROLE_ARN=$(terraform output -raw consumer_iam_role_arn)
export MSK_BROKERS=$(terraform output -raw bootstrap_brokers)
export REGION=$(terraform output -raw s3_bucket_region_spark_history_server)
export ICEBERG_BUCKET=$(terraform output -raw s3_bucket_id_iceberg_bucket)
```

### kubeconfig 업데이트

배포를 확인하기 위해 kubeconfig를 업데이트합니다.

```bash
aws eks --region $REGION update-kubeconfig --name $CLUSTER_NAME
kubectl get nodes
```

### 프로듀서 구성

프로듀서를 배포하려면 Terraform에서 내보낸 변수로 `examples/producer/00_deployment.yaml` 매니페스트를 업데이트합니다.

```bash
# producer 매니페스트에서 플레이스홀더를 대체하기 위해 `sed` 명령 적용
sed -i.bak -e "s|__MY_PRODUCER_ROLE_ARN__|$PRODUCER_ROLE_ARN|g" \
           -e "s|__MY_AWS_REGION__|$REGION|g" \
           -e "s|__MY_KAFKA_BROKERS__|$MSK_BROKERS|g" \
           ../examples/producer/00_deployment.yaml

# kafka 토픽을 삭제하고 스택을 다시 시작하는 데 사용할 수 있는 delete topic 매니페스트에 sed 적용
sed -i.bak -e "s|__MY_KAFKA_BROKERS__|$MSK_BROKERS|g" \
           ../examples/producer/01_delete_topic.yaml
```

### 컨슈머 구성

Spark 컨슈머를 배포하려면 Terraform에서 내보낸 변수로 `examples/consumer/manifests/01_spark_application.yaml` 매니페스트를 업데이트합니다.

```bash
# consumer Spark application 매니페스트에서 플레이스홀더를 대체하기 위해 `sed` 명령 적용
sed -i.bak -e "s|__MY_BUCKET_NAME__|$ICEBERG_BUCKET|g" \
           -e "s|__MY_KAFKA_BROKERS_ADRESS__|$MSK_BROKERS|g" \
           ../examples/consumer/manifests/01_spark_application.yaml
```

### 프로듀서 및 컨슈머 배포

프로듀서 및 컨슈머 매니페스트를 구성한 후 kubectl을 사용하여 배포합니다.

```bash
# Producer 배포
kubectl apply -f ../examples/producer/00_deployment.yaml

# Consumer 배포
kubectl apply -f ../examples/consumer/manifests/
```

#### 프로듀서에서 MSK로 확인

먼저 프로듀서 로그를 확인하여 데이터가 생성되고 MSK로 흐르는지 확인합니다:

```bash
kubectl logs $(kubectl get pods -l app=producer -oname) -f
```

#### Spark Operator로 Spark Streaming 애플리케이션 확인

컨슈머의 경우 먼저 YAML 구성을 기반으로 드라이버와 익스큐터 파드를 생성하기 위해 Spark Operator에 `spark-submit` 명령을 생성하는 `SparkApplication`을 가져와야 합니다:

```bash
kubectl get SparkApplication -n spark-operator
```

`STATUS`가 `RUNNING`인지 확인한 후 드라이버 및 익스큐터 파드를 확인합니다:

```bash
kubectl get pods -n spark-operator
```

아래와 같은 출력이 표시됩니다:

```bash
NAME                                     READY   STATUS      RESTARTS   AGE
kafkatoiceberg-1e9a438f4eeedfbb-exec-1   1/1     Running     0          7m15s
kafkatoiceberg-1e9a438f4eeedfbb-exec-2   1/1     Running     0          7m14s
kafkatoiceberg-1e9a438f4eeedfbb-exec-3   1/1     Running     0          7m14s
spark-consumer-driver                    1/1     Running     0          9m
spark-operator-9448b5c6d-d2ksp           1/1     Running     0          117m
spark-operator-webhook-init-psm4x        0/1     Completed   0          117m
```

`1개의 드라이버`와 `3개의 익스큐터` 파드가 있습니다. 이제 드라이버 로그를 확인합니다:

```bash
kubectl logs pod/spark-consumer-driver -n spark-operator
```

작업이 실행 중임을 나타내는 `INFO` 로그만 표시되어야 합니다.

### 데이터 흐름 확인

프로듀서와 컨슈머를 모두 배포한 후 S3 버킷에서 컨슈머 애플리케이션의 출력을 확인하여 데이터 흐름을 확인합니다. `s3_automation` 스크립트를 실행하여 S3 버킷의 데이터 크기에 대한 실시간 보기를 얻을 수 있습니다.

다음 단계를 따르세요:

1. **`s3_automation` 디렉토리로 이동**:

    ```bash
    cd ../examples/s3_automation/
    ```

2. **`s3_automation` 스크립트 실행**:

    ```bash
    python app.py
    ```

    이 스크립트는 S3 버킷의 총 크기를 지속적으로 모니터링하고 표시하여 수집되는 데이터의 실시간 보기를 제공합니다. 버킷 크기를 보거나 필요에 따라 특정 디렉토리를 삭제하도록 선택할 수 있습니다.


#### `s3_automation` 스크립트 사용

`s3_automation` 스크립트는 두 가지 주요 기능을 제공합니다:

- **버킷 크기 확인**: S3 버킷의 총 크기를 지속적으로 모니터링하고 표시합니다.
- **디렉토리 삭제**: S3 버킷 내의 특정 디렉토리를 삭제합니다.

이러한 기능을 사용하는 방법은 다음과 같습니다:

1. **버킷 크기 확인**:
    - 프롬프트가 표시되면 `size`를 입력하여 버킷의 현재 크기(메가바이트(MB))를 가져옵니다.

2. **디렉토리 삭제**:
    - 프롬프트가 표시되면 `delete`를 입력한 다음 삭제할 디렉토리 접두사(예: `myfolder/`)를 제공합니다.

## 더 나은 성능을 위한 프로듀서 및 컨슈머 튜닝

프로듀서와 컨슈머를 배포한 후 프로듀서의 레플리카 수와 Spark 애플리케이션의 익스큐터 구성을 조정하여 데이터 수집 및 처리를 더욱 최적화할 수 있습니다. 시작하기 위한 몇 가지 제안은 다음과 같습니다:

### 프로듀서 레플리카 수 조정

프로듀서 배포의 레플리카 수를 늘려 더 높은 메시지 생성 속도를 처리할 수 있습니다. 기본적으로 프로듀서 배포는 단일 레플리카로 구성됩니다. 이 수를 늘리면 더 많은 프로듀서 인스턴스가 동시에 실행되어 전체 처리량이 증가합니다.

레플리카 수를 변경하려면 `examples/producer/00_deployment.yaml`에서 `replicas` 필드를 업데이트합니다:

```yaml
spec:
  replicas: 200  # 프로듀서를 확장하려면 이 수를 늘립니다
```

환경 변수를 조정하여 생성되는 메시지의 속도와 양을 제어할 수도 있습니다:

```yaml
env:
  - name: RATE_PER_SECOND
    value: "200000"  # 초당 더 많은 메시지를 생성하려면 이 값을 늘립니다
  - name: NUM_OF_MESSAGES
    value: "20000000"  # 총 더 많은 메시지를 생성하려면 이 값을 늘립니다
```

업데이트된 배포 적용:

```bash
kubectl apply -f ../examples/producer/00_deployment.yaml
```

### 더 나은 수집 성능을 위한 Spark 익스큐터 튜닝

증가된 데이터 양을 효율적으로 처리하려면 Spark 애플리케이션에 더 많은 익스큐터를 추가하거나 각 익스큐터에 할당된 리소스를 늘릴 수 있습니다. 이렇게 하면 컨슈머가 데이터를 더 빠르게 처리하고 수집 시간을 줄일 수 있습니다.

Spark 익스큐터 구성을 조정하려면 `examples/consumer/manifests/01_spark_application.yaml`을 업데이트합니다:

```yaml
spec:
  dynamicAllocation:
    enabled: true
    initialExecutors: 5
    minExecutors: 5
    maxExecutors: 50  # 더 많은 익스큐터를 허용하려면 이 수를 늘립니다
  executor:
    cores: 4  # CPU 할당 증가
    memory: "8g"  # 메모리 할당 증가
```

업데이트된 Spark 애플리케이션 적용:

```bash
kubectl apply -f ../examples/consumer/manifests/01_spark_application.yaml
```

### 확인 및 모니터링

이러한 변경을 수행한 후 로그와 메트릭을 모니터링하여 시스템이 예상대로 작동하는지 확인합니다. 프로듀서 로그를 확인하여 데이터 생성을 확인하고 컨슈머 로그를 확인하여 데이터 수집 및 처리를 확인할 수 있습니다.

프로듀서 로그 확인:

```bash
kubectl logs $(kubectl get pods -l app=producer -oname) -f
```

컨슈머 로그 확인:

```bash
kubectl logs pod/spark-consumer-driver -n spark-operator
```

> 데이터 흐름 스크립트 확인을 다시 사용할 수 있습니다

### 요약

프로듀서 레플리카 수를 조정하고 Spark 익스큐터 설정을 튜닝하면 데이터 파이프라인의 성능을 최적화할 수 있습니다. 이를 통해 더 높은 수집 속도를 처리하고 데이터를 더 효율적으로 처리할 수 있어 Spark Streaming 애플리케이션이 Kafka에서 증가된 데이터 양을 따라잡을 수 있습니다.

워크로드에 최적의 구성을 찾기 위해 이러한 설정을 자유롭게 실험해 보세요. 즐거운 스트리밍 되세요!


### 프로듀서 및 컨슈머 리소스 정리

프로듀서 및 컨슈머 리소스만 정리하려면 다음 명령을 사용합니다:

```bash
# Producer 리소스 정리
kubectl delete -f ../examples/producer/00_deployment.yaml

# Consumer 리소스 정리
kubectl delete -f ../examples/consumer/manifests/
```

### `.bak`에서 `.yaml` 파일 복원

플레이스홀더가 있는 원래 상태로 `.yaml` 파일을 재설정해야 하는 경우 `.bak` 파일을 `.yaml`로 다시 이동합니다.

```bash
# Producer 매니페스트 복원
mv ../examples/producer/00_deployment.yaml.bak ../examples/producer/00_deployment.yaml


# Consumer Spark application 매니페스트 복원
mv ../examples/consumer/manifests/01_spark_application.yaml.bak ../examples/consumer/manifests/01_spark_application.yaml
```

### EKS 클러스터 및 리소스 삭제

전체 EKS 클러스터 및 관련 리소스를 정리하려면:

```bash
cd data-on-eks/streaming/spark-streaming/terraform/
terraform destroy
```
