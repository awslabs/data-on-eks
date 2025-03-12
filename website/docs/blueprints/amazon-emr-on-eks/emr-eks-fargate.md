---
sidebar_position: 6
sidebar_label: EMR on EKS with Fargate
---

:::danger
**DEPRECATION NOTICE**

This blueprint will be deprecated and eventually removed from this GitHub repository on **October 27, 2024**. No bugs will be fixed, and no new features will be added. The decision to deprecate is based on the lack of demand and interest in this blueprint, as well as the difficulty in allocating resources to maintain a blueprint that is not actively used by any users or customers.

If you are using this blueprint in production, please add yourself to the [adopters.md](https://github.com/awslabs/data-on-eks/blob/main/ADOPTERS.md) page and raise an issue in the repository. This will help us reconsider and possibly retain and continue to maintain the blueprint. Otherwise, you can make a local copy or use existing tags to access it.
:::

# EMR Virtual Cluster on EKS Fargate

This example shows how to provision a serverless cluster (serverless data plane) using Fargate Profiles to support EMR on EKS virtual clusters.

There are two Fargate profiles created:
1. `kube-system` to support core Kubernetes components such as CoreDNS
2. `emr-wildcard` which supports any namespaces that begin with `emr-*`; this allows for creating multiple virtual clusters without having to create additional Fargate profiles for each new cluster.

Using the `emr-on-eks` module, you can provision as many EMR virtual clusters as you would like by passing in multiple virtual cluster definitions to `emr_on_eks_config`. Each virtual cluster will get its own set of resources with permissions scoped to only that set of resources. The resources created by the `emr-on-eks` addon include:
- Kubernetes namespace, role, and role binding; existing or externally created namespace and role can be utilized as well
- IAM role for service account (IRSA) used by for job execution. Users can scope access to the appropriate S3 bucket and path via `s3_bucket_arns`, use for both accessing job data as well as writing out results. The bare minimum permissions have been provided for the job execution role; users can provide additional permissions by passing in additional policies to attach to the role via `iam_role_additional_policies`
- CloudWatch log group for task execution logs. Log streams are created by the job itself and not via Terraform
- EMR managed security group for the virtual cluster
- EMR virtual cluster scoped to the namespace created/provided

To learn more about running completely serverless EKS clusters using Fargate, see the [`fargate-serverless`](https://github.com/aws-ia/terraform-aws-eks-blueprints/tree/main/examples/fargate-serverless#serverless-eks-cluster-using-fargate-profiles) example.

:::info

Please be informed that the method of creating EMR on EKS clusters has changed and is now done as a Kubernetes add-on.
This differs from previous blueprints which deployed EMR on EKS as part of the EKS Cluster module.
Our team is working towards simplifying both deployment approaches and will soon create a standalone Terraform module for this purpose.
Additionally, all blueprints will be updated with this new dedicated EMR on EKS Terraform module.

:::

## Prerequisites:

Ensure that you have the following tools installed locally:

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### Deploy

Clone the repository

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

Navigate into one of the example directories and run `terraform init`

```bash
cd data-on-eks/analytics/emr-eks-fargate
terraform init
```

Set `AWS_REGION` and Run`terraform plan` to verify the resources created by this execution.

```bash
export AWS_REGION="us-west-2" # Change according to your need
terraform plan
```

Deploy the pattern

```bash
terraform apply
```

Enter `yes` at command prompt to apply

## Validate

The following command will update the `kubeconfig` on your local machine and allow you to interact with your EKS Cluster using `kubectl`.

1. Run `update-kubeconfig` command:

```sh
aws eks --region <REGION> update-kubeconfig --name <CLUSTER_NAME>
```

2. Test by listing all the pods running currently. Note: the EMR on EKS virtual cluster(s) will create pods as needed to execute jobs and the pods shown will vary depending on how long after deploying the example you run the `kubectl get pods -A` command:

```sh
kubectl get pods -A

# Output should look like below
NAMESPACE      NAME                                                       READY   STATUS              RESTARTS   AGE
kube-system    cluster-proportional-autoscaler-coredns-6ccfb4d9b5-sjb8m   1/1     Running             0          8m27s
kube-system    coredns-7c8d74d658-9cmn2                                   1/1     Running             0          8m27s
kube-system    coredns-7c8d74d658-pmf5l                                   1/1     Running             0          7m38s
```

3. Execute the sample EMR on EKS job. This will calculate the value of Pi using sample PySpark job.
```sh
cd analytics/terraform/emr-eks-fargate/examples
./basic-pyspark-job '<ENTER_EMR_EMR_VIRTUAL_CLUSTER_ID>' '<EMR_JOB_EXECUTION_ROLE_ARN>'
```

4. Once the job is complete, navigate to the CloudWatch log console and find the log group created by this example `/emr-on-eks-logs/emr-workload/emr-workload`. Click `Search Log Group` and enter `roughly` into the search field. You should see a log entry that has the returned results from the job.

```json
{
    "message": "Pi is roughly 3.146360",
    "time": "2022-11-20T16:46:59+00:00"
}
```

## Destroy

To teardown and remove the resources created in this example:

```sh
kubectl delete all --all -n emr-workload -n emr-custom # ensure all jobs resources are cleaned up first
terraform destroy -target="module.eks_blueprints_kubernetes_addons" -auto-approve
terraform destroy -target="module.eks" -auto-approve
terraform destroy -auto-approve
```

If the EMR virtual cluster fails to delete and the following error is shown:
```
Error: waiting for EMR Containers Virtual Cluster (xwbc22787q6g1wscfawttzzgb) delete: unexpected state 'ARRESTED', wanted target ''. last error: %!s(<nil>)
```

You can clean up any of the clusters in the `ARRESTED` state with the following:

```sh
aws emr-containers list-virtual-clusters --region us-west-2 --states ARRESTED \
--query 'virtualClusters[0].id' --output text | xargs -I{} aws emr-containers delete-virtual-cluster \
--region us-west-2 --id {}
```
