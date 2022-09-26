# EMR EKS with FSx for Lustre

This example deploys [EMR on EKS](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/emr-eks.html) with [FSx for Lustre](https://docs.aws.amazon.com/fsx/latest/LustreGuide/what-is.html) using the following resources

- Creates EKS Cluster Control plane with public endpoint (for demo purpose only) with two managed node groups
- Deploys Metrics server with HA, Cluster Autoscaler, Prometheus, VPA, CoreDNS Autoscaler, FSx CSI driver
- EMR on EKS Teams and EMR Virtual cluster for `emr-data-team-a`
- Creates Amazon managed Prometheus Endpoint and configures Prometheus Server addon with remote write configuration to Amazon Managed Prometheus
- Creates PERSISTENT type FSx for Lustre filesystem, Static Persistent volume and Persistent volume claim
- Creates Scratch type FSx for Lustre filesystem with dynamic Persistent volume claim
- S3 bucket to sync FSx for Lustre filesystem data

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
cd analytics/emr-eks-fsx-lustre
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

Let’s verify the resources created by Step 4.

Verify the Amazon EKS Cluster and Amazon Managed service for Prometheus

```sh
aws eks describe-cluster --name emr-eks-fsx-lustre

aws amp list-workspaces --alias amp-ws-emr-eks-fsx-lustre
```

```sh
# Verify EMR on EKS Namespaces emr-data-team-a and emr-data-team-b and Pod status for Prometheus, Vertical Pod Autoscaler, Metrics Server and Cluster Autoscaler.

aws eks --region <ENTER_YOUR_REGION> update-kubeconfig --name emr-eks-fsx-lustre # Creates k8s config file to authenticate with EKS Cluster

kubectl get nodes # Output shows the EKS Managed Node group nodes

kubectl get ns | grep emr-data-team # Output shows emr-data-team-a and emr-data-team-b namespaces for data teams

kubectl get pods --namespace=prometheus # Output shows Prometheus server and Node exporter pods

kubectl get pods --namespace=vpa  # Output shows Vertical Pod Autoscaler pods

kubectl get pods --namespace=kube-system | grep  metrics-server # Output shows Metric Server pod

kubectl get pods --namespace=kube-system | grep  cluster-autoscaler # Output shows Cluster Autoscaler pod

kubectl get pods -n kube-system | grep fsx # Output of the FSx controller and node pods

kubectl get pvc -n emr-data-team-a  # Output of persistent volume for static(`fsx-static-pvc`) and dynamic(`fsx-dynamic-pvc`)

#FSx Storage Class
kubectl get storageclasses | grep fsx
  emr-eks-fsx-lustre   fsx.csi.aws.com         Delete          Immediate              false                  109s

# Output of static persistent volume with name `fsx-static-pv`
kubectl get pv | grep fsx  
  fsx-static-pv                              1000Gi     RWX            Recycle          Bound    emr-data-team-a/fsx-static-pvc       fsx

# Output of static persistent volume with name `fsx-static-pvc` and `fsx-dynamic-pvc`
# Pending status means that the FSx for Lustre is still getting created. This will be changed to bound once the filesystem is created. Login to AWS console to verify.
kubectl get pvc -n emr-data-team-a | grep fsx
  fsx-dynamic-pvc   Pending                                             fsx            4m56s
  fsx-static-pvc    Bound     fsx-static-pv   1000Gi     RWX            fsx            4m56s

```

## Spark Job Execution - FSx - Static Provisioning

Execute Spark Job by using FSx for Lustre with statically provisioned volume
Execute the Spark job using the below shell script.

This script requires three input parameters which can be extracted from `terraform apply` output values

    EMR_VIRTUAL_CLUSTER_ID=$1     # Terraform output variable is emrcontainers_virtual_cluster_id
    S3_BUCKET=$2                  # This script requires s3 bucket as input parameter e.g., s3://<bucket-name>
    EMR_JOB_EXECUTION_ROLE_ARN=$3 # Terraform output variable is emr_on_eks_role_arn


Note: THis script downloads the test data to your local mac and uploads to S3 bucket. Verify the shell script for more details

```sh
cd analytics/emr-eks-fsx-lustre/examples/spark-execute/

./fsx-static-spark.sh "<ENTER_EMR_VIRTUAL_CLUSTER_ID>" "s3://<ENTER-YOUR-BUCKET-NAME>" "<EMR_JOB_EXECUTION_ROLE_ARN>"
```

Verify the job execution events

```sh
kubectl get pods --namespace=emr-data-team-a -w
```
This will show the mounted `/data` directory with FSx DNS name

```sh
kubectl exec -ti ny-taxi-trip-static-exec-1 -c analytics-kubernetes-executor -n emr-data-team-a -- df -h

kubectl exec -ti ny-taxi-trip-static-exec-1 -c analytics-kubernetes-executor -n emr-data-team-a -- ls -lah /static
```

## Spark Job Execution - FSx - Dynamic Provisioning

Execute Spark Job by using FSx for Lustre with dynamically provisioned volume and Fsx for Lustre file system

- This script requires three input parameters in which `EMR_VIRTUAL_CLUSTER_ID` and `EMR_JOB_EXECUTION_ROLE_ARN` values can be extracted from `terraform apply` output values.
- For `S3_BUCKET`, Either create a new S3 bucket or use an existing S3 bucket to store the scripts, input and output data required to run this sample job.

    EMR_VIRTUAL_CLUSTER_ID=$1     # Terraform output variable is emrcontainers_virtual_cluster_id
    S3_BUCKET=$2                  # This script requires s3 bucket as input parameter e.g., s3://<bucket-name>
    EMR_JOB_EXECUTION_ROLE_ARN=$3 # Terraform output variable is emr_on_eks_role_arn

Note: This script downloads the test data to your local mac and uploads to S3 bucket. Verify the shell script for more details

```sh
cd analytics/emr-eks-fsx-lustre/examples/spark-execute/

./fsx-dynamic-spark.sh "<ENTER_EMR_VIRTUAL_CLUSTER_ID>" "s3://<ENTER-YOUR-BUCKET-NAME>" "<EMR_JOB_EXECUTION_ROLE_ARN>"
```

Verify the job execution events

```sh
kubectl get pods --namespace=emr-data-team-a -w
```

```sh
kubectl exec -ti ny-taxi-trip-dyanmic-exec-1 -c analytics-kubernetes-executor -n emr-data-team-a -- df -h

kubectl exec -ti ny-taxi-trip-dyanmic-exec-1 -c analytics-kubernetes-executor -n emr-data-team-a -- ls -lah /dyanmic
```

## Cleanup
To clean up your environment, destroy the Terraform modules in reverse order.

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
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | >= 1.14 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10 |
| <a name="requirement_random"></a> [random](#requirement\_random) | 3.3.2 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 3.72 |
| <a name="provider_kubectl"></a> [kubectl](#provider\_kubectl) | >= 1.14 |

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
| [aws_fsx_data_repository_association.example](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/fsx_data_repository_association) | resource |
| [aws_fsx_lustre_file_system.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/fsx_lustre_file_system) | resource |
| [aws_iam_policy.emr_on_eks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_prometheus_workspace.amp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/prometheus_workspace) | resource |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_acl.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_acl) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_security_group.fsx](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [kubectl_manifest.dynamic_pvc](https://registry.terraform.io/providers/gavinbunney/kubectl/latest/docs/resources/manifest) | resource |
| [kubectl_manifest.static_pv](https://registry.terraform.io/providers/gavinbunney/kubectl/latest/docs/resources/manifest) | resource |
| [kubectl_manifest.static_pvc](https://registry.terraform.io/providers/gavinbunney/kubectl/latest/docs/resources/manifest) | resource |
| [kubectl_manifest.storage_class](https://registry.terraform.io/providers/gavinbunney/kubectl/latest/docs/resources/manifest) | resource |
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
| <a name="input_name"></a> [name](#input\_name) | Name of the VPC and EKS Cluster | `string` | `"emr-eks-fsx-lustre"` | no |
| <a name="input_region"></a> [region](#input\_region) | region | `string` | `"eu-west-1"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Default tags | `map(string)` | `{}` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | VPC CIDR | `string` | `"10.1.0.0/16"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aws_fsx_lustre_file_system_arn"></a> [aws\_fsx\_lustre\_file\_system\_arn](#output\_aws\_fsx\_lustre\_file\_system\_arn) | Amazon Resource Name of the file system |
| <a name="output_aws_fsx_lustre_file_system_dns_name"></a> [aws\_fsx\_lustre\_file\_system\_dns\_name](#output\_aws\_fsx\_lustre\_file\_system\_dns\_name) | DNS name for the file system, e.g., fs-12345678.fsx.us-west-2.amazonaws.com |
| <a name="output_aws_fsx_lustre_file_system_id"></a> [aws\_fsx\_lustre\_file\_system\_id](#output\_aws\_fsx\_lustre\_file\_system\_id) | Identifier of the file system, e.g., fs-12345678 |
| <a name="output_aws_fsx_lustre_file_system_mount_name"></a> [aws\_fsx\_lustre\_file\_system\_mount\_name](#output\_aws\_fsx\_lustre\_file\_system\_mount\_name) | The value to be used when mounting the filesystem |
| <a name="output_aws_fsx_lustre_file_system_owner_id"></a> [aws\_fsx\_lustre\_file\_system\_owner\_id](#output\_aws\_fsx\_lustre\_file\_system\_owner\_id) | AWS account identifier that created the file system |
| <a name="output_configure_kubectl"></a> [configure\_kubectl](#output\_configure\_kubectl) | Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig |
| <a name="output_emr_on_eks_role_arn"></a> [emr\_on\_eks\_role\_arn](#output\_emr\_on\_eks\_role\_arn) | IAM execution role arn for EMR on EKS |
| <a name="output_emr_on_eks_role_id"></a> [emr\_on\_eks\_role\_id](#output\_emr\_on\_eks\_role\_id) | IAM execution role ID for EMR on EKS |
| <a name="output_emrcontainers_virtual_cluster_id"></a> [emrcontainers\_virtual\_cluster\_id](#output\_emrcontainers\_virtual\_cluster\_id) | EMR Containers Virtual cluster ID |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
