# 문제 해결

Data on Amazon EKS(DoEKS) 설치 문제에 대한 문제 해결 정보를 찾을 수 있습니다.

## Error: local-exec provisioner error

local-exec provisioner 실행 중 다음 오류가 발생한 경우:

```sh
Error: local-exec provisioner error \
with module.eks-blueprints.module.emr_on_eks["data_team_b"].null_resource.update_trust_policy,\
 on .terraform/modules/eks-blueprints/modules/emr-on-eks/main.tf line 105, in resource "null_resource" \
 "update_trust_policy":│ 105: provisioner "local-exec" {│ │ Error running command 'set -e│ │ aws emr-containers update-role-trust-policy \
 │ --cluster-name emr-on-eks \│ --namespace emr-data-team-b \│ --role-name emr-on-eks-emr-eks-data-team-b
```
### 문제 설명:
오류 메시지는 사용 중인 AWS CLI 버전에 emr-containers 명령이 없음을 나타냅니다. 이 문제는 AWS CLI 버전 2.0.54에서 해결되었습니다.

### 해결 방법
문제를 해결하려면 다음 명령을 실행하여 AWS CLI 버전을 2.0.54 이상으로 업데이트하세요:

```sh
pip install --upgrade awscliv2
```

AWS CLI 버전을 업데이트하면 프로비저닝 프로세스 중에 필요한 emr-containers 명령을 사용하고 성공적으로 실행할 수 있습니다.

