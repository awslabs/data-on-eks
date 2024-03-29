## Requirements

 For security reasons, ALB is deployed as internal one and it can be changed to internet-facing during the deployment, if needed.
## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.36.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | 2.12.1 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | 2.25.2 |
| <a name="provider_null"></a> [null](#provider\_null) | 3.2.2 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_ebs_csi_driver_irsa"></a> [ebs\_csi\_driver\_irsa](#module\_ebs\_csi\_driver\_irsa) | terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks | ~> 5.20 |
| <a name="module_eks"></a> [eks](#module\_eks) | terraform-aws-modules/eks/aws | ~> 19.15 |
| <a name="module_eks_blueprints_addons"></a> [eks\_blueprints\_addons](#module\_eks\_blueprints\_addons) | aws-ia/eks-blueprints-addons/aws | ~> 1.2 |
| <a name="module_lb_role"></a> [lb\_role](#module\_lb\_role) | terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks | 5.37.1 |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | ~> 5.0 |

## Resources

| Name | Type |
|------|------|
| [helm_release.alb_controller](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.superset](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_ingress_class_v1.aws_alb](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/ingress_class_v1) | resource |
| [kubernetes_ingress_v1.superset](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/ingress_v1) | resource |
| [kubernetes_namespace.superset](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [kubernetes_service_account.service_account](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_account) | resource |
| [null_resource.add_superset_repo](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.helm_update_repos](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_eks_cluster_version"></a> [eks\_cluster\_version](#input\_eks\_cluster\_version) | EKS Cluster version | `string` | `"1.28"` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the VPC and EKS Cluster | `string` | `"superset-on-eks"` | no |
| <a name="input_region"></a> [region](#input\_region) | Region | `string` | `"us-east-1"` | no |
| <a name="input_secondary_cidr_blocks"></a> [secondary\_cidr\_blocks](#input\_secondary\_cidr\_blocks) | Secondary CIDR blocks to be attached to VPC | `list(string)` | <pre>[<br>  "100.64.0.0/16"<br>]</pre> | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | VPC CIDR. This should be a valid private (RFC 1918) CIDR range | `string` | `"10.1.0.0/21"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_configure_kubectl"></a> [configure\_kubectl](#output\_configure\_kubectl) | Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig |
| <a name="output_superset_url"></a> [superset\_url](#output\_superset\_url) | Configure kubectl: Once the kubeconfig is configured as above, use the below command to get the Superset URL |
