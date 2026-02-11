---
title: Argo Workflows
sidebar_position: 12
---

## Argo Workflows 및 Events를 사용한 Spark 작업 실행

Argo Workflows는 Kubernetes에서 병렬 작업을 오케스트레이션하기 위한 오픈 소스 컨테이너 네이티브 워크플로 엔진입니다. Kubernetes CRD(Custom Resource Definition)로 구현되어 `kubectl`을 사용하여 워크플로를 관리하고 볼륨, 시크릿, RBAC와 같은 다른 Kubernetes 서비스와 네이티브하게 통합할 수 있습니다.

이 가이드는 Argo를 사용하여 Amazon EKS에서 Spark 작업을 실행하는 세 가지 실용적인 예제를 제공합니다:

1. **예제 1: 워크플로에서 `spark-submit`**: Argo Workflow 내에서 직접 `spark-submit`을 사용하여 기본 Spark Pi 작업을 실행합니다. 이 방법은 Spark Operator를 사용하지 않습니다.
2. **예제 2: Spark Operator 사용**: Argo Workflows가 `SparkApplication` 커스텀 리소스를 생성하고 Spark Operator가 관리하도록 하여 Spark 작업을 오케스트레이션합니다.
3. **예제 3: Argo Events를 사용한 이벤트 기반 워크플로**: Amazon SQS 큐에 메시지가 전송되면 자동으로 Spark 작업을 트리거합니다.

