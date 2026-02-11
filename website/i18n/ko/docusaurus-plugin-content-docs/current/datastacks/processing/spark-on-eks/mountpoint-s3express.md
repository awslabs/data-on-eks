---
title: Mountpoint S3 Express
sidebar_position: 7
---

# Mountpoint S3 Express

이 예제는 고처리량 Spark 분석 워크로드를 위한 단일 자릿수 밀리초 지연 시간의 초고성능 S3 Express One Zone 스토리지를 보여줍니다.

## 개요

S3 Express One Zone은 자주 접근하는 데이터에 대해 일관된 단일 자릿수 밀리초 데이터 접근을 제공하는 고성능 스토리지 클래스입니다. Mountpoint for S3와 결합하면 Spark 워크로드를 위한 가장 빠른 S3 통합을 제공합니다.

## 주요 기능

- **초저지연**: 단일 자릿수 밀리초 접근 시간
- **높은 처리량**: 표준 S3보다 최대 10배 빠름
- **존 최적화**: 최소 네트워크 지연을 위해 컴퓨팅과 함께 배치
- **비용 효율적**: 최소 약정 없이 사용한 만큼만 지불
- **POSIX 인터페이스**: Mountpoint를 통한 표준 파일 시스템 시맨틱

## 전제 조건

이 예제를 배포하기 전에 다음을 확인하세요:

- [인프라 배포됨](/data-on-eks/docs/datastacks/processing/spark-on-eks/infra)
- EKS 클러스터용으로 `kubectl` 구성됨
- EKS 노드와 동일한 AZ에 S3 Express One Zone 버킷 생성됨
- S3 Express 권한이 있는 IAM 역할

## 빠른 배포 및 테스트

### 1. S3 Express One Zone 버킷 생성

```bash
# EKS 클러스터와 동일한 AZ에 S3 Express 버킷 생성
export AZ="us-west-2a"
export BUCKET_NAME="spark-express-${RANDOM}--${AZ}--x-s3"

aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --create-bucket-configuration LocationConstraint=us-west-2 \
  --bucket-type Directory

# S3 Express One Zone 활성화
aws s3api put-bucket-accelerate-configuration \
  --bucket $BUCKET_NAME \
  --accelerate-configuration Status=Enabled
```

### 2. Mountpoint for S3 Express 배포

```bash
# data-stacks 디렉토리로 이동
cd data-stacks/spark-on-eks

# 구성에서 버킷 이름 업데이트
export S3_EXPRESS_BUCKET=$BUCKET_NAME
envsubst < examples/mountpoint-s3-spark/mountpoint-s3express-daemonset.yaml | kubectl apply -f -
```

### 3. Spark Application 배포

```bash
# S3 Express 최적화 Spark 작업 배포
envsubst < examples/mountpoint-s3-spark/spark-s3express-job.yaml | kubectl apply -f -
```

### 4. 성능 확인

```bash
# Spark 애플리케이션 모니터링
kubectl get sparkapplications -n spark-team-a

# 지연 시간 메트릭 확인
kubectl logs -n spark-team-a -l spark-role=driver | grep -i "s3.*time"

# 상세 성능 메트릭 보기
kubectl port-forward -n spark-history svc/spark-history-server 18080:80
```

## 구성 세부 정보

### S3 Express One Zone 구성

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: s3express-config
  namespace: spark-team-a
data:
  bucket: "spark-express-123--us-west-2a--x-s3"
  region: "us-west-2"
  availability-zone: "us-west-2a"
  endpoint: "https://s3express-control.us-west-2.amazonaws.com"
```

### Mountpoint S3 Express DaemonSet

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: mountpoint-s3express
  namespace: kube-system
spec:
  template:
    spec:
      containers:
      - name: mountpoint-s3express
        image: public.ecr.aws/mountpoint-s3/mountpoint-s3-csi-driver:latest
        args:
          - "--cache-size=20GB"
          - "--part-size=8MB"
          - "--max-concurrent-requests=64"
          - "--read-timeout=5s"
          - "--write-timeout=10s"
          - "--s3-express-one-zone"
        env:
        - name: S3_EXPRESS_BUCKET
          valueFrom:
            configMapKeyRef:
              name: s3express-config
              key: bucket
```

### Spark Application 최적화

```yaml
spec:
  sparkConf:
    "spark.hadoop.fs.s3a.impl": "org.apache.hadoop.fs.s3a.S3AFileSystem"
    "spark.hadoop.fs.s3a.s3express.create.session": "true"
    "spark.hadoop.fs.s3a.s3express.session.duration": "300"
    "spark.hadoop.fs.s3a.connection.maximum": "200"
    "spark.hadoop.fs.s3a.fast.upload": "true"
    "spark.hadoop.fs.s3a.multipart.size": "8388608"
    "spark.hadoop.fs.s3a.multipart.threshold": "8388608"
    "spark.sql.adaptive.enabled": "true"
    "spark.sql.adaptive.coalescePartitions.enabled": "true"
    "spark.sql.adaptive.advisoryPartitionSizeInBytes": "134217728"
```

## 성능 검증

### 지연 시간 벤치마킹

```bash
# 지연 시간에 민감한 워크로드 실행
kubectl apply -f - <<EOF
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: s3express-latency-test
  namespace: spark-team-a
spec:
  type: Python
  mode: cluster
  image: public.ecr.aws/spark/spark-py:3.5.0
  mainApplicationFile: "s3a://${S3_EXPRESS_BUCKET}/scripts/latency-test.py"
  sparkConf:
    "spark.hadoop.fs.s3a.s3express.create.session": "true"
    "spark.eventLog.enabled": "true"
    "spark.eventLog.dir": "s3a://${S3_EXPRESS_BUCKET}/spark-logs/"
  driver:
    cores: 2
    memory: "4g"
  executor:
    cores: 4
    instances: 8
    memory: "8g"
EOF
```

