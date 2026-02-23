---
sidebar_position: 6
sidebar_label: Spark용 Mountpoint S3
---

import CollapsibleContent from '@site/src/components/CollapsibleContent';
import CodeBlock from '@theme/CodeBlock';

# Spark 워크로드용 Mountpoint S3

## 개요

[Spark Operator](https://github.com/kubeflow/spark-operator)로 관리되는 SparkApplication을 사용할 때 여러 종속성 JAR 파일을 처리하는 것은 상당한 문제를 야기합니다:

- **빌드 시간 증가**: 이미지 빌드 중 JAR 파일 다운로드로 빌드 시간 증가
- **이미지 크기 증가**: 번들된 JAR로 컨테이너 크기 및 풀 시간 증가
- **잦은 재빌드**: JAR 업데이트에 전체 이미지 재빌드 필요

[Mountpoint for Amazon S3](https://aws.amazon.com/s3/features/mountpoint/)는 S3 버킷을 로컬 파일 시스템으로 마운트하여 컨테이너 이미지에 포함하지 않고도 JAR에 원활하게 접근할 수 있도록 하여 이러한 문제를 해결합니다.

## Mountpoint S3란?

[Mountpoint S3](https://github.com/awslabs/mountpoint-s3)는 POSIX 파일 작업을 S3 API 호출로 변환하는 오픈 소스 파일 클라이언트입니다. 다음에 최적화되어 있습니다:
- 많은 동시 클라이언트에서 대형 객체에 대한 **높은 읽기 처리량**
- 단일 클라이언트에서 새 객체의 **순차 쓰기**
- **대규모 데이터 처리** 및 AI/ML 학습 워크로드

### 성능 기반: AWS CRT 라이브러리

Mountpoint S3의 높은 성능은 [AWS Common Runtime (CRT)](https://docs.aws.amazon.com/sdkref/latest/guide/common-runtime.html) 라이브러리로 구동됩니다:

- **효율적인 I/O 관리**: 논블로킹 I/O 작업으로 지연 시간 최소화
- **경량 설계**: 모듈식 아키텍처로 최소한의 오버헤드
- **고급 메모리 관리**: 가비지 컬렉션 오버헤드 감소
- **최적화된 네트워크 프로토콜**: AWS 환경에 맞게 튜닝된 HTTP/2

## 전제 조건

:::info
진행하기 전에 [인프라 설정 가이드](/data-on-eks/docs/datastacks/processing/spark-on-eks/infra)를 따라 Spark on EKS 인프라를 배포했는지 확인하세요.
:::

**필수 사항:**
- Spark on EKS 인프라 배포됨
- JAR 파일 및 종속성용 S3 버킷
- S3 접근 권한이 있는 IAM 역할
- 클러스터 접근을 위해 `kubectl` 구성됨

## 배포 접근 방식

Mountpoint S3는 **Pod 수준** 또는 **노드 수준**으로 배포할 수 있으며, 각각 다른 트레이드오프가 있습니다:

| 메트릭 | Pod 수준 (PVC) | 노드 수준 (HostPath) |
|--------|-----------------|----------------------|
| **접근 제어** | RBAC 및 서비스 계정을 통한 세밀한 제어 | 노드의 모든 Pod가 공유 접근 |
| **확장성** | 개별 PVC로 오버헤드 증가 | 구성 복잡성 감소 |
| **성능** | Pod당 격리된 성능 | 여러 Pod가 동일 버킷 접근 시 경합 가능 |
| **유연성** | 다른 Pod가 다른 데이터셋 접근 | 모든 Pod가 동일 데이터셋 공유 (공통 JAR에 이상적) |
| **캐싱** | 각 Pod에 별도 캐시 (더 많은 S3 API 호출) | Pod 간 공유 캐시 (더 적은 API 호출) |

**권장 사항:**
- **Pod 수준**: 엄격한 보안/규정 준수 또는 Pod 특정 데이터셋에 사용
- **노드 수준**: Spark 작업 간 공유 JAR 종속성에 사용 (비용 효율적인 캐싱)

## 접근 방식 1: PVC를 사용한 Pod 수준 배포

Pod 수준에서 Mountpoint S3를 배포하면 세밀한 접근 제어를 위해 Persistent Volume (PV) 및 Persistent Volume Claim (PVC)을 사용합니다.

**주요 기능:**
- S3 버킷이 클러스터 수준 리소스가 됨
- 서비스 계정 + RBAC로 PVC 접근 제한
- 각 Pod에 격리된 마운트 및 캐시

**제한 사항:** taints/tolerations를 지원하지 않음 (GPU 노드와 호환되지 않음)

자세한 Pod 수준 배포 지침은 [EKS Mountpoint S3 CSI 드라이버 문서](https://docs.aws.amazon.com/eks/latest/userguide/s3-csi.html)를 참조하세요.

## 접근 방식 2: 노드 수준 배포

노드 수준에서 S3를 마운트하면 노드의 모든 Pod 간에 단일 마운트를 공유하여 JAR 종속성 관리를 간소화합니다. **USERDATA** 또는 **DaemonSet**을 통해 구현할 수 있습니다.

### 일반적인 Mountpoint S3 인수

최적의 성능을 위해 다음 인수를 구성합니다:

```bash
mount-s3 \
  --metadata-ttl indefinite \  # JAR 파일은 불변 (읽기 전용)
  --allow-other \              # 모든 사용자/Pod 접근 활성화
  --cache /tmp/mountpoint-cache \  # S3 API 호출 줄이기 위한 캐싱 활성화
  <S3_BUCKET_NAME> /mnt/s3
```

**주요 매개변수:**
- `--metadata-ttl indefinite`: 정적 JAR에 대한 메타데이터 새로고침 없음
- `--allow-other`: Pod가 마운트에 접근 가능
- `--cache`: 반복 읽기를 위해 파일을 로컬에 캐시 (비용 최적화에 중요)

추가 구성 옵션은 [Mountpoint S3 구성 문서](https://github.com/awslabs/mountpoint-s3/blob/main/doc/CONFIGURATION.md)를 참조하세요.

### 접근 방식 2.1: USERDATA (권장)

새 클러스터 또는 노드가 동적으로 프로비저닝되는 Karpenter 기반 자동 확장에 USERDATA를 사용합니다.

**장점:**
- 노드 초기화 중 실행
- 노드 특정 구성 지원 (NodePool별 다른 버킷)
- 워크로드 특정 노드를 위한 Karpenter taints/tolerations와 통합

**USERDATA 스크립트:**

```bash
#!/bin/bash
set -e

# 시스템 업데이트 및 종속성 설치
yum update -y
yum install -y wget fuse

# Mountpoint S3 다운로드 및 설치
wget https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.rpm
yum install -y ./mount-s3.rpm

# 마운트 포인트 생성
mkdir -p /mnt/s3

# 캐싱과 함께 S3 버킷 마운트
/opt/aws/mountpoint-s3/bin/mount-s3 \
  --metadata-ttl indefinite \
  --allow-other \
  --cache /tmp/mountpoint-cache \
  <S3_BUCKET_NAME> /mnt/s3

# 마운트 확인
mount | grep /mnt/s3
```

**Karpenter 통합 예제:**

```yaml
# USERDATA가 포함된 Karpenter NodePool
apiVersion: karpenter.sh/v1beta1
kind: EC2NodeClass
metadata:
  name: spark-jars
spec:
  userData: |
    #!/bin/bash
    yum update -y && yum install -y wget fuse
    wget https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.rpm
    yum install -y ./mount-s3.rpm
    mkdir -p /mnt/s3-jars
    /opt/aws/mountpoint-s3/bin/mount-s3 \
      --metadata-ttl indefinite \
      --allow-other \
      --cache /tmp/mountpoint-cache \
      my-spark-jars-bucket /mnt/s3-jars
```

### 접근 방식 2.2: DaemonSet (기존 클러스터용)

재시작할 수 없거나 USERDATA 커스터마이징이 없는 정적 노드가 있는 경우 DaemonSet을 사용합니다.

**아키텍처:**
1. **ConfigMap**: Mountpoint S3 설치 및 유지 관리 스크립트
2. **DaemonSet**: 모든 노드에서 스크립트를 실행하는 Pod

**보안 고려 사항:**

:::danger
DaemonSet은 상승된 권한이 필요합니다. 프로덕션 사용 전에 보안 영향을 검토하세요.
:::

**필요한 권한:**
- `privileged: true` - 패키지 설치를 위한 전체 호스트 접근
- `hostPID: true` - `nsenter`를 통해 호스트 PID 네임스페이스 진입
- `hostIPC: true` - 공유 메모리 접근 (필요한 경우)
- `hostNetwork: true` - 인터넷에서 패키지 다운로드

**DaemonSet 예제:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mountpoint-s3-script
  namespace: spark-team-a
data:
  mount-s3.sh: |
    #!/bin/bash
    set -e

    # 구성
    S3_BUCKET="${S3_BUCKET_NAME:-my-spark-jars}"
    MOUNT_POINT="/mnt/s3"
    CACHE_DIR="/tmp/mountpoint-cache"
    LOG_FILE="/var/log/mountpoint-s3.log"

    # Mountpoint S3가 없으면 설치
    if ! command -v mount-s3 &> /dev/null; then
      echo "Installing Mountpoint S3..." | tee -a $LOG_FILE
      wget https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.rpm
      yum install -y ./mount-s3.rpm
    fi

    # 헬스 체크가 포함된 마운트 루프
    while true; do
      if ! mountpoint -q $MOUNT_POINT; then
        echo "Mounting S3 bucket $S3_BUCKET..." | tee -a $LOG_FILE
        mkdir -p $MOUNT_POINT $CACHE_DIR
        mount-s3 \
          --metadata-ttl indefinite \
          --allow-other \
          --cache $CACHE_DIR \
          $S3_BUCKET $MOUNT_POINT
      fi
      sleep 60  # 헬스 체크 간격
    done
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: mountpoint-s3
  namespace: spark-team-a
spec:
  selector:
    matchLabels:
      app: mountpoint-s3
  template:
    metadata:
      labels:
        app: mountpoint-s3
    spec:
      serviceAccountName: spark-team-a
      hostPID: true
      hostIPC: true
      hostNetwork: true
      containers:
      - name: mountpoint-installer
        image: amazonlinux:2023
        command:
        - /bin/bash
        - -c
        - |
          yum install -y util-linux
          cp /scripts/mount-s3.sh /host/tmp/mount-s3.sh
          chmod +x /host/tmp/mount-s3.sh
          nsenter --target 1 --mount --uts --ipc --net --pid -- /tmp/mount-s3.sh
        env:
        - name: S3_BUCKET_NAME
          value: "my-spark-jars"  # 버킷으로 교체
        securityContext:
          privileged: true
        volumeMounts:
        - name: host
          mountPath: /host
        - name: scripts
          mountPath: /scripts
      volumes:
      - name: host
        hostPath:
          path: /
      - name: scripts
        configMap:
          name: mountpoint-s3-script
```

:::warning
이 예제는 사전 구성된 IRSA가 있는 `spark-team-a` 네임스페이스를 사용합니다. 프로덕션에서는:
- DaemonSet을 위한 전용 네임스페이스 생성
- 최소 권한 IAM 역할 사용
- 특정 경로에 대한 S3 버킷 접근 제한
- [IAM 모범 사례](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html) 따르기
:::

## 실습: Mountpoint S3로 Spark 작업 배포

### 단계 1: JAR가 있는 S3 버킷 준비

Spark 종속성 JAR를 S3에 업로드:

```bash
cd data-stacks/spark-on-eks/examples/mountpoint-s3

# 샘플 JAR 업로드 (Hadoop AWS, AWS SDK)
aws s3 cp hadoop-aws-3.3.1.jar s3://${S3_BUCKET}/jars/
aws s3 cp aws-java-sdk-bundle-1.12.647.jar s3://${S3_BUCKET}/jars/

# 또는 제공된 스크립트 사용
chmod +x copy-jars-to-s3.sh
./copy-jars-to-s3.sh
```

### 단계 2: DaemonSet 배포 (노드 수준 접근 방식)

```bash
# DaemonSet YAML에서 S3_BUCKET 업데이트
export S3_BUCKET=my-spark-jars

# DaemonSet 배포
kubectl apply -f mountpoint-s3-daemonset.yaml

# DaemonSet Pod 실행 확인
kubectl get pods -n spark-team-a -l app=mountpoint-s3
```

### 단계 3: Spark 작업 제출

마운트된 JAR를 참조하는 SparkApplication 생성:

```yaml
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: spark-with-mountpoint
  namespace: spark-team-a
spec:
  type: Python
  mode: cluster
  image: "public.ecr.aws/data-on-eks/spark:3.5.3-scala2.12-java17-python3-ubuntu"
  mainApplicationFile: "local:///opt/spark/examples/src/main/python/pi.py"

  sparkConf:
    # Mountpoint S3 마운트에서 JAR 참조
    "spark.jars": "file:///mnt/s3/jars/hadoop-aws-3.3.1.jar,file:///mnt/s3/jars/aws-java-sdk-bundle-1.12.647.jar"

    # S3 구성
    "spark.hadoop.fs.s3a.aws.credentials.provider": "software.amazon.awssdk.auth.credentials.ContainerCredentialsProvider"

  driver:
    cores: 1
    memory: "512m"
    serviceAccount: spark-team-a
    nodeSelector:
      NodeGroupType: "SparkComputeOptimized"

  executor:
    cores: 1
    instances: 2
    memory: "512m"
    serviceAccount: spark-team-a
    nodeSelector:
      NodeGroupType: "SparkComputeOptimized"
```

```bash
kubectl apply -f spark-with-mountpoint.yaml
```

### 단계 4: 작업 실행 모니터링

```bash
# SparkApplication 상태 확인
kubectl get sparkapplication -n spark-team-a -w

# Driver 로그 확인
kubectl logs -n spark-team-a spark-with-mountpoint-driver -f

# Executor 로그 확인
kubectl logs -n spark-team-a spark-with-mountpoint-exec-1 -f
```

## 확인

### Mountpoint S3에서 JAR 로딩 확인

Executor 로그에서 JAR 복사 작업 확인:

```text
24/08/13 00:08:46 INFO Executor: Fetching file:/mnt/s3/jars/hadoop-aws-3.3.1.jar
24/08/13 00:08:46 INFO Utils: Copying /mnt/s3/jars/hadoop-aws-3.3.1.jar to /var/data/spark-...
24/08/13 00:08:46 INFO Executor: Adding file:/opt/spark/work-dir/./hadoop-aws-3.3.1.jar to class loader
```

### 노드에서 Mountpoint S3 설치 확인

SSM을 통해 노드에 연결하고 확인:

```bash
# Mountpoint S3 버전 확인
mount-s3 --version

# 마운트 포인트 확인
mount | grep /mnt/s3

# 캐시된 JAR 확인 (첫 번째 작업 실행 후)
sudo ls -lh /tmp/mountpoint-cache/
```

**예상 출력:**
```
/mnt/s3 type fuse.mountpoint-s3 (rw,nosuid,nodev,relatime,user_id=0,group_id=0,allow_other)
```

### 캐시 효과 확인

여러 작업 실행 후 캐시에 JAR 파일이 포함되어야 합니다:

```bash
sudo du -sh /tmp/mountpoint-cache/
# 예제 출력: 256M  /tmp/mountpoint-cache/
```

**캐시 이점:**
- 후속 작업이 캐시에서 읽기 (S3 API 호출 없음)
- S3 요청 비용 감소
- 더 빠른 Executor 시작 (다운로드 지연 없음)

## 프로덕션 모범 사례

### 1. 캐시 관리

```bash
# 캐시 크기 제한 구성
mount-s3 \
  --cache /tmp/mountpoint-cache \
  --max-cache-size 10737418240 \  # 10 GB 제한
  my-bucket /mnt/s3
```

### 2. 로깅 및 디버깅

문제 해결을 위한 상세 로깅 활성화:

```bash
mount-s3 \
  --log-directory /var/log/mountpoint-s3 \
  --debug \
  my-bucket /mnt/s3
```

[Mountpoint S3 로깅 문서](https://github.com/awslabs/mountpoint-s3/blob/main/doc/LOGGING.md)를 참조하세요.

### 3. IAM 권한

읽기 전용 JAR 접근을 위한 최소 S3 권한:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-spark-jars",
        "arn:aws:s3:::my-spark-jars/jars/*"
      ]
    }
  ]
}
```

### 4. 멀티 버킷 전략

다른 워크로드 유형에 대해 다른 마운트 포인트 사용:

```bash
# 프로덕션 JAR
mount-s3 prod-jars-bucket /mnt/s3/prod-jars

# 개발 JAR
mount-s3 dev-jars-bucket /mnt/s3/dev-jars

# ML 모델
mount-s3 ml-models-bucket /mnt/s3/ml-models
```

## 문제 해결

### "Permission Denied"로 마운트 실패

**원인:** `fuse` 커널 모듈 누락 또는 사용자 권한

**해결:**
```bash
# fuse 설치
yum install -y fuse

# fuse 모듈 로드 확인
lsmod | grep fuse

# --allow-other 플래그 설정 확인
```

### 높은 S3 API 비용

**원인:** 캐시가 활성화되지 않았거나 캐시 퇴거

**해결:**
```bash
# 충분한 크기로 캐시 활성화
mount-s3 \
  --cache /tmp/mountpoint-cache \
  --max-cache-size 53687091200 \  # 50 GB
  --metadata-ttl indefinite \
  my-bucket /mnt/s3
```

### Pod가 /mnt/s3에 접근할 수 없음

**원인:** `--allow-other` 플래그 누락 또는 잘못된 권한

**해결:**
```bash
# --allow-other로 다시 마운트
umount /mnt/s3
mount-s3 --allow-other my-bucket /mnt/s3

# 권한 확인
ls -la /mnt/s3
```

### DaemonSet Pod가 CrashLoopBackOff

**원인:** 권한 부족 또는 호스트 접근 누락

**해결:**
```yaml
# 모든 필수 권한 설정 확인
securityContext:
  privileged: true
hostPID: true
hostIPC: true
hostNetwork: true
```

## 비용 최적화

### S3 요청 비용 비교

**캐싱 없음 (Executor당 작업당):**
- 10 Executor x 5 JAR = 50 GET 요청
- 월 1000 작업 = 50,000 GET 요청
- 비용: 약 $0.20/월 ($0.0004/1000 요청 기준)

**캐싱 사용 (공유 노드 캐시):**
- 첫 번째 Executor: 5 GET 요청
- 후속 Executor: 0 GET 요청 (캐시 히트)
- 월 1000 작업 = 5,000 GET 요청
- 비용: 약 $0.02/월 (90% 절감)

### 스토리지 비용 절감

**컨테이너 이미지의 JAR:**
- 5 JAR x 50 MB = 이미지당 250 MB
- 10 이미지 버전 = ECR에 2.5 GB
- ECR 비용: $0.25/월

**Mountpoint가 있는 S3의 JAR:**
- 5 JAR x 50 MB = S3에 250 MB
- S3 비용: $0.006/월 (98% 저렴)

## 결론

Mountpoint for Amazon S3는 다음을 통해 Spark on EKS를 위한 비용 효율적이고 고성능 JAR 종속성 관리를 가능하게 합니다:
- 컨테이너 이미지에서 **종속성 분리**
- **빌드 시간** 및 이미지 크기 **감소**
- Pod 간 **공유 캐싱** 활성화 (노드 수준 배포)
- 저렴한 S3 비용으로 **거의 무제한 스토리지** 제공

캐싱 이점을 최대화하고 S3 API 비용을 최소화하려면 공유 Spark JAR 종속성에 대해 DaemonSet 또는 USERDATA가 있는 **노드 수준 배포**를 선택하세요.

## 관련 리소스

- [Mountpoint S3 GitHub 리포지토리](https://github.com/awslabs/mountpoint-s3)
- [Mountpoint S3 구성 가이드](https://github.com/awslabs/mountpoint-s3/blob/main/doc/CONFIGURATION.md)
- [AWS CRT 라이브러리 문서](https://docs.aws.amazon.com/sdkref/latest/guide/common-runtime.html)
- [EKS Mountpoint S3 CSI 드라이버](https://docs.aws.amazon.com/eks/latest/userguide/s3-csi.html)
- [인프라 설정 가이드](/data-on-eks/docs/datastacks/processing/spark-on-eks/infra)
