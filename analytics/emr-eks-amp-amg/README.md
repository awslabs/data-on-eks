# EMR on EKS

This example deploys [EMR on EKS](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/emr-eks.html) using the following resources

- Creates EKS Cluster Control plane with public endpoint (for demo purpose only)
- Two managed node groups
  - Core Node group with 3 AZs for Core add-ons. e.g., Cluster Autoscaler, CoreDNS and any other deployment type
  - Spark Node group with single AZ for running Spark jobs
- Enable EMR on EKS and creates two Data teams (emr-data-team-a, emr-data-team-b)
  - Creates new namespace for each team
  - Creates Kubernetes role and role binding(emr-containers user) for the above namespace
  - New IAM role for the team execution role
  - Update AWS_AUTH config map with  emr-containers user and AWSServiceRoleForAmazonEMRContainers role
  - Create a trust relationship between the job execution role and the identity of the EMR managed service account
- EMR Virtual Cluster for emr-data-team-a
- IAM policy for emr-data-team-a
- Amazon Managed Prometheus workspace to remote write metrics from Prometheus server
- Deploys the following Kubernetes Add-ons
  - Managed Add-ons
    - VPC CNI
    - CoreDNS
    - KubeProxy
    - AWS EBS CSi Driver
  - Self Managed Add-ons
    - Metrics server with HA
    - CoreDNS Cluster proportional Autoscaler
    - Cluster Autoscaler
    - Prometheus Server and Node Exporter
    - VPA for Prometheus
    - AWS for FluentBit
    - CloudWatchMetrics for EKS

## Prerequisites:

Ensure that you have installed the following tools on your machine.

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

_Note: Currently Amazon Managed Prometheus supported only in selected regions. Please see this [userguide](https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-Prometheus.html) for supported regions._

## Deploy EKS Clusters with EMR on EKS feature

Clone the repository

```sh
git clone https://github.com/awslabs/data-on-eks.git
```

Navigate into one of the example directories and run `terraform init`

```sh
cd analytics/emr-eks-amp-amg
terraform init
```

Set AWS_REGION and Run Terraform plan to verify the resources created by this execution.

```sh
export AWS_REGION="<enter-your-region>"
terraform plan
```

**Deploy the pattern**

```sh
terraform apply
```

Enter `yes` to apply.

## Verify the resources

Let’s verify the resources created by `terraform apply`

Verify the Amazon EKS Cluster and Amazon Managed service for Prometheus

```sh
aws eks describe-cluster --name emr-eks-amp-amg

aws amp list-workspaces --alias amp-ws-emr-eks-amp-amg
```

Verify EMR on EKS Namespaces `emr-data-team-a` and `emr-data-team-b` and Pod status for `Prometheus`, `Vertical Pod Autoscaler`, `Metrics Server` and `Cluster Autoscaler`.

```sh
aws eks --region <ENTER_YOUR_REGION> update-kubeconfig --name emr-eks-amp-amg # Creates k8s config file to authenticate with EKS Cluster

kubectl get nodes # Output shows the EKS Managed Node group nodes

kubectl get ns | grep emr-data-team # Output shows emr-data-team-a and emr-data-team-b namespaces for data teams

kubectl get pods --namespace=prometheus # Output shows Prometheus server and Node exporter pods

kubectl get pods --namespace=vpa  # Output shows Vertical Pod Autoscaler pods

kubectl get pods --namespace=kube-system | grep  metrics-server # Output shows Metric Server pod

kubectl get pods --namespace=kube-system | grep  cluster-autoscaler # Output shows Cluster Autoscaler pod
```

## Execute Sample Spark job on EMR Virtual Cluster

Execute the Spark job using the below shell script.
- This script requires three input parameters in which `EMR_VIRTUAL_CLUSTER_ID` and `EMR_JOB_EXECUTION_ROLE_ARN` values can be extracted from `terraform apply` output values.
- For `S3_BUCKET`, Either create a new S3 bucket or use an existing S3 bucket to store the scripts, input and output data required to run this sample job.


    EMR_VIRTUAL_CLUSTER_ID=$1     # Terraform output variable is emrcontainers_virtual_cluster_id
    S3_BUCKET=$2                  # This script requires s3 bucket as input parameter e.g., s3://<bucket-name>
    EMR_JOB_EXECUTION_ROLE_ARN=$3 # Terraform output variable is emr_on_eks_role_arn

