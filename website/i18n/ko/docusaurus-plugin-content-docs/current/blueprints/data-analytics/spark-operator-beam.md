---
sidebar_position: 5
sidebar_label: EKS에서 Apache Beam
hide_table_of_contents: true
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '@site/src/components/CollapsibleContent';

import CodeBlock from '@theme/CodeBlock';

# EKS에서 Spark로 Apache Beam 파이프라인 실행

[Apache Beam (Beam)](https://beam.apache.org/get-started/beam-overview/)은 배치 및 스트리밍 데이터 처리 파이프라인을 구축하기 위한 유연한 프로그래밍 모델입니다. Beam을 사용하면 개발자가 코드를 한 번 작성하고 *Apache Spark* 및 *Apache Flink*와 같은 다양한 실행 엔진에서 실행할 수 있습니다. 이러한 유연성을 통해 조직은 일관된 코드베이스를 유지하면서 다양한 실행 엔진의 장점을 활용할 수 있어 여러 코드베이스 관리의 복잡성을 줄이고 벤더 종속의 위험을 최소화합니다.

## Amazon EKS에서의 Beam

Kubernetes용 Spark Operator는 Kubernetes에서 Apache Spark의 배포 및 관리를 단순화합니다. Spark Operator를 사용하면 Apache Beam 파이프라인을 Spark 애플리케이션으로 직접 제출하고 EKS 클러스터에 배포 및 관리할 수 있으며, EKS의 강력하고 관리되는 인프라에서 자동 스케일링 및 자가 복구 기능과 같은 기능을 활용할 수 있습니다.

## 솔루션 개요

이 솔루션에서는 Python으로 작성된 Beam 파이프라인을 Spark Operator가 있는 EKS 클러스터에 배포하는 방법을 보여줍니다. Apache Beam [github 저장소](https://github.com/apache/beam/tree/master/sdks/python)의 예제 파이프라인을 사용합니다.

![BeamOnEKS](img/spark-operator-beam.png)

## Beam 파이프라인 배포

<CollapsibleContent header={<h2><span>Spark-Operator-on-EKS 솔루션 배포</span></h2>}>

이 [예제](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/spark-k8s-operator)에서는 오픈 소스 Spark Operator로 Spark 작업을 실행하는 데 필요한 다음 리소스를 프로비저닝합니다.

새 VPC에 Spark K8s Operator를 실행하는 EKS 클러스터를 배포합니다.

- 새 샘플 VPC, 2개의 프라이빗 서브넷, 2개의 퍼블릭 서브넷 및 EKS 파드용 RFC6598 공간(100.64.0.0/10)에 2개의 서브넷을 생성합니다.
- 퍼블릭 서브넷용 인터넷 게이트웨이와 프라이빗 서브넷용 NAT 게이트웨이를 생성합니다.
- 퍼블릭 엔드포인트(데모 목적으로만)가 있는 EKS 클러스터 컨트롤 플레인을 생성하고 벤치마킹 및 코어 서비스용 관리형 노드 그룹과 Spark 워크로드용 Karpenter NodePool을 생성합니다.
- Metrics 서버, Spark-operator, Apache Yunikorn, Karpenter, Grafana 및 Prometheus 서버를 배포합니다.

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

이제 설치 중에 생성된 버킷 이름을 보유하는 `S3_BUCKET` 변수를 만듭니다. 이 버킷은 이후 예제에서 출력 데이터를 저장하는 데 사용됩니다. S3_BUCKET이 설정 해제된 경우 다음 명령을 다시 실행할 수 있습니다.

```bash
export S3_BUCKET=$(terraform output -raw s3_bucket_id_spark_history_server)
echo $S3_BUCKET
```

</CollapsibleContent>

### 단계 1: Spark 및 Beam SDK가 포함된 커스텀 Docker 이미지 빌드

공식 Spark 베이스 이미지에서 Python 가상 환경과 Apache Beam SDK가 사전 설치된 커스텀 Spark 런타임 이미지를 만듭니다.

- 샘플 [Dockerfile](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/examples/beam/Dockerfile)을 검토합니다
- 환경에 맞게 Dockerfile을 커스터마이즈합니다
- Docker 이미지를 빌드하고 ECR에 푸시합니다

```sh
cd examples/beam
aws ecr create-repository --repository-name beam-spark-repo --region us-east-1
docker build . --tag ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/beam-spark-repo:eks-beam-image --platform linux/amd64,linux/arm64
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com
docker push ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/beam-spark-repo:eks-beam-image
```

Docker 이미지를 생성하고 ECR에 게시했습니다.

### 단계 2: 종속성과 함께 Beam 파이프라인 빌드 및 패키징

python 3.11이 설치된 상태에서 Python 가상 환경을 만들고 Beam 파이프라인 빌드에 필요한 종속성을 설치합니다:

```sh
python3 -m venv build-environment && \
source build-environment/bin/activate && \
python3 -m pip install --upgrade pip && \
python3 -m pip install apache_beam==2.58.0 \
    s3fs \
    boto3

```

[wordcount.py](https://raw.githubusercontent.com/apache/beam/master/sdks/python/apache_beam/examples/wordcount.py) 예제 파이프라인과 샘플 입력 파일을 다운로드합니다. wordcount Python 예제는 파일 읽기, 단어 분할, 매핑, 그룹화, 단어 카운트 합계 및 파일에 출력 작성 단계가 있는 Apache Beam 파이프라인을 보여줍니다.

```sh
curl -O https://raw.githubusercontent.com/apache/beam/master/sdks/python/apache_beam/examples/wordcount.py

curl -O https://raw.githubusercontent.com/cs109/2015/master/Lectures/Lecture15b/sparklect/shakes/kinglear.txt
```

입력 텍스트 파일을 S3 버킷에 업로드합니다.

```sh
aws s3 cp kinglear.txt s3://${S3_BUCKET}/
```

Apache Beam Python 파이프라인을 Spark에서 실행하려면 파이프라인과 모든 종속성을 단일 jar 파일로 패키징할 수 있습니다. 아래 명령을 사용하여 파이프라인을 실제로 실행하지 않고 모든 매개변수가 포함된 wordcount 파이프라인용 "fat" jar를 만듭니다:

```sh
python3 wordcount.py --output_executable_path=./wordcountApp.jar \ --runner=SparkRunner \ --environment_type=PROCESS \ --environment_config='{"command":"/opt/apache/beam/boot"}' \ --input=s3://${S3_BUCKET}/kinglear.txt \ --output=s3://${S3_BUCKET}/output.txt
```

Spark 애플리케이션에서 사용할 jar 파일을 S3 버킷에 업로드합니다.

```sh
aws s3 cp wordcountApp.jar s3://${S3_BUCKET}/app/
```
### 단계 3: SparkApplication으로 파이프라인 생성 및 실행

이 단계에서는 Apache Beam 파이프라인을 Spark 애플리케이션으로 제출하기 위한 SparkApplication 객체의 매니페스트 파일을 만듭니다. 빌드 환경에서 ACCOUNT_ID 및 S3_BUCKET 값을 대체하여 BeamApp.yaml 파일을 만드는 아래 명령을 실행합니다.

```sh
envsubst < beamapp.yaml > beamapp.yaml
```

이 명령은 beamapp.yaml 파일의 환경 변수를 교체합니다.

### 단계 4: Spark Job 실행

YAML 구성 파일을 적용하여 EKS 클러스터에 SparkApplication을 생성하고 Beam 파이프라인을 실행합니다:

```sh
kubectl apply -f beamapp.yaml
```


### 단계 5: 파이프라인 작업 모니터링 및 검토

파이프라인 작업 모니터링 및 검토
word count Beam 파이프라인은 실행하는 데 몇 분이 걸릴 수 있습니다. 상태를 모니터링하고 작업 세부 정보를 검토하는 몇 가지 방법이 있습니다.

1. Spark History Server를 사용하여 실행 중인 작업을 확인할 수 있습니다.

spark-k8s-operator 패턴을 사용하여 EKS 클러스터를 생성했으며, 이미 spark-history-server가 설치 및 구성되어 있습니다. 아래 명령을 실행하여 포트 포워딩을 시작한 다음 Preview 메뉴를 클릭하고 Preview Running Application을 선택합니다:

```sh
kubectl port-forward svc/spark-history-server 8080:80 -n spark-history-server
```

새 브라우저 창을 열고 다음 주소로 이동합니다: [http://127.0.0.1:8080/](http://127.0.0.1:8080/)

2. 약 2분 후 작업이 성공적으로 완료되면 입력 텍스트에서 찾은 단어와 각 발생 횟수가 포함된 출력 파일(output.txt-*)을 아래 명령을 실행하여 S3 버킷에서 빌드 환경으로 다운로드할 수 있습니다.

```sh
mkdir job_output &&  cd job_output
aws s3 sync s3://$S3_BUCKET/ . --include "output.txt-*" --exclude "kinglear*" --exclude app/*
```

출력은 아래와 같습니다:

```
...
particular: 3
wish: 2
Either: 3
benison: 2
Duke: 30
Contending: 1
say'st: 4
attendance: 1
...
```

<CollapsibleContent header={<h2><span>정리</span></h2>}>

:::caution
AWS 계정에 원치 않는 비용이 청구되지 않도록 이 배포 중에 생성된 모든 AWS 리소스를 삭제하세요.
:::

## ECR 저장소 삭제

```bash
aws ecr delete-repository --repository-name beam-spark-repo --region us-east-1 --force
```

## EKS 클러스터 삭제

이 스크립트는 모든 리소스가 올바른 순서로 삭제되도록 `-target` 옵션을 사용하여 환경을 정리합니다.

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator && chmod +x cleanup.sh
./cleanup.sh
```

</CollapsibleContent>