계속 문제가 발생하거나 추가 지원이 필요한 경우 자세한 내용은 [AWS CLI GitHub 이슈](https://github.com/aws/aws-cli/issues/6162)를 참조하거나 추가 안내를 위해 지원팀에 문의하세요.

## Terraform Destroy 중 타임아웃

### 문제 설명:
고객은 환경 삭제 중, 특히 VPC가 삭제될 때 타임아웃을 경험할 수 있습니다. 이것은 vpc-cni 컴포넌트와 관련된 알려진 문제입니다.

### 증상:

환경이 삭제된 후에도 ENI(Elastic Network Interfaces)가 서브넷에 연결된 상태로 남아 있습니다.
ENI와 연결된 EKS 관리 보안 그룹을 EKS에서 삭제할 수 없습니다.
### 해결 방법:
이 문제를 해결하려면 아래 권장 해결 방법을 따르세요:

리소스의 적절한 정리를 보장하기 위해 제공된 `cleanup.sh` 스크립트를 활용하세요. 블루프린트에 포함된 `cleanup.sh` 스크립트를 실행하세요.
이 스크립트는 남아 있는 ENI 및 관련 보안 그룹의 제거를 처리합니다.


## Error: could not download chart
차트 다운로드를 시도하는 동안 다음 오류가 발생한 경우:

```sh
│ Error: could not download chart: failed to download "oci://public.ecr.aws/karpenter/karpenter" at version "v0.18.1"
│
│   with module.eks_blueprints_kubernetes_addons.module.karpenter[0].module.helm_addon.helm_release.addon[0],
│   on .terraform/modules/eks_blueprints_kubernetes_addons/modules/kubernetes-addons/helm-addon/main.tf line 1, in resource "helm_release" "addon":
│    1: resource "helm_release" "addon" {
│
```

문제를 해결하려면 아래 단계를 따르세요:

### 문제 설명:
오류 메시지는 지정된 차트 다운로드에 실패했음을 나타냅니다. 이 문제는 Karpenter 설치 중 Terraform의 버그로 인해 발생할 수 있습니다.

### 해결 방법:
문제를 해결하려면 다음 단계를 시도해 보세요:

ECR 인증: 다음 명령을 실행하여 차트가 위치한 ECR(Elastic Container Registry)에 인증합니다:

```sh
aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws
```
terraform apply 재실행: --auto-approve 플래그와 함께 terraform apply 명령을 다시 실행하여 Terraform 구성을 다시 적용합니다:
```sh
terraform apply --auto-approve
```

ECR에 인증하고 terraform apply 명령을 다시 실행하면 설치 프로세스 중에 필요한 차트를 성공적으로 다운로드할 수 있습니다.

## EKS 클러스터 인증을 위한 Terraform apply/destroy 오류
```
ERROR:
╷
│ Error: Get "http://localhost/api/v1/namespaces/kube-system/configmaps/aws-auth": dial tcp [::1]:80: connect: connection refused
│
│   with module.eks.kubernetes_config_map_v1_data.aws_auth[0],
│   on .terraform/modules/eks/main.tf line 550, in resource "kubernetes_config_map_v1_data" "aws_auth":
│  550: resource "kubernetes_config_map_v1_data" "aws_auth" {
│
╵
```

**해결 방법:**
이 상황에서 Terraform은 데이터 리소스를 새로 고치고 EKS 클러스터에 인증할 수 없습니다.
[여기](https://github.com/terraform-aws-modules/terraform-aws-eks/issues/1234)에서 토론을 참조하세요.

먼저 exec 플러그인을 사용하여 이 접근 방식을 시도해 보세요.

```terraform
provider "kubernetes" {
  host                   = module.eks_blueprints.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = ["eks", "get-token", "--cluster-name", module.eks_blueprints.eks_cluster_id]
  }
}


```

위 변경 후에도 문제가 지속되면 로컬 kube config 파일을 사용하는 대안적인 접근 방식을 사용할 수 있습니다.
참고: 이 접근 방식은 프로덕션에 이상적이지 않을 수 있습니다. 로컬 kube config로 클러스터를 apply/destroy하는 데 도움이 됩니다.

1. 클러스터용 로컬 kubeconfig 생성

```bash
aws eks update-kubeconfig --name <EKS_CLUSTER_NAME> --region <CLUSTER_REGION>
```

2. config_path만 사용하여 아래 구성으로 `providers.tf` 파일을 업데이트합니다.

```terraform
provider "kubernetes" {
    config_path = "<HOME_PATH>/.kube/config"
}

provider "helm" {
    kubernetes {
        config_path = "<HOME_PATH>/.kube/config"
    }
}

provider "kubectl" {
    config_path = "<HOME_PATH>/.kube/config"
}
```

## EMR Containers Virtual Cluster (dhwtlq9yx34duzq5q3akjac00) delete: unexpected state 'ARRESTED'

"waiting for EMR Containers Virtual Cluster (xwbc22787q6g1wscfawttzzgb) delete: unexpected state 'ARRESTED', wanted target ''. last error: %!s(nil)"라는 오류 메시지가 발생하면 아래 단계를 따라 문제를 해결할 수 있습니다:

참고: `<REGION>`을 가상 클러스터가 위치한 적절한 AWS 리전으로 대체하세요.

1. 터미널 또는 명령 프롬프트를 엽니다.
2. 다음 명령을 실행하여 "ARRESTED" 상태의 가상 클러스터를 나열합니다:

```sh
aws emr-containers list-virtual-clusters --region <REGION> --states ARRESTED \
--query 'virtualClusters[0].id' --output text
```
이 명령은 "ARRESTED" 상태의 가상 클러스터 ID를 검색합니다.

3. 다음 명령을 실행하여 가상 클러스터를 삭제합니다:

```sh
aws emr-containers list-virtual-clusters --region <REGION> --states ARRESTED \
--query 'virtualClusters[0].id' --output text | xargs -I{} aws emr-containers delete-virtual-cluster \
--region <REGION> --id {}
```
`<VIRTUAL_CLUSTER_ID>`를 이전 단계에서 얻은 가상 클러스터 ID로 대체합니다.

이러한 명령을 실행하면 "ARRESTED" 상태의 가상 클러스터를 삭제할 수 있습니다. 이렇게 하면 예기치 않은 상태 문제가 해결되고 추가 작업을 진행할 수 있습니다.

## 네임스페이스 종료 문제

네임스페이스가 "Terminating" 상태에서 멈추고 삭제할 수 없는 문제가 발생하면 다음 명령을 사용하여 네임스페이스의 finalizers를 제거할 수 있습니다:

참고: `<namespace>`를 삭제하려는 네임스페이스 이름으로 대체하세요.

```sh
NAMESPACE=<namespace>
kubectl get namespace $NAMESPACE -o json | sed 's/"kubernetes"//' | kubectl replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" -f -
```

이 명령은 JSON 형식으로 네임스페이스 세부 정보를 검색하고 "kubernetes" finalizer를 제거한 다음 네임스페이스에서 finalizer를 제거하기 위한 replace 작업을 수행합니다. 이렇게 하면 네임스페이스가 종료 프로세스를 완료하고 성공적으로 삭제될 수 있습니다.

이 작업을 수행하는 데 필요한 권한이 있는지 확인하세요. 계속 문제가 발생하거나 추가 지원이 필요한 경우 추가 안내 및 문제 해결 단계를 위해 지원팀에 문의하세요.

## KMS Alias AlreadyExistsException

Terraform 설치 또는 재배포 중에 `AlreadyExistsException: An alias with the name ...` already exists라는 오류가 발생할 수 있습니다. 이는 생성하려는 KMS 별칭이 이미 AWS 계정에 존재할 때 발생합니다.

```
│ Error: creating KMS Alias (alias/eks/trainium-inferentia): AlreadyExistsException: An alias with the name arn:aws:kms:us-west-2:23423434:alias/eks/trainium-inferentia already exists
│
│   with module.eks.module.kms.aws_kms_alias.this["cluster"],
│   on .terraform/modules/eks.kms/main.tf line 452, in resource "aws_kms_alias" "this":
│  452: resource "aws_kms_alias" "this" {
│
```

**해결 방법:**

이 문제를 해결하려면 aws kms delete-alias 명령을 사용하여 기존 KMS 별칭을 삭제하세요. 명령을 실행하기 전에 별칭 이름과 리전을 업데이트하세요.


```sh
aws kms delete-alias --alias-name <KMS_ALIAS_NAME> --region <ENTER_REGION>
```

## Error: creating CloudWatch Logs Log Group

AWS 계정에 이미 존재하기 때문에 Terraform이 CloudWatch Logs 로그 그룹을 생성할 수 없습니다.

```
╷
│ Error: creating CloudWatch Logs Log Group (/aws/eks/trainium-inferentia/cluster): operation error CloudWatch Logs: CreateLogGroup, https response error StatusCode: 400, RequestID: 5c34c47a-72c6-44b2-a345-925824f24d38, ResourceAlreadyExistsException: The specified log group already exists
│
│   with module.eks.aws_cloudwatch_log_group.this[0],
│   on .terraform/modules/eks/main.tf line 106, in resource "aws_cloudwatch_log_group" "this":
│  106: resource "aws_cloudwatch_log_group" "this" {

```

**해결 방법:**

로그 그룹 이름과 리전을 업데이트하여 기존 로그 그룹을 삭제합니다.

```sh
aws logs delete-log-group --log-group-name <LOG_GROUP_NAME> --region <ENTER_REGION>
```

## Karpenter Error - Missing Service Linked Role

Karpenter가 새 인스턴스를 생성하려고 할 때 아래 오류를 발생시킵니다.

```
"error":"launching nodeclaim, creating instance, with fleet error(s), AuthFailure.ServiceLinkedRoleCreationNotPermitted: The provided credentials do not have permission to create the service-linked role for EC2 Spot Instances."}
```

**해결 방법:**

`ServiceLinkedRoleCreationNotPermitted` 오류를 피하기 위해 사용 중인 AWS 계정에 service linked role을 생성해야 합니다.

```sh
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com
```
