# AWS Batch on EKS

Checkout the [documentation website](https://awslabs.github.io/data-on-eks/docs/blueprints/job-schedulers/aws-batch) to deploy this pattern and run sample tests.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.2 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.95 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 2.17 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.95 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.10 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_cloudwatch_irsa_role"></a> [cloudwatch\_irsa\_role](#module\_cloudwatch\_irsa\_role) | terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks | >= 5.44 |
| <a name="module_ebs_csi_irsa_role"></a> [ebs\_csi\_irsa\_role](#module\_ebs\_csi\_irsa\_role) | terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks | >= 5.44 |
| <a name="module_eks"></a> [eks](#module\_eks) | terraform-aws-modules/eks/aws | ~> 20.0 |
| <a name="module_eks_auth"></a> [eks\_auth](#module\_eks\_auth) | terraform-aws-modules/eks/aws//modules/aws-auth | ~> 20.0 |
| <a name="module_eks_blueprints_addons"></a> [eks\_blueprints\_addons](#module\_eks\_blueprints\_addons) | aws-ia/eks-blueprints-addons/aws | ~> 1.2 |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | ~> 5.0 |

## Resources

| Name | Type |
|------|------|
| [aws_batch_compute_environment.doeks_ondemand_ce](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/batch_compute_environment) | resource |
| [aws_batch_compute_environment.doeks_spot_ce](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/batch_compute_environment) | resource |
| [aws_batch_job_definition.doeks_hello_world](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/batch_job_definition) | resource |
| [aws_batch_job_queue.doeks_ondemand_jq](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/batch_job_queue) | resource |
| [aws_batch_job_queue.doeks_spot_jq](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/batch_job_queue) | resource |
| [aws_iam_instance_profile.batch_eks_instance_profile](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.batch_eks_instance_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [kubernetes_cluster_role.batch_cluster_role](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/cluster_role) | resource |
| [kubernetes_cluster_role_binding.batch_cluster_role_binding](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/cluster_role_binding) | resource |
| [kubernetes_namespace.doeks_batch_namespace](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [kubernetes_role.batch_compute_env_role](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/role) | resource |
| [kubernetes_role_binding.batch_compute_env_role_binding](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/role_binding) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.ec2_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_batch_doeks_ce_name"></a> [aws\_batch\_doeks\_ce\_name](#input\_aws\_batch\_doeks\_ce\_name) | The AWS Batch EKS namespace | `string` | `"doeks-CE1"` | no |
| <a name="input_aws_batch_doeks_jd_name"></a> [aws\_batch\_doeks\_jd\_name](#input\_aws\_batch\_doeks\_jd\_name) | The AWS Batch example job definition name | `string` | `"doeks-hello-world"` | no |
| <a name="input_aws_batch_doeks_jq_name"></a> [aws\_batch\_doeks\_jq\_name](#input\_aws\_batch\_doeks\_jq\_name) | The AWS Batch EKS namespace | `string` | `"doeks-JQ1"` | no |
| <a name="input_aws_batch_doeks_namespace"></a> [aws\_batch\_doeks\_namespace](#input\_aws\_batch\_doeks\_namespace) | The AWS Batch EKS namespace | `string` | `"doeks-aws-batch"` | no |
| <a name="input_aws_batch_instance_types"></a> [aws\_batch\_instance\_types](#input\_aws\_batch\_instance\_types) | The set of instance types to launch for AWS Batch jobs. | `list(string)` | <pre>[<br/>  "optimal"<br/>]</pre> | no |
| <a name="input_aws_batch_max_vcpus"></a> [aws\_batch\_max\_vcpus](#input\_aws\_batch\_max\_vcpus) | The minimum aggregate vCPU for AWS Batch compute environment | `number` | `256` | no |
| <a name="input_aws_batch_min_vcpus"></a> [aws\_batch\_min\_vcpus](#input\_aws\_batch\_min\_vcpus) | The minimum aggregate vCPU for AWS Batch compute environment | `number` | `0` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS Region | `string` | `"us-east-1"` | no |
| <a name="input_eks_cluster_name"></a> [eks\_cluster\_name](#input\_eks\_cluster\_name) | Name of the VPC and EKS Cluster | `string` | `"doeks-aws-batch"` | no |
| <a name="input_eks_cluster_version"></a> [eks\_cluster\_version](#input\_eks\_cluster\_version) | EKS Cluster Kubernetes version. AWS Batch recommends version  1.27 and higher. | `string` | `"1.30"` | no |
| <a name="input_eks_private_cluster_endpoint"></a> [eks\_private\_cluster\_endpoint](#input\_eks\_private\_cluster\_endpoint) | Whether to have a private cluster endpoint for the EKS cluster. | `bool` | `true` | no |
| <a name="input_eks_public_cluster_endpoint"></a> [eks\_public\_cluster\_endpoint](#input\_eks\_public\_cluster\_endpoint) | Whether to have a public cluster endpoint for the EKS cluster.   #WARNING: Avoid a public endpoint in preprod or prod accounts. This feature is designed for sandbox accounts, simplifying cluster deployment and testing. | `bool` | `true` | no |
| <a name="input_num_azs"></a> [num\_azs](#input\_num\_azs) | The number of Availability Zones to deploy subnets to. Must be 2 or more | `number` | `2` | no |
| <a name="input_private_subnets"></a> [private\_subnets](#input\_private\_subnets) | Private Subnets CIDRs. 32766 Subnet1 and 16382 Subnet2 IPs per Subnet | `list(string)` | <pre>[<br/>  "10.1.0.0/17",<br/>  "10.1.128.0/18"<br/>]</pre> | no |
| <a name="input_public_subnets"></a> [public\_subnets](#input\_public\_subnets) | Public Subnets CIDRs. 62 IPs per Subnet | `list(string)` | <pre>[<br/>  "10.1.255.128/26",<br/>  "10.1.255.192/26"<br/>]</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Default tags | `map(string)` | `{}` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | VPC CIDR | `string` | `"10.1.0.0/16"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aws_batch_ondemand_job_queue"></a> [aws\_batch\_ondemand\_job\_queue](#output\_aws\_batch\_ondemand\_job\_queue) | The ARN of the created AWS Batch job queue to submit jobs to. |
| <a name="output_aws_batch_spot_job_queue"></a> [aws\_batch\_spot\_job\_queue](#output\_aws\_batch\_spot\_job\_queue) | The ARN of the created AWS Batch job queue to submit jobs to. |
| <a name="output_configure_kubectl_cmd"></a> [configure\_kubectl\_cmd](#output\_configure\_kubectl\_cmd) | Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig |
| <a name="output_run_example_aws_batch_job"></a> [run\_example\_aws\_batch\_job](#output\_run\_example\_aws\_batch\_job) | Use the AWS CLI to submit the example Hello World AWS Batch job definition to the Spot job queue. |
| <a name="output_run_example_aws_batch_job_on_spot"></a> [run\_example\_aws\_batch\_job\_on\_spot](#output\_run\_example\_aws\_batch\_job\_on\_spot) | Use the AWS CLI to submit the example Hello World AWS Batch job definition to the Spot job queue. |
<!-- END_TF_DOCS -->