Argo Workflows를 프로비저닝하는 Terraform 코드는 [schedulers/terraform/argo-workflow](https://github.com/awslabs/data-on-eks/tree/main/schedulers/terraform/argo-workflow) 디렉토리에서 찾을 수 있습니다. 이 가이드의 예제에 대한 Kubernetes 매니페스트는 `data-stacks/spark-on-eks/examples/argo-workflows/manifests/` 디렉토리에 있습니다.

## 전제 조건

시작하기 전에 Spark on EKS 기본 인프라를 배포해야 합니다.

- **Spark on EKS 인프라 배포:** [인프라 설정 가이드](./infra.md)를 따라 필요한 리소스를 프로비저닝합니다.

## Argo Workflows UI 접근

Argo Workflows는 워크플로를 시각화하고 관리할 수 있는 웹 기반 UI와 함께 제공됩니다.

### 1. UI 서비스로 포트 포워드

로컬 머신에서 UI에 접근하려면 새 터미널을 열고 다음 명령을 실행합니다. 이렇게 하면 로컬 포트가 클러스터에서 실행 중인 Argo Workflows 서버로 포워딩됩니다.

```bash
kubectl port-forward service/argo-workflows-server -n argo-workflows 2746:2746
```

이제 브라우저에서 [http://localhost:2746](http://localhost:2746)으로 UI에 접근할 수 있습니다.

### 2. UI 로그인

기본 사용자 이름은 `admin`입니다. 자동 생성된 비밀번호(인증 토큰)를 얻으려면 다음 명령을 실행합니다:

```bash
ARGO_TOKEN="Bearer $(kubectl -n argo-workflows create token argo-workflows-server)"
echo $ARGO_TOKEN
```

`Bearer` 접두사를 포함한 전체 출력을 복사하여 UI의 토큰 필드에 붙여넣어 로그인합니다.

![argo-workflow-login](img/argo-workflow-login.png)

### 3. 환경 변수 설정

이 환경 변수들은 다음 예제의 명령어에서 리소스를 찾고 매니페스트를 구성하는 데 사용됩니다.

```bash
export SPARK_DIR=$(git rev-parse --show-toplevel)/data-stacks/spark-on-eks
export S3_BUCKET=$(terraform -chdir=$SPARK_DIR/terraform/_local output -raw s3_bucket_id_spark_history_server)
export REGION=$(terraform -chdir=$SPARK_DIR/terraform/_local output --raw region)
```

## 예제 1: `spark-submit`으로 Spark 작업 제출

이 예제는 컨테이너 내부에서 직접 `spark-submit`을 사용하여 기본 Spark Pi 작업을 실행하는 방법을 보여줍니다. 이 워크플로는 Argo Workflows에서 관리되지만 Spark Operator를 사용하지 **않습니다**.

### 1. 매니페스트 적용

먼저 `spark-workflow-templates.yaml` 파일을 적용합니다. 이 파일에는 이 예제에서 사용하는 `spark-pi` 템플릿을 포함한 `WorkflowTemplate` 리소스가 포함되어 있습니다. `envsubst` 명령은 파일의 다른 템플릿에 필요한 변수를 대체합니다.

```bash
envsubst < $SPARK_DIR/examples/argo-workflows/manifests/spark-workflow-templates.yaml | kubectl apply -f -
```

다음으로 `argo-rbac.yaml` 파일을 적용하여 워크플로 실행에 필요한 Service Account와 Role Binding을 생성합니다.

```bash
kubectl apply -f $SPARK_DIR/examples/argo-workflows/manifests/argo-rbac.yaml
```

마지막으로 `argo-spark.yaml` 파일을 적용하여 워크플로 자체를 생성합니다.

```bash
kubectl apply -f $SPARK_DIR/examples/argo-workflows/manifests/argo-spark.yaml
```

### 2. 워크플로 확인

매니페스트를 적용하면 Argo Workflow가 생성됩니다. 명령줄에서 상태를 확인할 수 있습니다:

```bash
kubectl get wf -n argo-workflows
```

`spark-pi-xxxxx`와 같은 이름의 워크플로가 `Succeeded` 상태로 표시되어야 합니다. Argo Workflows UI에서 워크플로 그래프, 로그, 출력을 볼 수도 있습니다.

![argo-wf-spark](img/argo-wf-spark.png)

## 예제 2: Spark Operator를 통한 Spark 작업 제출

이 예제는 Spark Operator를 사용하여 Spark 작업을 오케스트레이션합니다. Argo Workflow가 `SparkApplication` 커스텀 리소스를 생성하면 Spark Operator가 Spark 작업의 라이프사이클을 관리합니다.

이 워크플로는 간단한 DAG(Directed Acyclic Graph) 구조를 가집니다: 데이터 준비 단계를 시뮬레이션하기 위해 두 개의 병렬 `wait` 태스크를 실행하고, 둘 다 완료되면 `SparkApplication`을 제출합니다.

### 1. 워크플로 적용

이전 예제에서 적용한 `spark-workflow-templates.yaml` 파일에는 이미 필요한 템플릿(`wait` 및 `submit-spark-pi-app`)이 포함되어 있습니다.

`argo-spark-operator.yaml` 매니페스트를 적용하여 워크플로를 제출합니다:

```bash
kubectl apply -f $SPARK_DIR/examples/argo-workflows/manifests/argo-spark-operator.yaml
```

### 2. 워크플로 확인

명령줄에서 워크플로 상태를 확인합니다:

```bash
kubectl get wf -n argo-workflows
```

`spark-operator`라는 이름의 워크플로가 `Running` 또는 `Succeeded` 상태로 표시됩니다. `spark-team-a` 네임스페이스에서 `SparkApplication` 리소스가 생성되었는지 확인할 수도 있습니다.

```bash
kubectl get sparkapp -n spark-team-a
```

Spark 작업이 완료되면 `SparkApplication` 상태가 `COMPLETED`로 변경되고 Argo Workflow는 `Succeeded`로 표시됩니다. Argo Workflows UI에서 DAG 시각화를 보고 태스크가 실행되는 것을 관찰할 수 있습니다.

![argo-wf-spark-operator](img/argo-wf-spark-operator.png)

## 예제 3: SQS 이벤트에서 Spark 작업 트리거

이 예제는 Argo의 강력한 기능인 이벤트 기반 워크플로를 보여줍니다. Amazon SQS 큐의 메시지를 수신 대기하도록 Argo Events를 구성합니다. 메시지가 도착하면 자동으로 Spark Operator를 사용하여 Spark 작업을 실행하는 Argo Workflow를 트리거합니다.

이 설정은 세 가지 주요 Argo Events 구성 요소로 구성됩니다:
- **EventBus:** Argo Events 시스템 내에서 이벤트를 전송하는 메시지 버스.
- **EventSource:** 외부 이벤트(이 경우 SQS 큐 폴링)를 수신 대기하고 EventBus에 게시하는 구성 요소.
- **Sensor:** EventBus의 이벤트를 수신 대기하고 해당 이벤트에 따라 작업(예: Argo Workflow 생성)을 트리거하는 구성 요소.

### 1. SQS 큐 및 이벤팅 인프라 생성

먼저 워크플로를 트리거하는 데 사용할 SQS 큐를 생성합니다.

```bash
QUEUE_URL=$(aws sqs create-queue --queue-name data-on-eks --region $REGION --output text)
echo "SQS Queue URL: $QUEUE_URL"
```

다음으로 Argo Events 구성 요소를 배포합니다. `eventbus.yaml` 매니페스트는 `EventBus` 리소스를 생성합니다.

```bash
kubectl apply -f $SPARK_DIR/examples/argo-workflows/manifests/eventbus.yaml
```

`eventsource-sqs.yaml` 매니페스트는 `data-on-eks` SQS 큐를 모니터링하도록 `EventSource`를 구성합니다. `envsubst`를 사용하여 매니페스트에 올바른 AWS 리전을 주입합니다.

```bash
cat $SPARK_DIR/examples/argo-workflows/manifests/eventsource-sqs.yaml | envsubst | kubectl apply -f -
```

### 2. Sensor 및 RBAC 배포

Sensor는 Argo Workflows를 생성할 권한이 필요합니다. `sensor-rbac.yaml` 매니페스트를 적용하여 필요한 `ServiceAccount`, `Role`, `RoleBinding`을 생성합니다.

```bash
kubectl apply -f $SPARK_DIR/examples/argo-workflows/manifests/sensor-rbac.yaml
```

이제 `sqs-spark-jobs.yaml` 매니페스트를 사용하여 `Sensor` 자체를 배포합니다. 이 Sensor는 SQS EventSource의 이벤트를 수신 대기하고 `spark-taxi-app` 템플릿을 실행하는 워크플로를 트리거하도록 구성되어 있습니다.

```bash
cat $SPARK_DIR/examples/argo-workflows/manifests/sqs-spark-jobs.yaml | envsubst | kubectl apply -f -
```

### 3. Argo Events 구성 요소 확인

`argo-events` 네임스페이스에서 모든 Argo Events 구성 요소가 올바르게 배포되었는지 확인할 수 있습니다.

```bash
kubectl get all,eventbus,eventsource,sensor -n argo-events
```

`EventBus` Pod, `EventSource` Pod, `Sensor` Pod가 `Running` 상태인지 확인합니다. 이는 이벤팅 파이프라인이 준비되었음을 나타냅니다.

### 4. 데이터 준비 및 워크플로 트리거

이 예제의 Spark 작업은 택시 여행 데이터를 처리합니다. 다음 스크립트를 실행하여 이 데이터를 생성하고 S3 버킷에 업로드합니다.

```bash
$SPARK_DIR/../scripts/taxi-trip-execute.sh $S3_BUCKET $REGION
```

이제 SQS 큐에 메시지를 전송하여 워크플로를 트리거합니다. 이 예제에서는 메시지 내용이 중요하지 않습니다.

```bash
aws sqs send-message --queue-url $QUEUE_URL --message-body '{"message": "hello world"}' --region $REGION
```

### 5. 결과 확인

거의 즉시 `EventSource`가 새 메시지를 감지하고 `Sensor`가 새 Argo Workflow를 트리거합니다.

워크플로 상태를 확인합니다:
```bash
kubectl get wf -n argo-workflows
```
`aws-sqs-spark-workflow-xxxxx`와 같은 이름의 새 워크플로가 `Running` 상태로 표시되어야 합니다.

`spark-team-a` 네임스페이스에서 생성되는 Spark 애플리케이션 Pod도 확인할 수 있습니다:
```bash
kubectl get po -n spark-team-a
```

UI에서 트리거된 워크플로와 해당 Spark 작업을 볼 수 있습니다.

![argo-wf-sqs-spark](img/argo-wf-sqs-spark.png)
![argo-wf-sqs-spark-tree](img/argo-wf-sqs-spark-tree.png)

## 정리

향후 요금이 발생하지 않도록 이 예제에서 생성된 리소스를 정리해야 합니다. Argo Workflows 및 Events 구성 요소 자체는 [기본 인프라 가이드](./infra.md)의 정리 단계를 따라 제거할 수 있습니다.

### 예제 1 및 2 리소스

처음 두 예제의 워크플로와 템플릿을 삭제하려면:

```bash
export SPARK_DIR=$(git rev-parse --show-toplevel)/data-stacks/spark-on-eks

# 워크플로 삭제
kubectl delete wf --all -n argo-workflows

# 워크플로 템플릿 및 관련 RBAC 삭제
kubectl delete -f $SPARK_DIR/examples/argo-workflows/manifests/argo-spark.yaml
kubectl delete -f $SPARK_DIR/examples/argo-workflows/manifests/spark-workflow-templates.yaml
```

### 예제 3 리소스

이벤트 기반 워크플로의 리소스를 삭제하려면:

```bash
export SPARK_DIR=$(git rev-parse --show-toplevel)/data-stacks/spark-on-eks
export REGION=$(terraform -chdir=$SPARK_DIR/terraform/_local output --raw region)
QUEUE_URL=$(aws sqs get-queue-url --queue-name data-on-eks --region $REGION --output text 2>/dev/null)

# Sensor, RBAC, EventSource, EventBus 삭제
kubectl delete -f $SPARK_DIR/examples/argo-workflows/manifests/sqs-spark-jobs.yaml --ignore-not-found=true
kubectl delete -f $SPARK_DIR/examples/argo-workflows/manifests/sensor-rbac.yaml --ignore-not-found=true
cat $SPARK_DIR/examples/argo-workflows/manifests/eventsource-sqs.yaml | envsubst | kubectl delete -f - --ignore-not-found=true
kubectl delete -f $SPARK_DIR/examples/argo-workflows/manifests/eventbus.yaml --ignore-not-found=true

# SQS 큐 삭제
if [ -n "$QUEUE_URL" ]; then
  aws sqs delete-queue --queue-url $QUEUE_URL --region $REGION
fi
```