### 처리량 테스트

```bash
# I/O 성능 모니터링
kubectl exec -n spark-team-a <driver-pod> -- iostat -x 1 10

# S3 Express 메트릭 확인
aws cloudwatch get-metric-statistics \
  --namespace AWS/S3 \
  --metric-name NumberOfObjects \
  --dimensions Name=BucketName,Value=$S3_EXPRESS_BUCKET \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

## 예상 결과

- **초저지연**: 핫 데이터에 대해 10ms 미만 접근 시간
- **높은 처리량**: 표준 S3보다 10배 빠름
- **일관된 성능**: 부하 상태에서 예측 가능한 지연 시간
- **비용 최적화**: 최소 약정 없는 요청당 과금
- **Spark 통합**: 기존 Spark 코드와 원활한 통합

## 문제 해결

### 일반적인 문제

**S3 Express 세션 생성 실패:**
```bash
# S3 Express에 대한 IAM 권한 확인
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT:role/spark-team-a \
  --action-names s3express:CreateSession \
  --resource-arns arn:aws:s3express:us-west-2:ACCOUNT:bucket/$S3_EXPRESS_BUCKET

# 버킷 구성 확인
aws s3api describe-bucket --bucket $S3_EXPRESS_BUCKET
```

**S3 Express에도 불구하고 높은 지연 시간:**
```bash
# AZ 정렬 확인
kubectl get nodes -o custom-columns=NAME:.metadata.name,ZONE:.metadata.labels.'topology\.kubernetes\.io/zone'

# S3 Express 엔드포인트 확인
kubectl exec -n spark-team-a <pod-name> -- nslookup s3express-control.us-west-2.amazonaws.com

# 네트워크 지연 시간 모니터링
kubectl exec -n spark-team-a <pod-name> -- ping -c 10 s3express-control.us-west-2.amazonaws.com
```

**성능 저하:**
```bash
# Mountpoint 캐시 사용률 확인
kubectl exec -n kube-system <mountpoint-pod> -- df -h /mnt/s3express-cache

# 동시 요청 제한 모니터링
kubectl logs -n kube-system -l app=mountpoint-s3express | grep -i "throttl\|limit"

# S3 Express 용량 확인
aws s3api get-bucket-location --bucket $S3_EXPRESS_BUCKET
```

## 고급 구성

### 멀티 AZ 배포

```yaml
# HA를 위해 여러 AZ에 배포
apiVersion: v1
kind: ConfigMap
metadata:
  name: s3express-multi-az
data:
  primary-bucket: "spark-express-123--us-west-2a--x-s3"
  secondary-bucket: "spark-express-456--us-west-2b--x-s3"
  tertiary-bucket: "spark-express-789--us-west-2c--x-s3"
```

### 세션 관리

```yaml
# S3 Express 세션 구성 최적화
spec:
  sparkConf:
    "spark.hadoop.fs.s3a.s3express.create.session": "true"
    "spark.hadoop.fs.s3a.s3express.session.duration": "900"
    "spark.hadoop.fs.s3a.s3express.session.cache.size": "1000"
    "spark.hadoop.fs.s3a.s3express.session.refresh.interval": "600"
```

### 요청 최적화

```yaml
# 최대 성능을 위한 튜닝
spec:
  sparkConf:
    "spark.hadoop.fs.s3a.connection.maximum": "500"
    "spark.hadoop.fs.s3a.threads.max": "64"
    "spark.hadoop.fs.s3a.max.total.tasks": "100"
    "spark.hadoop.fs.s3a.multipart.uploads.enabled": "true"
    "spark.hadoop.fs.s3a.fast.upload.buffer": "bytebuffer"
```

## 비용 최적화

### 요청 패턴 분석

```bash
# 요청 패턴 모니터링
aws cloudwatch get-metric-statistics \
  --namespace AWS/S3 \
  --metric-name AllRequests \
  --dimensions Name=BucketName,Value=$S3_EXPRESS_BUCKET \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Sum

# 요청당 비용 분석
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -d '1 day ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) \
  --granularity DAILY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

### 데이터 라이프사이클 관리

```yaml
# 자동 정리 구성
apiVersion: batch/v1
kind: CronJob
metadata:
  name: s3express-cleanup
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: cleanup
            image: amazon/aws-cli:latest
            command:
            - /bin/sh
            - -c
            - |
              aws s3api list-objects-v2 --bucket $S3_EXPRESS_BUCKET \
                --query 'Contents[?LastModified<`$(date -u -d "7 days ago" +%Y-%m-%d)`].Key' \
                --output text | xargs -I {} aws s3api delete-object --bucket $S3_EXPRESS_BUCKET --key {}
```

## 관련 예제

- [Mountpoint S3](/data-on-eks/docs/datastacks/processing/spark-on-eks/mountpoint-s3) - Mountpoint가 있는 표준 S3
- [S3 Tables](/data-on-eks/docs/datastacks/processing/spark-on-eks/s3tables) - S3 Express와 Iceberg 통합
- [관측성](/data-on-eks/docs/datastacks/processing/spark-on-eks/observability) - 성능 모니터링

## 추가 리소스

- [S3 Express One Zone 문서](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-express-one-zone.html)
- [S3 Express 성능 가이드](https://aws.amazon.com/s3/storage-classes/express-one-zone/)
- [Mountpoint S3 Express 구성](https://github.com/awslabs/mountpoint-s3/blob/main/doc/CONFIGURATION.md)
