# 故障排除

您将找到 Data on Amazon EKS(DoEKS) 安装问题的故障排除信息

## 错误：local-exec 配置器错误

如果您在执行 local-exec 配置器期间遇到以下错误：

```sh
Error: local-exec provisioner error \
with module.eks-blueprints.module.emr_on_eks["data_team_b"].null_resource.update_trust_policy,\
 on .terraform/modules/eks-blueprints/modules/emr-on-eks/main.tf line 105, in resource "null_resource" \
 "update_trust_policy":│ 105: provisioner "local-exec" {│ │ Error running command 'set -e│ │ aws emr-containers update-role-trust-policy \
 │ --cluster-name emr-on-eks \│ --namespace emr-data-team-b \│ --role-name emr-on-eks-emr-eks-data-team-b
```

### 问题描述：
错误消息表明正在使用的 AWS CLI 版本中不存在 emr-containers 命令。此问题已在 AWS CLI 版本 2.0.54 中得到解决和修复。

### 解决方案
要解决此问题，请通过执行以下命令将您的 AWS CLI 版本更新到 2.0.54 或更高版本：

```sh
pip install --upgrade awscliv2
```

通过更新 AWS CLI 版本，您将确保必要的 emr-containers 命令可用，并且可以在配置过程中成功执行。

