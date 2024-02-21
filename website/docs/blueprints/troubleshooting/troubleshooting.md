# Troubleshooting

You will find troubleshooting info for Data on Amazon EKS(DoEKS) installation issues

## Error: local-exec provisioner error

If you encounter the following error during the execution of the local-exec provisioner:

```sh
Error: local-exec provisioner error \
with module.eks-blueprints.module.emr_on_eks["data_team_b"].null_resource.update_trust_policy,\
 on .terraform/modules/eks-blueprints/modules/emr-on-eks/main.tf line 105, in resource "null_resource" \
 "update_trust_policy":│ 105: provisioner "local-exec" {│ │ Error running command 'set -e│ │ aws emr-containers update-role-trust-policy \
 │ --cluster-name emr-on-eks \│ --namespace emr-data-team-b \│ --role-name emr-on-eks-emr-eks-data-team-b
```
### Issue Description:
The error message indicates that the emr-containers command is not present in the AWS CLI version being used. This issue has been addressed and fixed in AWS CLI version 2.0.54.

### Solution
To resolve the issue, update your AWS CLI version to 2.0.54 or a later version by executing the following command:

```sh
pip install --upgrade awscliv2
```

By updating the AWS CLI version, you will ensure that the necessary emr-containers command is available and can be executed successfully during the provisioning process.

