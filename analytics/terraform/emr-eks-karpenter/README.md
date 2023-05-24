# Scaling EMR on EKS Spark Jobs with Karpenter Autoscaler
Checkout the [documentation website](https://awslabs.github.io/data-on-eks/docs/amazon-emr-on-eks/emr-eks-karpenter) to deploy this pattern and run sample tests.

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 3.72 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.4.1 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | >= 1.14 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10 |
| <a name="requirement_null"></a> [null](#requirement\_null) | >= 3.0 |
| <a name="requirement_time"></a> [time](#requirement\_time) | >= 0.7 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 3.72 |
| <a name="provider_aws.ecr"></a> [aws.ecr](#provider\_aws.ecr) | >= 3.72 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 2.4.1 |
| <a name="provider_kubectl"></a> [kubectl](#provider\_kubectl) | >= 1.14 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_ebs_csi_driver_irsa"></a> [ebs\_csi\_driver\_irsa](#module\_ebs\_csi\_driver\_irsa) | terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks | ~> 5.14 |
| <a name="module_eks"></a> [eks](#module\_eks) | terraform-aws-modules/eks/aws | ~> 19.9 |
| <a name="module_eks_blueprints_kubernetes_addons"></a> [eks\_blueprints\_kubernetes\_addons](#module\_eks\_blueprints\_kubernetes\_addons) | github.com/aws-ia/terraform-aws-eks-blueprints-addons | 08650fd2b4bc894bde7b51313a8dc9598d82e925 |
| <a name="module_emr_containers"></a> [emr\_containers](#module\_emr\_containers) | ../../../workshop/modules/emr-eks-containers | n/a |
| <a name="module_karpenter"></a> [karpenter](#module\_karpenter) | terraform-aws-modules/eks/aws//modules/karpenter | ~> 19.9 |
| <a name="module_s3_bucket"></a> [s3\_bucket](#module\_s3\_bucket) | terraform-aws-modules/s3-bucket/aws | v3.3.0 |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | ~> 3.0 |
| <a name="module_vpc_cni_irsa"></a> [vpc\_cni\_irsa](#module\_vpc\_cni\_irsa) | terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks | ~> 5.14 |
| <a name="module_vpc_endpoints"></a> [vpc\_endpoints](#module\_vpc\_endpoints) | terraform-aws-modules/vpc/aws//modules/vpc-endpoints | ~> 3.0 |
| <a name="module_vpc_endpoints_sg"></a> [vpc\_endpoints\_sg](#module\_vpc\_endpoints\_sg) | terraform-aws-modules/security-group/aws | ~> 4.0 |

## Resources

| Name | Type |
|------|------|
| [aws_fsx_data_repository_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/fsx_data_repository_association) | resource |
| [aws_fsx_lustre_file_system.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/fsx_lustre_file_system) | resource |
| [aws_prometheus_workspace.amp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/prometheus_workspace) | resource |
| [aws_security_group.fsx](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [helm_release.kubecost](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.yunikorn](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubectl_manifest.karpenter_provisioner](https://registry.terraform.io/providers/gavinbunney/kubectl/latest/docs/resources/manifest) | resource |
| [kubectl_manifest.static_pv](https://registry.terraform.io/providers/gavinbunney/kubectl/latest/docs/resources/manifest) | resource |
| [kubectl_manifest.storage_class](https://registry.terraform.io/providers/gavinbunney/kubectl/latest/docs/resources/manifest) | resource |
| [aws_ami.eks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_ecrpublic_authorization_token.token](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ecrpublic_authorization_token) | data source |
| [aws_eks_cluster_auth.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_cluster_auth) | data source |
| [kubectl_path_documents.karpenter_provisioners](https://registry.terraform.io/providers/gavinbunney/kubectl/latest/docs/data-sources/path_documents) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_eks_cluster_version"></a> [eks\_cluster\_version](#input\_eks\_cluster\_version) | EKS Cluster version | `string` | `"1.24"` | no |
| <a name="input_enable_aws_for_fluentbit"></a> [enable\_aws\_for\_fluentbit](#input\_enable\_aws\_for\_fluentbit) | Enable Fluentbit addon | `bool` | `true` | no |
| <a name="input_enable_cloudwatch_metrics"></a> [enable\_cloudwatch\_metrics](#input\_enable\_cloudwatch\_metrics) | Enable Cloudwatch metrics | `bool` | `true` | no |
| <a name="input_enable_fsx_for_lustre"></a> [enable\_fsx\_for\_lustre](#input\_enable\_fsx\_for\_lustre) | Deploys fsx for lustre addon, storage class and static FSx for Lustre filesystem for EMR | `bool` | `false` | no |
| <a name="input_enable_vpc_endpoints"></a> [enable\_vpc\_endpoints](#input\_enable\_vpc\_endpoints) | Enable VPC Endpoints | `string` | `false` | no |
| <a name="input_enable_yunikorn"></a> [enable\_yunikorn](#input\_enable\_yunikorn) | Enable Apache YuniKorn Scheduler | `bool` | `false` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the VPC and EKS Cluster | `string` | `"emr-eks-karpenter"` | no |
| <a name="input_private_subnets"></a> [private\_subnets](#input\_private\_subnets) | Private Subnets CIDRs. 32766 Subnet1 and 16382 Subnet2 IPs per Subnet | `list(string)` | <pre>[<br>  "10.1.0.0/17",<br>  "10.1.128.0/18"<br>]</pre> | no |
| <a name="input_public_subnets"></a> [public\_subnets](#input\_public\_subnets) | Public Subnets CIDRs. 62 IPs per Subnet | `list(string)` | <pre>[<br>  "10.1.255.128/26",<br>  "10.1.255.192/26"<br>]</pre> | no |
| <a name="input_region"></a> [region](#input\_region) | Region | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Default tags | `map(string)` | `{}` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | VPC CIDR | `string` | `"10.1.0.0/16"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_amp_workspace_id"></a> [amp\_workspace\_id](#output\_amp\_workspace\_id) | The id of amp |
| <a name="output_aws_auth_configmap_yaml"></a> [aws\_auth\_configmap\_yaml](#output\_aws\_auth\_configmap\_yaml) | Formatted yaml output for base aws-auth configmap containing roles used in cluster node groups/fargate profiles |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | The Amazon Resource Name (ARN) of the cluster |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | The Amazon Resource Name (ARN) of the cluster |
| <a name="output_configure_kubectl"></a> [configure\_kubectl](#output\_configure\_kubectl) | Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig |
| <a name="output_eks_managed_node_groups"></a> [eks\_managed\_node\_groups](#output\_eks\_managed\_node\_groups) | Map of attribute maps for all EKS managed node groups created |
| <a name="output_eks_managed_node_groups_iam_role_name"></a> [eks\_managed\_node\_groups\_iam\_role\_name](#output\_eks\_managed\_node\_groups\_iam\_role\_name) | List of the autoscaling group names created by EKS managed node groups |
| <a name="output_emr_on_eks"></a> [emr\_on\_eks](#output\_emr\_on\_eks) | EMR on EKS |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | The ARN of the OIDC Provider if `enable_irsa = true` |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
