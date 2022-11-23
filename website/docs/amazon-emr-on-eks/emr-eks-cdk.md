---
sidebar_position: 6
sidebar_label: Deploying EMR on EKS with CDK blueprint
---

# Deploying EMR on EKS with CDK blueprint

## Introduction
In this post, we will learn how to use EMR on EKS AddOn and Teams in the `cdk-eks-blueprints` to deploy a an infrasturcture on EKS to submit Spark Job. The `cdk-eks-blueprints` allows you deploy an EKS cluster and enable it to be used by EMR on EKS service with minimal setup.

## Deploying the Solution

In this [example](https://github.com/awslabs/data-on-eks/tree/main/analytics/cdk/emr-eks), you will provision the following:

- Creates EKS Cluster Control plane with public endpoint (for demo purpose only)
- Two managed node groups
  - Core Node group with 3 AZs for running system critical pods. e.g., Cluster Autoscaler, CoreDNS, Observability, Logging etc.
  - Spark Node group with single AZ for running Spark jobs
- Enable EMR on EKS and creates two Data teams (`emr-data-team-a`)
  - Creates new namespace for each team
  - Creates Kubernetes role and role binding(`emr-containers` user) for the above namespace
  - New IAM role for the team execution role
  - Update AWS_AUTH config map with  emr-containers user and AWSServiceRoleForAmazonEMRContainers role
  - Create a trust relationship between the job execution role and the identity of the EMR managed service account
- EMR Virtual Cluster for `emr-data-team-a`
- IAM policy for `emr-data-team-a`
- Deploys the following Kubernetes Add-ons
    - Managed Add-ons
        - VPC CNI, CoreDNS, KubeProxy, AWS EBS CSi Driver
    - Self Managed Add-ons
        - Metrics server with HA, Cluster Autoscaler, CertManager and AwsLoadBalancerController

This blueprint can also take an EKS cluster that you defined using the `cdk-blueprints-library`.

### Prerequisites:

Ensure that you have installed the following tools on your machine.

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [CDK](https://docs.aws.amazon.com/cdk/v2/guide/getting_started.html#getting_started_install)

**NOTE:** You need to have an AWS account and region that are [bootstraped](https://docs.aws.amazon.com/cdk/v2/guide/getting_started.html#getting_started_bootstrap) by AWS CDK.

### Deploy

Clone the repository

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

Navigate into one of the example directories and run `cdk synth`

```bash
cd analytics/cdk/emr-eks
cdk synth
```

Deploy the pattern

```bash
cdk deploy --all
```

Enter `yes` to deploy.

## Verify the resources

Let’s verify the resources created by `cdk deploy`.

Verify the Amazon EKS Cluster

```bash
aws eks describe-cluster --name emr-eks-amp-amg

```

Verify EMR on EKS Namespaces `emr-data-team-a` and Pod status for `Metrics Server` and `Cluster Autoscaler`.

```bash
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

```text
EMR_VIRTUAL_CLUSTER_ID=$1     # Terraform output variable is emrcontainers_virtual_cluster_id
S3_BUCKET=$2                  # This script requires s3 bucket as input parameter e.g., s3://<bucket-name>
EMR_JOB_EXECUTION_ROLE_ARN=$3 # Terraform output variable is emr_on_eks_role_arn
```
:::caution

This shell script downloads the test data to your local machine and uploads to S3 bucket. Verify the shell script before running the job.

:::

```bash
cd analytics/emr-eks-amp-amg/examples/spark/

./emr-eks-spark-amp-amg.sh "<ENTER_EMR_VIRTUAL_CLUSTER_ID>" "s3://<ENTER-YOUR-BUCKET-NAME>" "<EMR_JOB_EXECUTION_ROLE_ARN>"
```

Verify the job execution

```bash
kubectl get pods --namespace=emr-data-team-a -w
```

## Cleanup

To clean up your environment, destroy the Terraform modules in reverse order with `--target` option to avoid destroy failures.

Destroy the Kubernetes Add-ons, EKS cluster with Node groups and VPC

```bash
cdk destroy
```

:::caution

To avoid unwanted charges to your AWS account, delete all the AWS resources created during this deployment
:::