如果您继续遇到任何问题或需要进一步帮助，请查阅 [AWS CLI GitHub 问题](https://github.com/aws/aws-cli/issues/6162) 了解更多详细信息，或联系我们的支持团队获取额外指导。

## Terraform Destroy 期间的超时

### 问题描述：
客户在删除环境时可能会遇到超时，特别是在删除 VPC 时。这是与 vpc-cni 组件相关的已知问题。

### 症状：

即使在环境被销毁后，ENI（弹性网络接口）仍然附加到子网。
与 ENI 关联的 EKS 托管安全组无法被 EKS 删除。

### 解决方案：
要解决此问题，请按照以下推荐解决方案：

利用提供的 `cleanup.sh` 脚本确保资源的正确清理。运行蓝图中包含的 `cleanup.sh` 脚本。
此脚本将处理任何残留 ENI 和关联安全组的删除。

## 错误：无法下载图表
如果您在尝试下载图表时遇到以下错误：

```sh
│ Error: could not download chart: failed to download "oci://public.ecr.aws/karpenter/karpenter" at version "v0.18.1"
│
│   with module.eks_blueprints_kubernetes_addons.module.karpenter[0].module.helm_addon.helm_release.addon[0],
│   on .terraform/modules/eks_blueprints_kubernetes_addons/modules/kubernetes-addons/helm-addon/main.tf line 1, in resource "helm_release" "addon":
│    1: resource "helm_release" "addon" {
│
```

按照以下步骤解决问题：

### 问题描述：
错误消息表明下载指定图表失败。此问题可能由于 Terraform 在安装 Karpenter 期间的错误而发生。

### 解决方案：
要解决此问题，您可以尝试以下步骤：

使用 ECR 进行身份验证：运行以下命令以使用图表所在的 ECR（弹性容器注册表）进行身份验证：

```sh
aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws
```
重新运行 terraform apply：使用 --auto-approve 标志再次执行 terraform apply 命令以重新应用 Terraform 配置：
```sh
terraform apply --auto-approve
```

通过使用 ECR 进行身份验证并重新运行 terraform apply 命令，您将确保在安装过程中可以成功下载必要的图表。

## Terraform apply/destroy 错误，无法与 EKS 集群进行身份验证
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

**解决方案：**
在这种情况下，Terraform 无法刷新数据资源并与 EKS 集群进行身份验证。
请参阅[此处](https://github.com/terraform-aws-modules/terraform-aws-eks/issues/1234)的讨论

首先尝试使用 exec 插件的方法。

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

如果在上述更改后问题仍然存在，那么您可以使用本地 kube config 文件的替代方法。
注意：此方法可能不适合生产环境。它帮助您使用本地 kube config 应用/销毁集群。

1. 为您的集群创建本地 kubeconfig

```bash
aws eks update-kubeconfig --name <EKS_CLUSTER_NAME> --region <CLUSTER_REGION>
```

2. 使用以下配置更新 `providers.tf` 文件，仅使用 config_path。

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

## EMR Containers 虚拟集群 (dhwtlq9yx34duzq5q3akjac00) 删除：意外状态 'ARRESTED'

如果您遇到错误消息"waiting for EMR Containers Virtual Cluster (xwbc22787q6g1wscfawttzzgb) delete: unexpected state 'ARRESTED', wanted target ''. last error: %!s(nil)"，您可以按照以下步骤解决问题：

注意：将 `<REGION>` 替换为虚拟集群所在的适当 AWS 区域。

1. 打开终端或命令提示符。
2. 运行以下命令列出处于"ARRESTED"状态的虚拟集群：

```sh
aws emr-containers list-virtual-clusters --region <REGION> --states ARRESTED \
--query 'virtualClusters[0].id' --output text
```
此命令检索处于"ARRESTED"状态的虚拟集群的 ID。

3. 运行以下命令删除虚拟集群：

```sh
aws emr-containers list-virtual-clusters --region <REGION> --states ARRESTED \
--query 'virtualClusters[0].id' --output text | xargs -I{} aws emr-containers delete-virtual-cluster \
--region <REGION> --id {}
```
将 `<VIRTUAL_CLUSTER_ID>` 替换为从上一步获得的虚拟集群 ID。

通过执行这些命令，您将能够删除处于"ARRESTED"状态的虚拟集群。这应该解决意外状态问题并允许您继续进行进一步的操作。

## 终止命名空间问题

如果您遇到命名空间卡在"Terminating"状态且无法删除的问题，您可以使用以下命令删除命名空间上的终结器：

注意：将 `<namespace>` 替换为您要删除的命名空间的名称。

```sh
NAMESPACE=<namespace>
kubectl get namespace $NAMESPACE -o json | sed 's/"kubernetes"//' | kubectl replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" -f -
```

此命令以 JSON 格式检索命名空间详细信息，删除"kubernetes"终结器，并执行替换操作以从命名空间中删除终结器。这应该允许命名空间完成终止过程并成功删除。

请确保您具有执行此操作的必要权限。如果您继续遇到问题或需要进一步帮助，请联系我们的支持团队获取额外的指导和故障排除步骤。

## KMS 别名 AlreadyExistsException

在您的 Terraform 安装或重新部署期间，您可能会遇到错误："AlreadyExistsException: An alias with the name ... already exists"。当您尝试创建的 KMS 别名在您的 AWS 账户中已经存在时会发生这种情况。

```
│ Error: creating KMS Alias (alias/eks/trainium-inferentia): AlreadyExistsException: An alias with the name arn:aws:kms:us-west-2:23423434:alias/eks/trainium-inferentia already exists
│
│   with module.eks.module.kms.aws_kms_alias.this["cluster"],
│   on .terraform/modules/eks.kms/main.tf line 452, in resource "aws_kms_alias" "this":
│  452: resource "aws_kms_alias" "this" {
│
```

**解决方案：**

要解决此问题，请使用 aws kms delete-alias 命令删除现有的 KMS 别名。记住在运行命令之前更新别名名称和区域。

```sh
aws kms delete-alias --alias-name <KMS_ALIAS_NAME> --region <ENTER_REGION>
```

## 错误：创建 CloudWatch Logs 日志组

Terraform 无法创建 CloudWatch Logs 日志组，因为它在您的 AWS 账户中已经存在。

```
╷
│ Error: creating CloudWatch Logs Log Group (/aws/eks/trainium-inferentia/cluster): operation error CloudWatch Logs: CreateLogGroup, https response error StatusCode: 400, RequestID: 5c34c47a-72c6-44b2-a345-925824f24d38, ResourceAlreadyExistsException: The specified log group already exists
│
│   with module.eks.aws_cloudwatch_log_group.this[0],
│   on .terraform/modules/eks/main.tf line 106, in resource "aws_cloudwatch_log_group" "this":
│  106: resource "aws_cloudwatch_log_group" "this" {

```

**解决方案：**

通过更新日志组名称和区域来删除现有日志组。

```sh
aws logs delete-log-group --log-group-name <LOG_GROUP_NAME> --region <ENTER_REGION>
```

## Karpenter 错误 - 缺少服务链接角色

Karpenter 在尝试创建新实例时抛出以下错误。

```
"error":"launching nodeclaim, creating instance, with fleet error(s), AuthFailure.ServiceLinkedRoleCreationNotPermitted: The provided credentials do not have permission to create the service-linked role for EC2 Spot Instances."}
```

**解决方案：**

您需要在使用的 AWS 账户中创建服务链接角色以避免 `ServiceLinkedRoleCreationNotPermitted` 错误。

```sh
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com
```

## 错误：AmazonEKS_CNI_IPv6_Policy 不存在
如果您在部署支持 IPv6 的解决方案时遇到以下错误：

```sh
│ Error: attaching IAM Policy (arn:aws:iam::1234567890:policy/AmazonEKS_CNI_IPv6_Policy) to IAM Role (core-node-group-eks-node-group-20241111182906854800000003): operation error IAM: AttachRolePolicy, https response error StatusCode: 404, RequestID: 9c99395a-ce3d-4a05-b119-538470a3a9f7, NoSuchEntity: Policy arn:aws:iam::1234567890:policy/AmazonEKS_CNI_IPv6_Policy does not exist or is not attachable.
```

### 问题描述：
Amazon VPC CNI 插件需要 IAM 权限来分配 IPv6 地址，因此您必须创建 IAM 策略并将其与 CNI 将使用的角色关联。但是，每个 IAM 策略名称在同一 AWS 账户中必须是唯一的。如果策略作为 terraform 堆栈的一部分创建并多次部署，这会导致冲突。

要解决此错误，您需要使用以下命令创建策略。您应该只需要为每个 AWS 账户执行一次此操作。

### 解决方案：

1. 复制以下文本并将其保存到名为 vpc-cni-ipv6-policy.json 的文件中。

```sh
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AssignIpv6Addresses",
                "ec2:DescribeInstances",
                "ec2:DescribeTags",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeInstanceTypes"
            ],
            "Resource": ""
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags"
            ],
            "Resource": [
                "arn:aws:ec2::*:network-interface/*"
            ]
        }
    ]
}
```

2. 创建 IAM 策略。

```sh
aws iam create-policy --policy-name AmazonEKS_CNI_IPv6_Policy --policy-document file://vpc-cni-ipv6-policy.json
```

3. 重新运行蓝图的 `install.sh` 脚本
