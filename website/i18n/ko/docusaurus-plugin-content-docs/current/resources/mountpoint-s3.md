---
sidebar_position: 2
sidebar_label: EKS에서 Mountpoint-S3
---

# Mountpoint S3: Amazon EKS에서 데이터 및 AI 워크로드를 위한 Amazon S3 파일 액세스 향상

## Mountpoint-S3란?

[Mountpoint-S3](https://github.com/awslabs/mountpoint-s3)는 AWS가 개발한 오픈 소스 파일 클라이언트로 파일 작업을 S3 API 호출로 변환하여 애플리케이션이 [Amazon S3](https://aws.amazon.com/s3/) 버킷을 로컬 디스크처럼 상호 작용할 수 있게 합니다. Mountpoint for Amazon S3는 잠재적으로 많은 클라이언트에서 한 번에 대용량 객체에 대한 높은 읽기 처리량이 필요하고 한 번에 단일 클라이언트에서 새 객체를 순차적으로 쓰는 애플리케이션에 최적화되어 있습니다. 기존 S3 액세스 방법에 비해 상당한 성능 향상을 제공하여 데이터 집약적 워크로드 및 AI/ML 학습에 이상적입니다.

Mountpoint-S3의 주요 기능은 [Amazon S3 Standard](https://aws.amazon.com/s3/storage-classes/) 및 [Amazon S3 Express One Zone](https://aws.amazon.com/s3/storage-classes/)과의 호환성입니다. S3 Express One Zone은 *단일 가용 영역 배포*를 위해 설계된 고성능 스토리지 클래스입니다. 자주 액세스하는 데이터와 지연 시간에 민감한 애플리케이션에 이상적인 일관된 한 자릿수 밀리초 데이터 액세스를 제공합니다. S3 Express One Zone은 S3 Standard에 비해 최대 10배 빠른 데이터 액세스 속도와 최대 50% 낮은 요청 비용을 제공하는 것으로 알려져 있습니다. 이 스토리지 클래스를 통해 사용자는 동일한 가용 영역에 스토리지와 컴퓨팅 리소스를 함께 배치하여 성능을 최적화하고 잠재적으로 컴퓨팅 비용을 절감할 수 있습니다.

S3 Express One Zone과의 통합은 Mountpoint-S3의 기능을 향상시키며, 특히 머신 러닝 및 분석 워크로드에서 [Amazon EKS](https://aws.amazon.com/eks/), [Amazon SageMaker Model Training](https://aws.amazon.com/sagemaker/train/), [Amazon Athena](https://aws.amazon.com/athena/), [Amazon EMR](https://aws.amazon.com/emr/) 및 [AWS Glue Data Catalog](https://docs.aws.amazon.com/prescriptive-guidance/latest/serverless-etl-aws-glue/aws-glue-data-catalog.html)와 같은 서비스와 함께 사용할 수 있습니다. S3 Express One Zone의 소비 기반 자동 스토리지 스케일링은 낮은 지연 시간 워크로드 관리를 단순화하여 Mountpoint-S3를 다양한 데이터 집약적 작업 및 AI/ML 학습 환경에 매우 효과적인 도구로 만듭니다.


:::warning

Mountpoint-S3는 파일 이름 변경 작업을 지원하지 않으므로 이러한 기능이 필수적인 시나리오에서 적용 가능성이 제한될 수 있습니다.

:::


## Amazon EKS에서 Mountpoint-S3 배포:

### 1단계: S3 CSI 드라이버용 IAM 역할 설정

S3 CSI 드라이버에 필요한 권한이 있는 IAM 역할을 Terraform으로 생성합니다. 이 단계는 EKS와 S3 간의 안전하고 효율적인 통신을 보장하는 데 중요합니다.


```terraform

#---------------------------------------------------------------
# Mountpoint for Amazon S3 CSI Driver용 IRSA
#---------------------------------------------------------------
module "s3_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.34"
  role_name_prefix      = format("%s-%s-", local.name, "s3-csi-driver")
  role_policy_arns = {
    # 경고: 데모 목적으로만 사용. 최소 권한으로 자체 IAM 정책 가져오기
    s3_csi_driver = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  }
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:s3-csi-driver-sa"]
    }
  }
  tags = local.tags
}

```

### 2단계: EKS Blueprints 애드온 구성

S3 CSI 드라이버의 Amazon EKS 애드온에 이 역할을 활용하도록 EKS Blueprints 애드온 Terraform 모듈을 구성합니다.

```terraform
#---------------------------------------------------------------
# EKS Blueprints 애드온
#---------------------------------------------------------------
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.2"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------
  # Amazon EKS 관리형 애드온
  #---------------------------------------
  eks_addons = {
    aws-mountpoint-s3-csi-driver = {
      service_account_role_arn = module.s3_csi_driver_irsa.iam_role_arn
    }
  }
}

```

### 3단계: PersistentVolume 정의

PersistentVolume(PV) 구성에서 S3 버킷, 리전 세부 정보 및 액세스 모드를 지정합니다. 이 단계는 EKS가 S3 버킷과 상호 작용하는 방식을 정의하는 데 중요합니다.

```yaml
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: s3-pv
spec:
  capacity:
    storage: 1200Gi # 무시됨, 필수
  accessModes:
    - ReadWriteMany # 지원되는 옵션: ReadWriteMany / ReadOnlyMany
  mountOptions:
    - uid=1000
    - gid=2000
    - allow-other
    - allow-delete
    - region <ENTER_REGION>
  csi:
    driver: s3.csi.aws.com # 필수
    volumeHandle: s3-csi-driver-volume
    volumeAttributes:
      bucketName: <ENTER_S3_BUCKET_NAME>
```

### 4단계: PersistentVolumeClaim 생성

정의된 PV를 활용하기 위해 액세스 모드 및 정적 프로비저닝 요구 사항을 지정하는 PersistentVolumeClaim(PVC)을 설정합니다.

```yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: s3-claim
  namespace: spark-team-a
spec:
  accessModes:
    - ReadWriteMany # 지원되는 옵션: ReadWriteMany / ReadOnlyMany
  storageClassName: "" # 정적 프로비저닝에 필수
  resources:
    requests:
      storage: 1200Gi # 무시됨, 필수
  volumeName: s3-pv

```

### 5단계: Pod 정의에서 PVC 사용
PersistentVolumeClaim(PVC)을 설정한 후 다음 단계는 Pod 정의 내에서 이를 활용하는 것입니다. 이를 통해 Kubernetes에서 실행 중인 애플리케이션이 S3 버킷에 저장된 데이터에 액세스할 수 있습니다. 아래는 다양한 시나리오에 대해 Pod 정의에서 PVC를 참조하는 방법을 보여주는 예제입니다.

#### 예제 1: 스토리지에 PVC를 사용하는 기본 Pod

이 예제는 `s3-claim` PVC를 컨테이너 내의 디렉토리에 마운트하는 기본 Pod 정의를 보여줍니다.

이 예제에서 PVC `s3-claim`은 nginx 컨테이너의 `/data` 디렉토리에 마운트됩니다. 이 설정을 통해 컨테이너 내에서 실행 중인 애플리케이션이 로컬 디렉토리인 것처럼 S3 버킷에 데이터를 읽고 쓸 수 있습니다.

```yaml

apiVersion: v1
kind: Pod
metadata:
  name: example-pod
  namespace: spark-team-a
spec:
  containers:
    - name: app-container
      image: nginx  # 예제 이미지
      volumeMounts:
        - name: s3-storage
          mountPath: "/data"  # S3 버킷이 마운트될 경로
  volumes:
    - name: s3-storage
      persistentVolumeClaim:
        claimName: s3-claim

```

#### 예제 2: PVC를 사용하는 AI/ML 학습 작업

AI/ML 학습 시나리오에서는 데이터 접근성과 처리량이 중요합니다. 이 예제는 S3에 저장된 데이터셋에 액세스하는 머신 러닝 학습 작업에 대한 Pod 구성을 보여줍니다.

```yaml

apiVersion: v1
kind: Pod
metadata:
  name: ml-training-pod
  namespace: spark-team-a
spec:
  containers:
    - name: training-container
      image: ml-training-image  # ML 학습 이미지로 교체
      volumeMounts:
        - name: dataset-storage
          mountPath: "/datasets"  # 학습 데이터의 마운트 경로
  volumes:
    - name: dataset-storage
      persistentVolumeClaim:
        claimName: s3-claim

```

:::warning

Mountpoint S3는 Amazon S3 또는 S3 express와 함께 사용할 때 Spark 워크로드의 셔플 스토리지로 적합하지 않을 수 있습니다. 이 제한은 Spark의 셔플 작업 특성에서 비롯되며, 종종 여러 클라이언트가 동일한 위치에 동시에 읽고 쓰는 것을 포함합니다.

또한 Mountpoint S3는 Spark의 효율적인 셔플 작업에 필요한 중요한 기능인 파일 이름 변경을 지원하지 않습니다. 이러한 이름 변경 기능의 부족은 데이터 처리 작업에서 운영 문제와 잠재적인 성능 병목 현상을 초래할 수 있습니다.

:::


## 다음 단계:

- 자세한 배포 지침은 제공된 Terraform 코드 스니펫을 탐색하세요.
- 추가 구성 옵션 및 제한 사항은 공식 Mountpoint-S3 문서를 참조하세요.
- Mountpoint-S3를 활용하여 EKS 애플리케이션 내에서 고성능, 확장 가능한 S3 액세스를 잠금 해제하세요.

Mountpoint-S3의 기능과 제한 사항을 이해함으로써 Amazon EKS에서 데이터 기반 워크로드를 최적화하기 위한 정보에 입각한 결정을 내릴 수 있습니다.