If you continue to experience any issues or require further assistance, please consult the [AWS CLI GitHub issue](https://github.com/aws/aws-cli/issues/6162) for more details or contact our support team for additional guidance.

## Timeouts during Terraform Destroy

### Issue Description:
Customers may experience timeouts during the deletion of their environments, specifically when VPCs are being deleted. This is a known issue related to the vpc-cni component.

### Symptoms:

ENIs (Elastic Network Interfaces) remain attached to subnets even after the environment is destroyed.
The EKS managed security group associated with the ENI cannot be deleted by EKS.
### Solution:
To overcome this issue, follow the recommended solution below:

Utilize the provided `cleanup.sh` scripts to ensure a proper cleanup of resources. Run the `cleanup.sh`` script, which is included in the blueprint.
This script will handle the removal of any lingering ENIs and associated security groups.


## Error: could not download chart
If you encounter the following error while attempting to download a chart:

```sh
│ Error: could not download chart: failed to download "oci://public.ecr.aws/karpenter/karpenter" at version "v0.18.1"
│
│   with module.eks_blueprints_kubernetes_addons.module.karpenter[0].module.helm_addon.helm_release.addon[0],
│   on .terraform/modules/eks_blueprints_kubernetes_addons/modules/kubernetes-addons/helm-addon/main.tf line 1, in resource "helm_release" "addon":
│    1: resource "helm_release" "addon" {
│
```

Follow the steps below to resolve the issue:

### Issue Description:
The error message indicates that there was a failure in downloading the specified chart. This issue can occur due to a bug in Terraform during the installation of Karpenter.

### Solution:
To resolve the issue, you can try the following steps:

Authenticate with ECR: Run the following command to authenticate with the ECR (Elastic Container Registry) where the chart is located:

```sh
aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws
```
Re-run terraform apply: Execute the terraform apply command again with the --auto-approve flag to reapply the Terraform configuration:
```sh
terraform apply --auto-approve
```

By authenticating with ECR and re-running the terraform apply command, you will ensure that the necessary chart can be downloaded successfully during the installation process.

## Terraform apply/destroy error to authenticate with EKS Cluster
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

**Solution:**
In this situation Terraform is unable to refresh the data resources and authenticate with EKS Cluster.
See the discussion [here](https://github.com/terraform-aws-modules/terraform-aws-eks/issues/1234)

Try this approach first by using exec plugin.

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

If the issue still persists even after the above change then you can use alternative approach of using local kube config file.
NOTE: This approach might not be ideal for production. It helps you to apply/destroy clusters with your local kube config.

1. Create a local kubeconfig for your cluster

```bash
aws eks update-kubeconfig --name <EKS_CLUSTER_NAME> --region <CLUSTER_REGION>
```

2. Update the `providers.tf` file with the below config by just using the config_path.

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

If you encounter an error message stating "waiting for EMR Containers Virtual Cluster (xwbc22787q6g1wscfawttzzgb) delete: unexpected state 'ARRESTED', wanted target ''. last error: %!s(nil)", you can follow the steps below to resolve the issue:

Note: Replace `<REGION>` with the appropriate AWS region where the virtual cluster is located.

1. Open a terminal or command prompt.
2. Run the following command to list the virtual clusters in the "ARRESTED" state:

```sh
aws emr-containers list-virtual-clusters --region <REGION> --states ARRESTED \
--query 'virtualClusters[0].id' --output text
```
This command retrieves the ID of the virtual cluster in the "ARRESTED" state.

3. Run the following command to delete the virtual cluster:

```sh
aws emr-containers list-virtual-clusters --region <REGION> --states ARRESTED \
--query 'virtualClusters[0].id' --output text | xargs -I{} aws emr-containers delete-virtual-cluster \
--region <REGION> --id {}
```
Replace `<VIRTUAL_CLUSTER_ID>` with the ID of the virtual cluster obtained from the previous step.

By executing these commands, you will be able to delete the virtual cluster that is in the "ARRESTED" state. This should resolve the unexpected state issue and allow you to proceed with further operations.

## Terminating namespace issue

If you encounter the issue where a namespace is stuck in the "Terminating" state and cannot be deleted, you can use the following command to remove the finalizers on the namespace:

Note: Replace `<namespace>` with the name of the namespace you want to delete.

```sh
NAMESPACE=<namespace>
kubectl get namespace $NAMESPACE -o json | sed 's/"kubernetes"//' | kubectl replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" -f -
```

This command retrieves the namespace details in JSON format, removes the "kubernetes" finalizer, and performs a replace operation to remove the finalizer from the namespace. This should allow the namespace to complete the termination process and be successfully deleted.

Please ensure that you have the necessary permissions to perform this operation. If you continue to experience issues or require further assistance, please reach out to our support team for additional guidance and troubleshooting steps.

## KMS Alias AlreadyExistsException

During your Terraform installation or redeployment, you might encounter an error saying: `AlreadyExistsException: An alias with the name ...` already exists. This happens when the KMS alias you're trying to create already exists in your AWS account.

```
│ Error: creating KMS Alias (alias/eks/trainium-inferentia): AlreadyExistsException: An alias with the name arn:aws:kms:us-west-2:23423434:alias/eks/trainium-inferentia already exists
│
│   with module.eks.module.kms.aws_kms_alias.this["cluster"],
│   on .terraform/modules/eks.kms/main.tf line 452, in resource "aws_kms_alias" "this":
│  452: resource "aws_kms_alias" "this" {
│
```

**Solution:**

To resolve this, delete the existing KMS alias using the aws kms delete-alias command. Remember to update the alias name and region in the command before running it.


```sh
aws kms delete-alias --alias-name <KMS_ALIAS_NAME> --region <ENTER_REGION>
```

## Error: creating CloudWatch Logs Log Group

Terraform cannot create a CloudWatch Logs log group because it already exists in your AWS account.

```
╷
│ Error: creating CloudWatch Logs Log Group (/aws/eks/trainium-inferentia/cluster): operation error CloudWatch Logs: CreateLogGroup, https response error StatusCode: 400, RequestID: 5c34c47a-72c6-44b2-a345-925824f24d38, ResourceAlreadyExistsException: The specified log group already exists
│
│   with module.eks.aws_cloudwatch_log_group.this[0],
│   on .terraform/modules/eks/main.tf line 106, in resource "aws_cloudwatch_log_group" "this":
│  106: resource "aws_cloudwatch_log_group" "this" {

```

**Solution:**

Delete the existing log group by updating log group name and the region.

```sh
aws logs delete-log-group --log-group-name <LOG_GROUP_NAME> --region <ENTER_REGION>
```

## Karpenter Error - Missing Service Linked Role

Karpenter throws below error while trying to create new instances.

```
"error":"launching nodeclaim, creating instance, with fleet error(s), AuthFailure.ServiceLinkedRoleCreationNotPermitted: The provided credentials do not have permission to create the service-linked role for EC2 Spot Instances."}
```

**Solution:**

You will need to create the service linked role in the AWS account you're using to avoid `ServiceLinkedRoleCreationNotPermitted` error.

```sh
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com
```
