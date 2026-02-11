---
title: EKS 기반 AWS Batch
sidebar_position: 5
---

# EKS 기반 AWS Batch
AWS Batch는 Amazon Elastic Kubernetes Service(EKS)와 같은 AWS 관리형 컨테이너 오케스트레이션 서비스 위에서 컨테이너화된 배치 워크로드(머신러닝, 시뮬레이션, 분석)를 계획, 스케줄링 및 실행할 수 있는 완전 관리형 AWS 네이티브 배치 컴퓨팅 서비스입니다.

AWS Batch는 고성능 컴퓨팅 워크로드에 필요한 운영 시맨틱스와 리소스를 추가하여 기존 EKS 클러스터에서 효율적이고 비용 효율적으로 실행할 수 있게 합니다.

구체적으로 Batch는 작업 요청을 수락하기 위한 상시 작업 큐를 제공합니다. AWS Batch 작업 정의(작업 템플릿)를 만든 다음 Batch 작업 큐에 제출합니다. 그러면 Batch는 Batch 전용 네임스페이스에서 EKS 클러스터용 노드를 프로비저닝하고 이러한 인스턴스에 파드를 배치하여 워크로드를 실행합니다.

이 예제는 다음을 포함하여 AWS Batch를 사용하여 Amazon EKS 클러스터에서 워크로드를 실행하기 위한 완전한 환경을 구축하기 위한 블루프린트를 제공합니다:
* VPC, IAM roles, 보안 그룹 등 모든 필요한 지원 인프라
* 워크로드를 위한 EKS 클러스터
* EC2 온디맨드 및 스팟 인스턴스에서 작업을 실행하기 위한 AWS Batch 리소스

