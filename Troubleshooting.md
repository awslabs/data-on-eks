# Frequently Asked Questions

Frequently asked questions and debugging issues listed below

## Error: local-exec provisioner error

```sh
Error: local-exec provisioner error \
with module.eks-blueprints.module.emr_on_eks["data_team_b"].null_resource.update_trust_policy,\
 on .terraform/modules/eks-blueprints/modules/emr-on-eks/main.tf line 105, in resource "null_resource" \
 "update_trust_policy":│ 105: provisioner "local-exec" {│ │ Error running command 'set -e│ │ aws emr-containers update-role-trust-policy \
 │ --cluster-name emr-on-eks \│ --namespace emr-data-team-b \│ --role-name emr-on-eks-emr-eks-data-team-b
```
### Solution

- emr-containers not present in cli version 2.0.41 Python/3.7.4. For more [details](https://github.com/aws/aws-cli/issues/6162)
  This is fixed in version 2.0.54.
- Action: aws cli version should be updated to 2.0.54 or later : Execute `pip install --upgrade awscliv2 `

## Timeouts during Terraform Destroy

Customers who are deleting their environments using terraform destroy may see timeout errors when VPCs are being deleted. This is due to a known issue in the [vpc-cni](https://github.com/aws/amazon-vpc-cni-k8s/issues/1223#issue-704536542)

Customers may face a situation where ENIs that were attached to EKS managed nodes (same may apply to self-managed nodes) are not being deleted by the VPC CNI as expected which leads to IaC tool failures, such as:

- ENIs are left on subnets
- EKS managed security group which is attached to the ENI can’t be deleted by EKS

### Solution

The current recommendation is to execute cleanup in the following order:

delete all pods that have been created in the cluster.
add delay/ wait
delete VPC CNI
delete nodes
delete cluster

## Forbidden! Configured service account doesn't have access

Error:

    io.fabric8.kubernetes.client.KubernetesClientException: Failure executing: PATCH at: https://kubernetes.default.svc/api/v1/namespaces/emr-team-a/pods/createnosaprocessedactions-772b9c81ae56a93d-exec-394. Message: Forbidden!Configured service account doesn't have access. Service account may have been revoked. pods "createnosaprocessedactions-772b9c81ae56a93d-exec-394" is forbidden: User "system:serviceaccount:emr-team-a:emr-containers-sa-spark-driver-682942051493-76simz7hn0n7qw78flb3z0c1ldt10ou9nmbeg8sh29" cannot patch resource "pods" in API group "" in the namespace "emr-team-a".

### Solution :
The following script patches the Kubernetes roles created by EMR job execution for given namespace.
This is a mandatory fix for `EMR6.6/Spark3.2` for missing permissions. This issue will be resolved in future release e.g., EMR6.7 and the patch script may not be required
Repeat the above tests after applying the patch. This script needs to be run for all the namespaces used by by EMR on EKS Jobs

```sh
cd analytics/emr-eks-fsx-lustre/fsx_lustre
python3 emr-eks-sa-fix.py -n "emr-data-team-a"
```

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

If the EMR virtual cluster fails to delete and the following error is shown:
```
Error: waiting for EMR Containers Virtual Cluster (xwbc22787q6g1wscfawttzzgb) delete: unexpected state 'ARRESTED', wanted target ''. last error: %!s(<nil>)
```

**Solution:**
You can clean up any of the clusters in the `ARRESTED` state with the following:

```sh
aws emr-containers list-virtual-clusters --region <REGION> --states ARRESTED \
--query 'virtualClusters[0].id' --output text | xargs -I{} aws emr-containers delete-virtual-cluster \
--region <REGION> --id {}
```

## Execute this command to delete `Terminating namespace` issue

This will remove the finalizers on the namespace.

```sh
NAMESPACE=<namespace>
kubectl get namespace $NAMESPACE -o json | sed 's/"kubernetes"//' | kubectl replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" -f -
```
