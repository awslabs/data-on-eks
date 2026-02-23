---
sidebar_label: Kafka 통합
sidebar_position: 1
---

## Kafka를 통한 실시간 데이터 수집

이 예제는 Apache Kafka에서 Pinot 테이블로 실시간 항공편 데이터를 수집하는 방법을 보여줍니다. JSON 및 Avro 형식의 두 테이블을 생성하고 샘플 데이터를 스트리밍하며 세그먼트가 S3 DeepStore에 백업되었는지 확인합니다.

**학습 내용:**
- Strimzi 연산자를 사용하여 Kafka 배포
- Pinot 수집용 Kafka 토픽 생성
- S3 DeepStore로 실시간 Pinot 테이블 구성
- 샘플 항공편 데이터 스트리밍 및 쿼리
- S3로 세그먼트 업로드 확인

**샘플 데이터:** 항공사, 출발지, 목적지, 지연 등의 세부 정보를 포함하는 ~19,000개의 항공편 레코드.

## Kafka 통합

### 스트리밍 데이터를 위한 Apache Kafka 배포

Apache Pinot은 스트리밍 데이터 소스(실시간)뿐만 아니라 배치 데이터 소스(오프라인)에서도 데이터를 수집할 수 있습니다. 이 예제에서는 [Apache Kafka](https://kafka.apache.org/)를 활용하여 토픽에 실시간 데이터를 푸시합니다.

EKS 클러스터에서 이미 Apache Kafka가 실행 중이거나 Amazon Managed Streaming for Apache Kafka (MSK)를 사용 중인 경우 이 단계를 건너뛸 수 있습니다. 그렇지 않은 경우 아래 단계를 따라 Strimzi Kafka 연산자를 사용하여 EKS 클러스터에 Kafka를 설치합니다.

:::note
다음 배포는 간소화된 배포를 위해 PLAINTEXT 리스너로 Kafka 브로커를 구성합니다. 프로덕션 배포 시 적절한 보안 설정으로 구성을 수정하세요.
:::

### Kafka 클러스터 배포

Strimzi Kafka 연산자를 사용하여 Kafka 클러스터 생성:

```bash
kubectl apply -f ../../kafka-on-eks/kafka-cluster/kafka-cluster.yaml
```

클러스터가 준비될 때까지 대기:

```bash
kubectl get kafka -n kafka
```

예상 출력:
```
NAME          READY   METADATA STATE   WARNINGS
data-on-eks   True    KRaft            True
```

### Kafka 토픽 생성

Pinot이 연결하여 데이터를 읽을 두 개의 Kafka 토픽 생성:

```bash
kubectl apply -f examples/quickstart-topics.yaml -n kafka
```

토픽이 생성되었는지 확인:

```bash
kubectl get kafkatopic -n kafka
```

예상 출력:
```
NAME                    CLUSTER       PARTITIONS   REPLICATION FACTOR   READY
flights-realtime        data-on-eks   1            1                    True
flights-realtime-avro   data-on-eks   1            1                    True
```

### 샘플 데이터 수집

quickstart 작업은 다음을 수행합니다:
1. **Pinot에 두 개의 실시간 테이블 생성**:
   - `airlineStats` - JSON 형식의 항공편 데이터 수집
   - `airlineStatsAvro` - Avro 형식의 항공편 데이터 수집
2. **S3 DeepStore 구성** - 완료 후 세그먼트가 자동으로 S3에 업로드
3. **샘플 데이터 스트리밍** - 두 Kafka 토픽에 ~19,000개의 항공편 레코드 게시
4. **수집 시작** - Pinot이 데이터를 실시간으로 소비하고 인덱싱 시작

quickstart 매니페스트 적용:

```bash
kubectl apply -f examples/pinot-realtime-quickstart.yml -n pinot
```

작업은 다음 컨테이너를 포함하는 두 개의 파드를 생성합니다:
- `pinot-add-example-realtime-table-json` - JSON 테이블 생성
- `pinot-add-example-realtime-table-avro` - Avro 테이블 생성
- `loading-json-data-to-kafka` - Kafka로 JSON 데이터 스트리밍
- `loading-avro-data-to-kafka` - Kafka로 Avro 데이터 스트리밍

### 데이터 수집 확인

Pinot Query Console로 돌아가서 테이블이 생성되고 데이터를 수신하고 있는지 확인:

```bash
kubectl port-forward service/pinot-controller 9000:9000 -n pinot
```

브라우저에서 [http://localhost:9000](http://localhost:9000) 을 엽니다. 새로 생성된 테이블과 실시간으로 수집되는 데이터를 볼 수 있습니다.

![Pinot Example](./img/pinot-example.png)

### S3 DeepStore 업로드 확인

세그먼트는 다음 조건에 따라 완료되면 S3에 업로드됩니다:
- **시간 임계값**: 300000ms (5분) - 5분 후 세그먼트 플러시
- **크기 임계값**: 50000행 - 50k 행에 도달하면 세그먼트 플러시

S3에 세그먼트가 있는지 확인:

```bash
# 버킷 이름 가져오기
BUCKET_NAME=$(terraform -chdir=../../infra/terraform/_local output -raw data_bucket_id)

# S3의 세그먼트 나열
aws s3 ls s3://$BUCKET_NAME/pinot/segments/ --recursive
```

다음과 같은 세그먼트 파일이 표시되어야 합니다:
```
pinot/segments/airlineStats/airlineStats__0__0__20260123T0054Z.tmp.030c94c8-19d7-4cc0-89bd-86c41c7e9b7c
pinot/segments/airlineStats/airlineStats__0__0__20260123T0054Z.tmp.04a4b92b-1293-4462-8e22-08207dc621e4
```

테스트를 위해 세그먼트 완료 강제 실행(선택 사항):

```bash
# 현재 소비 중인 세그먼트를 봉인하기 위해 강제 커밋
curl -X POST http://localhost:9000/tables/airlineStats_REALTIME/forceCommit
curl -X POST http://localhost:9000/tables/airlineStatsAvro_REALTIME/forceCommit
```

서버 로그에서 업로드 활동 확인:

```bash
kubectl logs -n pinot pinot-server-0 | grep -i "upload\|deepstore\|s3"
```