블루프린트는 [여기](https://github.com/awslabs/data-on-eks/tree/main/schedulers/terraform/aws-batch-eks)에서 찾을 수 있습니다.

## 고려 사항

AWS Batch는 미디어 재포맷, ML 모델 학습, 배치 추론 또는 사용자와 상호 작용하지 않는 기타 컴퓨팅 및 데이터 집약적 작업과 같은 오프라인 분석 및 데이터 처리 작업을 위한 것입니다.

특히 Batch는 *3분 이상 걸리는 작업을 실행하도록 튜닝되어* 있습니다. 작업이 짧은 경우(1분 미만) 작업의 총 실행 시간을 늘리기 위해 단일 AWS Batch 작업 요청에 더 많은 작업을 패킹하는 것을 고려하세요.

## 사전 요구 사항

다음 도구가 로컬에 설치되어 있는지 확인하세요:

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

## 배포

**이 예제를 프로비저닝하려면:**

1. 저장소를 로컬 머신에 복제합니다.
   ```bash
   git clone https://github.com/awslabs/data-on-eks.git
   cd data-on-eks/schedulers/terraform/aws-batch
   ```
2. install 스크립트를 실행합니다.
   ```bash
   /bin/sh install.sh
   ```
   계속하려면 명령 프롬프트에서 리전을 입력합니다.

스크립트는 Terraform을 실행하여 모든 리소스를 설정합니다. 완료되면 아래와 같은 terraform output이 표시됩니다.

![terraform output](img/aws-batch/tf-apply-output.png)

다음 구성 요소가 환경에 프로비저닝됩니다:

- 2개의 프라이빗 서브넷과 2개의 퍼블릭 서브넷이 있는 샘플 VPC
- 퍼블릭 서브넷용 인터넷 게이트웨이 및 프라이빗 서브넷용 NAT Gateway
- 하나의 관리형 노드 그룹이 있는 EKS 클러스터 컨트롤 플레인
- EKS 관리형 애드온: VPC_CNI, CoreDNS, EBS_CSI_Driver, CloudWatch
- 다음을 포함하는 AWS Batch 리소스:
  - 온디맨드 컴퓨팅 환경 및 작업 큐
  - 스팟 컴퓨팅 환경 및 작업 큐
  - `echo "hello world!"`를 실행하는 예제 Batch 작업 정의

## 확인

## AWS Batch를 사용하여 EKS 클러스터에서 예제 작업 실행

다음 명령은 로컬 머신의 `kubeconfig`를 업데이트하고 `kubectl`을 사용하여 EKS 클러스터와 상호 작용하여 배포를 확인할 수 있게 합니다.

### `update-kubeconfig` 명령 실행

`terraform apply`의 `configure_kubectl_cmd` output 값에서 명령을 실행합니다. 이 값이 없으면 `terraform output` 명령을 사용하여 terraform 스택 output 값을 가져올 수 있습니다.

```bash
# 이것을 복사하지 마세요! 이것은 예제일 뿐입니다. 실행할 내용은 위를 참조하세요.
aws eks --region us-east-1 update-kubeconfig --name doeks-batch
```

### 노드 목록 조회

`kubectl`이 구성되면 이를 사용하여 클러스터 노드와 네임스페이스를 검사할 수 있습니다. 노드 정보를 가져오려면 다음 명령을 실행합니다.

```bash
kubectl get nodes
```

출력은 다음과 같아야 합니다.

```
NAME                           STATUS   ROLES    AGE    VERSION
ip-10-1-107-168.ec2.internal   Ready    <none>   3m7s   v1.30.2-eks-1552ad0
ip-10-1-141-25.ec2.internal    Ready    <none>   3m7s   v1.30.2-eks-1552ad0
```

클러스터의 생성된 네임스페이스를 가져오려면 다음 명령을 실행합니다.

```bash
kubectl get ns
```

출력은 다음과 같아야 합니다.

```
NAME                STATUS   AGE
amazon-cloudwatch   Active   2m22s
default             Active   10m
doeks-aws-batch     Active   103s
kube-node-lease     Active   10m
kube-public         Active   10m
kube-system         Active   10m
```

`doeks-aws-batch` 네임스페이스는 Batch가 노드용으로 Batch 관리 EC2 인스턴스를 추가하고 이러한 노드에서 작업을 실행하는 데 사용됩니다.

:::note
AWS Batch kubernetes 네임스페이스는 terraform의 입력 변수로 구성할 수 있습니다. `variables.tf` 파일에서 변경하기로 선택한 경우 나중에 명령을 조정하여 변경 사항을 반영해야 합니다.
:::

### "Hello World!" 작업 실행

`terraform apply`의 output에는 온디맨드 및 스팟 작업 큐 모두에서 예제 **Hello World!** 작업 정의를 실행하기 위한 AWS CLI 명령이 포함되어 있습니다. `terraform output`을 사용하여 이러한 명령을 다시 볼 수 있습니다.

**온디맨드 리소스에서 예제 작업 정의를 실행하려면:**

1. terraform output `run_example_aws_batch_job`에서 제공된 명령을 실행합니다. 다음과 같아야 합니다:
   ```bash
   JOB_ID=$(aws batch --region us-east-1  submit-job --job-definition arn:aws:batch:us-east-1:653295002771:job-definition/doeks-hello-world:2 --job-queue doeks-JQ1_OD --job-name doeks_hello_example --output text --query jobId) && echo $JOB_ID
   ## Output은 Batch 작업 ID여야 합니다
   be1f781d-753e-4d10-a7d4-1b6de68574fc
   ```
   응답은 `JOB_ID` 셸 변수를 채우며, 이후 단계에서 사용할 수 있습니다.

## 상태 확인

AWS CLI를 사용하여 AWS Batch API에서 작업 상태를 확인할 수 있습니다:

```bash
aws batch --no-cli-pager \
describe-jobs --jobs $JOB_ID --query "jobs[].[jobId,status]"
```

다음과 같은 출력이 표시됩니다:

```
[
    [
        "a13e1cff-121c-4a0b-a9c5-fab953136e20",
        "RUNNABLE"
    ]
]
```

:::tip
빈 결과가 표시되면 배포된 리전과 다른 기본 AWS 리전을 사용하고 있을 가능성이 높습니다. `AWS_DEFAULT_REGION` 셸 변수를 설정하여 기본 리전 값을 조정하세요.

```bash
export AWS_DEFAULT_REGION=us-east-1
```
:::

`kubectl`을 사용하여 Batch가 관리하는 노드와 파드의 상태를 모니터링할 수 있습니다. 먼저 노드가 시작되어 클러스터에 참여하는 것을 추적합니다:

```bash
kubectl get nodes -w
```
이것은 EKS 노드의 상태를 지속적으로 모니터링하고 주기적으로 준비 상태를 출력합니다.

```
NAME                           STATUS   ROLES    AGE   VERSION
ip-10-1-107-168.ec2.internal   Ready    <none>   12m   v1.30.2-eks-1552ad0
ip-10-1-141-25.ec2.internal    Ready    <none>   12m   v1.30.2-eks-1552ad0
ip-10-1-60-65.ec2.internal     NotReady   <none>   0s    v1.30.2-eks-1552ad0
ip-10-1-60-65.ec2.internal     NotReady   <none>   0s    v1.30.2-eks-1552ad0
ip-10-1-60-65.ec2.internal     NotReady   <none>   0s    v1.30.2-eks-1552ad0
# ... 더 많은 줄
```

새 Batch 관리 노드가 시작될 때(**NotReady** 상태의 새 노드) `Control-c` 키 조합을 눌러 watch 프로세스를 종료할 수 있습니다. 이렇게 하면 AWS Batch 네임스페이스에서 시작되는 파드의 상태를 모니터링할 수 있습니다:

```bash
kubectl get pods -n doeks-aws-batch -w
```
:::note
AWS Batch kubernetes 네임스페이스는 terraform의 입력 변수로 구성할 수 있습니다. `variables.tf` 파일에서 변경하기로 선택한 경우 이전 명령을 조정하여 변경 사항을 반영해야 합니다.
:::

이것은 Batch가 클러스터에 배치하는 파드의 상태를 지속적으로 모니터링하고 주기적으로 상태를 출력합니다.

```
NAME                                             READY   STATUS    RESTARTS   AGE
aws-batch.32d8f53f-29dc-31b4-9ce4-13504ccf74c1   0/1     Pending   0          0s
aws-batch.32d8f53f-29dc-31b4-9ce4-13504ccf74c1   0/1     ContainerCreating   0          0s
aws-batch.32d8f53f-29dc-31b4-9ce4-13504ccf74c1   1/1     Running             0          17s
aws-batch.32d8f53f-29dc-31b4-9ce4-13504ccf74c1   0/1     Completed           0          52s
aws-batch.32d8f53f-29dc-31b4-9ce4-13504ccf74c1   0/1     Completed           0          53s
aws-batch.32d8f53f-29dc-31b4-9ce4-13504ccf74c1   0/1     Terminating         0          53s
aws-batch.32d8f53f-29dc-31b4-9ce4-13504ccf74c1   0/1     Terminating         0          53s
```

파드가 **Terminating** 상태가 되면 `Control-c` 키 조합을 눌러 watch 프로세스를 종료할 수 있습니다. AWS Batch에서 작업 상태를 보려면 다음 명령을 사용합니다:

```bash
aws batch --no-cli-pager \
describe-jobs --jobs $JOB_ID --query "jobs[].[jobId,status]"
```

작업 ID와 상태가 표시되며, `SUCCEEDED`여야 합니다.

```
[
    [
        "a13e1cff-121c-4a0b-a9c5-fab953136e20",
        "SUCCEEDED"
    ]
]
```

CloudWatch Log Groups 관리 콘솔에서 애플리케이션 컨테이너 로그를 찾으려면 애플리케이션 컨테이너의 파드 이름이 필요합니다. `kubectl get pods` 출력은 해당 파드 중 어느 것이 애플리케이션 컨테이너가 있는 것인지 확인하기 좋은 방법을 제공하지 않았습니다. 또한 파드가 종료되면 Kubernetes 스케줄러는 더 이상 작업의 노드 또는 파드에 대한 정보를 제공할 수 없습니다. 다행히 AWS Batch는 작업 기록을 유지합니다!

AWS Batch의 API를 사용하여 메인 노드의 `podName` 및 기타 정보를 쿼리할 수 있습니다. MNP 작업에서 특정 노드에 대한 정보를 가져오려면 작업 ID에 `"#<NODE_INDEX>"` 패턴을 접미사로 붙입니다. 작업 정의에서 인덱스 `"0"`으로 정의한 메인 노드의 경우 다음 AWS CLI 명령으로 변환됩니다:

```bash
aws batch describe-jobs --jobs "$JOB_ID" --query "jobs[].eksAttempts[].{nodeName: nodeName, podName: podName}"
```

출력은 다음과 유사해야 합니다.

```
[
    {
        "nodeName": "ip-10-1-60-65.ec2.internal",
        "podName": "aws-batch.32d8f53f-29dc-31b4-9ce4-13504ccf74c1"
    }
]
```

**애플리케이션 컨테이너 로그를 보려면:**
1. [Amazon CloudWatch management console Log Groups 패널](https://console.aws.amazon.com/cloudwatch/home?#logsV2:log-groups$3FlogGroupNameFilter$3Ddoeks-batch)로 이동합니다.
2. **Log groups** 목록 테이블에서 클러스터의 애플리케이션 로그를 선택합니다. 클러스터 이름과 `application` 접미사로 식별됩니다.
   ![CloudWatch management console, showing the location of the application logs.](img/aws-batch/cw-logs-1.png)
3. **Log streams** 목록 테이블에서 이전 단계의 `podName` 값을 입력합니다. 이렇게 하면 파드의 두 컨테이너에 대한 두 개의 로그가 강조 표시됩니다. `application` 컨테이너에 대한 로그 스트림을 선택합니다.
   ![CloudWatch log stream panel showing the filtered set using the pod name.](img/aws-batch/cw-logs-2.png)
4. **Log events** 섹션의 필터 바에서 **Display**를 선택한 다음 **View in plain text**를 선택합니다. 로그 이벤트의 `"log"` 속성에서 "Hello World!" 로그 메시지가 표시됩니다.

## 정리

환경을 정리하고 클러스터에서 모든 AWS Batch 리소스와 kubernetes 구성을 제거하려면 `cleanup.sh` 스크립트를 실행합니다.

```bash
chmod +x cleanup.sh
./cleanup.sh
```

CloudWatch 로그에서 데이터 요금이 발생하지 않도록 클러스터의 로그 그룹도 삭제해야 합니다. [CloudWatch management console의 **Log groups** 페이지](https://console.aws.amazon.com/cloudwatch/home?#logsV2:log-groups$3FlogGroupNameFilter$3Ddoeks-batch)로 이동하여 찾을 수 있습니다.