**NOTE: This script downloads the test data to your local machine and uploads to S3 bucket. Verify the shell script before running the job.**

```sh
cd analytics/emr-eks-amp-amg/examples/spark/

./emr-eks-spark-amp-amg.sh "<ENTER_EMR_VIRTUAL_CLUSTER_ID>" "s3://<ENTER-YOUR-BUCKET-NAME>" "<EMR_JOB_EXECUTION_ROLE_ARN>"
```

Verify the job execution

```sh
kubectl get pods --namespace=emr-data-team-a -w
```

### Setup Amazon Managed Grafana and monitor EMR EKS Spark jobs

Currently, this step is manual. Please follow the steps in this [blog](https://aws.amazon.com/blogs/mt/monitoring-amazon-emr-on-eks-with-amazon-managed-prometheus-and-amazon-managed-grafana/) to create Amazon Managed Grafana with SSO enabled in your account.
You can visualize the Spark jobs runs and metrics using Amazon Managed Prometheus and Amazon Managed Grafana.


## Cleanup

To clean up your environment, destroy the Terraform modules in reverse order with `--target` option to avoid destroy failures.

Destroy the Kubernetes Add-ons, EKS cluster with Node groups and VPC

```sh
terraform destroy -target="module.eks_blueprints_kubernetes_addons" -auto-approve
terraform destroy -target="module.eks_blueprints" -auto-approve
terraform destroy -target="module.vpc" -auto-approve
```

Finally, destroy any additional resources that are not in the above modules

```sh
terraform destroy -auto-approve
```

**NOTE: To avoid unwanted charges to your AWS account, delete all the AWS resources created during this deployment**

---

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 3.72 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.4.1 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 3.72 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_eks_blueprints"></a> [eks\_blueprints](#module\_eks\_blueprints) | github.com/aws-ia/terraform-aws-eks-blueprints | v4.10.0 |
| <a name="module_eks_blueprints_kubernetes_addons"></a> [eks\_blueprints\_kubernetes\_addons](#module\_eks\_blueprints\_kubernetes\_addons) | github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons | v4.10.0 |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | ~> 3.0 |

## Resources

| Name | Type |
|------|------|
| [aws_emrcontainers_virtual_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/emrcontainers_virtual_cluster) | resource |
| [aws_iam_policy.emr_on_eks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_prometheus_workspace.amp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/prometheus_workspace) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_eks_cluster_auth.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_cluster_auth) | data source |
| [aws_iam_policy_document.emr_on_eks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_eks_cluster_version"></a> [eks\_cluster\_version](#input\_eks\_cluster\_version) | EKS Cluster version | `string` | `"1.23"` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the VPC and EKS Cluster | `string` | `"emr-eks-amp-amg"` | no |
| <a name="input_region"></a> [region](#input\_region) | region | `string` | `"eu-west-1"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Default tags | `map(string)` | `{}` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | VPC CIDR | `string` | `"10.1.0.0/16"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_configure_kubectl"></a> [configure\_kubectl](#output\_configure\_kubectl) | Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig |
| <a name="output_emr_on_eks_role_arn"></a> [emr\_on\_eks\_role\_arn](#output\_emr\_on\_eks\_role\_arn) | IAM execution role arn for EMR on EKS |
| <a name="output_emr_on_eks_role_id"></a> [emr\_on\_eks\_role\_id](#output\_emr\_on\_eks\_role\_id) | IAM execution role ID for EMR on EKS |
| <a name="output_emrcontainers_virtual_cluster_id"></a> [emrcontainers\_virtual\_cluster\_id](#output\_emrcontainers\_virtual\_cluster\_id) | EMR Containers Virtual cluster ID |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
