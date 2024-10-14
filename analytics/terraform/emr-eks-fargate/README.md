# EMR on EKS with Apache YuniKorn Batch Scheduler

:::danger
**DEPRECATION NOTICE**

This blueprint will be deprecated and eventually removed from this GitHub repository on **October 27, 2024**. No bugs will be fixed, and no new features will be added. The decision to deprecate is based on the lack of demand and interest in this blueprint, as well as the difficulty in allocating resources to maintain a blueprint that is not actively used by any users or customers.

If you are using this blueprint in production, please add yourself to the [adopters.md](https://github.com/awslabs/data-on-eks/blob/main/ADOPTERS.md) page and raise an issue in the repository. This will help us reconsider and possibly retain and continue to maintain the blueprint. Otherwise, you can make a local copy or use existing tags to access it.
:::

Checkout the [documentation website](https://awslabs.github.io/data-on-eks/docs/blueprints/amazon-emr-on-eks/emr-eks-fargate) to deploy this pattern and run sample tests.

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.47 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.4 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 4.47 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_eks"></a> [eks](#module\_eks) | terraform-aws-modules/eks/aws | ~> 19.15 |
| <a name="module_eks_blueprints_addons"></a> [eks\_blueprints\_addons](#module\_eks\_blueprints\_addons) | aws-ia/eks-blueprints-addons/aws | ~> 1.2 |
| <a name="module_emr_containers"></a> [emr\_containers](#module\_emr\_containers) | terraform-aws-modules/emr/aws//modules/virtual-cluster | ~> 1.0 |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | ~> 5.0 |

## Resources

| Name | Type |
|------|------|
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_eks_cluster_auth.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_cluster_auth) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_eks_cluster_version"></a> [eks\_cluster\_version](#input\_eks\_cluster\_version) | EKS Cluster version | `string` | `"1.27"` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the VPC and EKS Cluster | `string` | `"emr-eks-fargate"` | no |
| <a name="input_private_subnets"></a> [private\_subnets](#input\_private\_subnets) | Private Subnets CIDRs. 32766 Subnet1 and 16382 Subnet2 IPs per Subnet | `list(string)` | <pre>[<br/>  "10.1.0.0/17",<br/>  "10.1.128.0/18"<br/>]</pre> | no |
| <a name="input_public_subnets"></a> [public\_subnets](#input\_public\_subnets) | Public Subnets CIDRs. 62 IPs per Subnet | `list(string)` | <pre>[<br/>  "10.1.255.128/26",<br/>  "10.1.255.192/26"<br/>]</pre> | no |
| <a name="input_region"></a> [region](#input\_region) | Region | `string` | `"us-west-2"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Default tags | `map(string)` | `{}` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | VPC CIDR | `string` | `"10.1.0.0/16"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_configure_kubectl"></a> [configure\_kubectl](#output\_configure\_kubectl) | Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig |
| <a name="output_emr_on_eks"></a> [emr\_on\_eks](#output\_emr\_on\_eks) | EMR on EKS |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
