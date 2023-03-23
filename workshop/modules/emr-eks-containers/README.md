<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.13 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_emr_on_eks"></a> [emr\_on\_eks](#module\_emr\_on\_eks) | ./emr-on-eks | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_eks_cluster_id"></a> [eks\_cluster\_id](#input\_eks\_cluster\_id) | Name of the EKS Cluster | `string` | n/a | yes |
| <a name="input_eks_oidc_provider_arn"></a> [eks\_oidc\_provider\_arn](#input\_eks\_oidc\_provider\_arn) | The OpenID Connect identity provider ARN | `string` | n/a | yes |
| <a name="input_emr_on_eks_config"></a> [emr\_on\_eks\_config](#input\_emr\_on\_eks\_config) | EMR on EKS Helm configuration values | `any` | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all AWS resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_emr_on_eks"></a> [emr\_on\_eks](#output\_emr\_on\_eks) | EMR on EKS |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
