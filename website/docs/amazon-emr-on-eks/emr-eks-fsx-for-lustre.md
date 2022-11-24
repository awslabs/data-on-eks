---
sidebar_position: 4
sidebar_label: EMR on EKS with FSx for Lustre
---

# EMR on EKS with FSx for Lustre

## Introduction
Amazon FSx for Lustre is a fully managed shared storage option built on the world’s most popular high-performance file system. It offers highly scalable, cost-effective storage, which provides sub-millisecond latencies, millions of IOPS, and throughput of hundreds of gigabytes per second. Its popular use cases include high-performance computing (HPC), financial modeling, video rendering, and machine learning. FSx for Lustre supports two types of deployments:

For storage, EMR on EKS supports node ephemeral storage using `hostPath` where the storage is attached to individual nodes, and Amazon Elastic Block Store (Amazon EBS) volume per executor/driver pod using dynamic `Persistent Volume Claims`.
However, some Spark users are looking for an **HDFS-like shared file system** to handle specific workloads like time-sensitive applications or streaming analytics.

In this example, you will learn how to deploy, configure and use FSx for Lustre as a shuffle storage for running Spark jobs with EMR on EKS.

## Deploying the Solution
In this [example](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/emr-eks-fsx-lustre), you will provision the following resources required to run Spark Jobs using EMR on EKS with FSx for Lustre as shuffle storage, as well as monitor spark job metrics using **Amazon Managed Prometheus** and **Amazon Managed Grafana**.

- Creates EKS Cluster Control plane with public endpoint (for demo purpose only) with two managed node groups
- Deploys Metrics server with HA, Cluster Autoscaler, Prometheus, VPA, CoreDNS Autoscaler, FSx CSI driver
- EMR on EKS Teams and EMR Virtual cluster for `emr-data-team-a`
- Creates Amazon managed Prometheus Endpoint and configures Prometheus Server addon with remote write configuration to Amazon Managed Prometheus
- Creates PERSISTENT type FSx for Lustre filesystem, Static Persistent volume and Persistent volume claim
- Creates Scratch type FSx for Lustre filesystem with dynamic Persistent volume claim
- S3 bucket to sync FSx for Lustre filesystem data

### Prerequisites:

Ensure that you have installed the following tools on your machine.

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

_Note: Currently Amazon Managed Prometheus supported only in selected regions. Please see this [userguide](https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-Prometheus.html) for supported regions._

### Deploy

Clone the repository

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

Navigate into one of the example directories and run `terraform init`

```bash
cd data-on-eks/analytics/emr-eks-fsx-lustre
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

Enter `yes` to apply.

## Verify the resources

Let’s verify the resources created by `terraform apply`.

Verify the Amazon EKS Cluster and Amazon Managed service for Prometheus

```bash
aws eks describe-cluster --name emr-eks-fsx-lustre

aws amp list-workspaces --alias amp-ws-emr-eks-fsx-lustre
```

```bash
# Verify EMR on EKS Namespaces emr-data-team-a and emr-data-team-b and Pod status for Prometheus, Vertical Pod Autoscaler, Metrics Server and Cluster Autoscaler.

aws eks --region us-west-2 update-kubeconfig --name emr-eks-fsx-lustre # Creates k8s config file to authenticate with EKS Cluster

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

## Spark Job Execution - FSx for Lustre Static Provisioning

Execute Spark Job by using `FSx for Lustre` with statically provisioned volume.
Execute the Spark job using the below shell script.

This script requires three input parameters which can be extracted from `terraform apply` output values.

```text
EMR_VIRTUAL_CLUSTER_ID=$1     # Terraform output variable is emrcontainers_virtual_cluster_id
S3_BUCKET=$2                  # This script requires s3 bucket as input parameter e.g., s3://<bucket-name>
EMR_JOB_EXECUTION_ROLE_ARN=$3 # Terraform output variable is emr_on_eks_role_arn
```
:::caution

This shell script downloads the test data to your local machine and uploads to S3 bucket. Verify the shell script before running the job.

:::

```bash
cd data-on-eks/analytics/emr-eks-fsx-lustre/examples/spark-execute/

./fsx-static-spark.sh "<ENTER_EMR_VIRTUAL_CLUSTER_ID>" "s3://<ENTER-YOUR-BUCKET-NAME>" "<EMR_JOB_EXECUTION_ROLE_ARN>"
```

Verify the job execution events

```bash
kubectl get pods --namespace=emr-data-team-a -w
```
This will show the mounted `/data` directory with FSx DNS name

```bash
kubectl exec -ti ny-taxi-trip-static-exec-1 -c analytics-kubernetes-executor -n emr-data-team-a -- df -h

kubectl exec -ti ny-taxi-trip-static-exec-1 -c analytics-kubernetes-executor -n emr-data-team-a -- ls -lah /static
```

## Spark Job Execution - FSx for Lustre Dynamic Provisioning

Execute Spark Job by using FSx for Lustre with dynamically provisioned volume and Fsx for Lustre file system

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
cd data-on-eks/analytics/emr-eks-fsx-lustre/examples/spark-execute/

./fsx-dynamic-spark.sh "<ENTER_EMR_VIRTUAL_CLUSTER_ID>" "s3://<ENTER-YOUR-BUCKET-NAME>" "<EMR_JOB_EXECUTION_ROLE_ARN>"
```

Verify the job execution events

```bash
kubectl get pods --namespace=emr-data-team-a -w
```

```bash
kubectl exec -ti ny-taxi-trip-dyanmic-exec-1 -c analytics-kubernetes-executor -n emr-data-team-a -- df -h

kubectl exec -ti ny-taxi-trip-dyanmic-exec-1 -c analytics-kubernetes-executor -n emr-data-team-a -- ls -lah /dyanmic
```

## Cleanup
To clean up your environment, destroy the Terraform modules in reverse order.

Destroy the Kubernetes Add-ons, EKS cluster with Node groups and VPC

```bash
terraform destroy -target="module.eks_blueprints_kubernetes_addons" -auto-approve
terraform destroy -target="module.eks_blueprints" -auto-approve
terraform destroy -target="module.vpc" -auto-approve
```

Finally, destroy any additional resources that are not in the above modules

```bash
terraform destroy -auto-approve
```

:::caution

To avoid unwanted charges to your AWS account, delete all the AWS resources created during this deployment
:::
