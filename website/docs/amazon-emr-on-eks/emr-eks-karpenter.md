---
sidebar_position: 2
sidebar_label: EMR on EKS with Karpenter
---

import CollapsibleContent from '../../src/components/CollapsibleContent';

# EMR on EKS with [Karpenter](https://karpenter.sh/)

## Introduction

In this [pattern](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/emr-eks-karpenter), you will deploy an EMR on EKS cluster and use Karpenter provisioners for scaling Spark jobs.
It will demonstrate how to use multiple storage types (**EBS PVC, Instance Storage (SSD), FSx for Lustre**) for **Spark shuffle storage**.

Additionally, all the **Karpenter Node templates** use **RAID0 configuration** to ensure Spark jobs can refer to `/local1` as one folder even if the instances have one or more SSD disks.

This pattern deploys three Karpenter provisioners, and it also provides guidance on using **Apache YuniKorn as a batch scheduler** to **gang-schedule** Spark jobs.

This example showcases how multiple data teams within an organization can run Spark jobs using Karpenter provisioners that are unique to each workload.
For example, you can use a compute-optimized provisioner that has taints and use pod templates to specify tolerations so that you can run Spark on compute-optimized EC2 instances.

- `spark-compute-optimized` provisioner to run spark jobs on `c5d` instances.
- `spark-memory-optimized` provisioner to run spark jobs on `r5d` instances.
- `spark-graviton-memory-optimized` provisioner to run spark jobs on `r6gd` Graviton instances(`ARM64`).

Let's review the Karpenter provisioner for computed optimized instances deployed by this pattern.

**Karpenter provisioner for compute optimized instances. This template leverages the pre-created AWS Launch templates.**

<CollapsibleContent header={<h3><span>Karpenter Provisioner - Compute Optimized Instances</span></h3>}>

```yaml
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: spark-compute-optimized
  namespace: karpenter # Same namespace as Karpenter add-on installed
spec:
  kubeletConfiguration:
    containerRuntime: containerd
    #    podsPerCore: 2
    #    maxPods: 20
  requirements:
    - key: "topology.kubernetes.io/zone"
      operator: In
      values: [${azs}a] #Update the correct region and zones
    - key: "karpenter.sh/capacity-type"
      operator: In
      values: ["spot", "on-demand"]
    - key: "node.kubernetes.io/instance-type" #If not included, all instance types are considered
      operator: In
      values: ["c5d.large","c5d.xlarge","c5d.2xlarge","c5d.4xlarge","c5d.9xlarge"] # 1 NVMe disk
    - key: "kubernetes.io/arch"
      operator: In
      values: ["amd64"]
  limits:
    resources:
      cpu: 1000
  providerRef:
    name: spark-compute-optimized
  labels:
    type: karpenter
    provisioner: spark-compute-optimized
    NodeGroupType: SparkComputeOptimized
  taints:
    - key: spark-compute-optimized
      value: 'true'
      effect: NoSchedule
  ttlSecondsAfterEmpty: 120 # optional, but never scales down if not set

---
apiVersion: karpenter.k8s.aws/v1alpha1
kind: AWSNodeTemplate
metadata:
  name: spark-compute-optimized
  namespace: karpenter
spec:
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 100Gi
        volumeType: gp3
        encrypted: true
        deleteOnTermination: true
  metadataOptions:
    httpEndpoint: enabled
    httpProtocolIPv6: disabled
    httpPutResponseHopLimit: 2
    httpTokens: required
  subnetSelector:
    Name: "${eks_cluster_id}-private*"        # Name of the Subnets to spin up the nodes
  securityGroupSelector:                      # required, when not using launchTemplate
    Name: "${eks_cluster_id}-node*"           # name of the SecurityGroup to be used with Nodes
  #  instanceProfile: ""      # optional, if already set in controller args

  userData: |
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="BOUNDARY"

    --BOUNDARY
    Content-Type: text/x-shellscript; charset="us-ascii"

    #!/bin/bash
    echo "Running a custom user data script"
    set -ex

    IDX=1
    DEVICES=$(lsblk -o NAME,TYPE -dsn | awk '/disk/ {print $1}')

    for DEV in $DEVICES
    do
      mkfs.xfs /dev/$${DEV}
      mkdir -p /local$${IDX}
      echo /dev/$${DEV} /local$${IDX} xfs defaults,noatime 1 2 >> /etc/fstab
      IDX=$(($${IDX} + 1))
    done

    mount -a

    /usr/bin/chown -hR +999:+1000 /local*

    --BOUNDARY--

  tags:
    InstanceType: "spark-compute-optimized"
```

</CollapsibleContent>

**Spark Jobs can use this provisioner to submit the jobs by adding `tolerations` to pod templates.**

e.g.,

```yaml
spec:
  tolerations:
    - key: "spark-compute-optimized"
      operator: "Exists"
      effect: "NoSchedule"
```

**Karpenter provisioner for memory optimized instances. This template uses the AWS Node template with Userdata.**

<CollapsibleContent header={<h3><span>Karpenter Provisioner - Memory Optimized Instances</span></h3>}>

```yaml
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: spark-memory-optimized
  namespace: karpenter
spec:
  kubeletConfiguration:
    containerRuntime: containerd
#    podsPerCore: 2
#    maxPods: 20
  requirements:
    - key: "topology.kubernetes.io/zone"
      operator: In
      values: [${azs}b] #Update the correct region and zone
    - key: "karpenter.sh/capacity-type"
      operator: In
      values: ["spot", "on-demand"]
    - key: "node.kubernetes.io/instance-type" #If not included, all instance types are considered
      operator: In
      values: ["r5d.4xlarge","r5d.8xlarge","r5d.8xlarge"] # 2 NVMe disk
    - key: "kubernetes.io/arch"
      operator: In
      values: ["amd64"]
  limits:
    resources:
      cpu: 1000
  providerRef: # optional, recommended to use instead of `provider`
    name: spark-memory-optimized
  labels:
    type: karpenter
    provisioner: spark-memory-optimized
    NodeGroupType: SparkMemoryOptimized
  taints:
    - key: spark-memory-optimized
      value: 'true'
      effect: NoSchedule
  ttlSecondsAfterEmpty: 120 # optional, but never scales down if not set

---
apiVersion: karpenter.k8s.aws/v1alpha1
kind: AWSNodeTemplate
metadata:
  name: spark-memory-optimized
  namespace: karpenter
spec:
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 200Gi
        volumeType: gp3
        encrypted: true
        deleteOnTermination: true
  metadataOptions:
    httpEndpoint: enabled
    httpProtocolIPv6: disabled
    httpPutResponseHopLimit: 2
    httpTokens: required
  subnetSelector:
    Name: "${eks_cluster_id}-private*"        # Name of the Subnets to spin up the nodes
  securityGroupSelector:                      # required, when not using launchTemplate
    Name: "${eks_cluster_id}-node*"           # name of the SecurityGroup to be used with Nodes
  instanceProfile: "${instance_profile}"      # optional, if already set in controller args
  # RAID0 ARRAY config
  userData: |
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="BOUNDARY"

    --BOUNDARY
    Content-Type: text/x-shellscript; charset="us-ascii"

    #!/bin/bash
    echo "Running a custom user data script"
    set -ex
    yum install mdadm -y

    DEVICES=$(lsblk -o NAME,TYPE -dsn | awk '/disk/ {print $1}')

    DISK_ARRAY=()

    for DEV in $DEVICES
    do
    DISK_ARRAY+=("/dev/$${DEV}")
    done

    if [ $${#DISK_ARRAY[@]} -gt 0 ]; then
    mdadm --create --verbose /dev/md0 --level=0 --raid-devices=$${#DISK_ARRAY[@]} $${DISK_ARRAY[@]}
    mkfs.xfs /dev/md0
    mkdir -p /local1
    echo /dev/md0 /local1 xfs defaults,noatime 1 2 >> /etc/fstab
    mount -a
    /usr/bin/chown -hR +999:+1000 /local1
    fi

    --BOUNDARY--

  tags:
    InstanceType: "spark-memory-optimized"    # optional, add tags for your own use

```

</CollapsibleContent>

Spark Jobs can use this provisioner to submit the jobs by adding `tolerations` to pod templates.

e.g.,

```yaml
spec:
  tolerations:
    - key: "spark-memory-optimized"
      operator: "Exists"
      effect: "NoSchedule"
```


<CollapsibleContent header={<h2><span>Deploying the Solution</span></h2>}>

In this [example](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/emr-eks-karpenter), you will provision the following resources required to run Spark Jobs using EMR on EKS with [Karpenter](https://karpenter.sh/) as Autoscaler, as well as monitor job metrics using Amazon Managed Prometheus and Amazon Managed Grafana.

- Creates EKS Cluster Control plane with public endpoint (recommended for demo/poc environment)
- One managed node group
  - Core Node group with 2 AZs for running system critical pods. e.g., Cluster Autoscaler, CoreDNS, Observability, Logging etc.
- Enables EMR on EKS and creates two Data teams (`emr-data-team-a`, `emr-data-team-b`)
  - Creates new namespace for each team
  - Creates Kubernetes role and role binding(`emr-containers` user) for the above namespace
  - New IAM role for the team execution role
  - Update `AWS_AUTH` config map with `emr-containers` user and `AWSServiceRoleForAmazonEMRContainers` role
  - Create a trust relationship between the job execution role and the identity of the EMR managed service account
  - EMR Virtual Cluster for `emr-data-team-a` and `emr-data-team-b`
- Amazon Managed Prometheus workspace to remotely write metrics from Prometheus server
- Deploys the following Kubernetes Add-ons
  - Managed Add-ons
    - VPC CNI, CoreDNS, KubeProxy, AWS EBS CSi Driver
  - Self Managed Add-ons
    - Karpetner, Apache YuniKorn(optional), FSx for Lustre(Optional), Metrics server with HA, CoreDNS Cluster proportional Autoscaler, Cluster Autoscaler, Prometheus Server and Node Exporter, VPA for Prometheus, AWS for FluentBit, CloudWatchMetrics for EKS

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
cd data-on-eks/analytics/terraform/emr-eks-karpenter
terraform init
```

Set AWS_REGION and Run Terraform plan to verify the resources created by this execution.

```bash
export AWS_REGION="us-west-2"
terraform plan
```

This command may take between 20 and 30 minutes to create all the resources.

```bash
terraform apply
```

Enter `yes` to apply.

### Verify the resources

Verify the Amazon EKS Cluster and Amazon Managed service for Prometheus

```bash
aws eks describe-cluster --name emr-eks-karpenter

aws amp list-workspaces --alias amp-ws-emr-eks-karpenter
```

Verify EMR on EKS Namespaces `emr-data-team-a` and `emr-data-team-b` and Pod status for `Prometheus`, `Vertical Pod Autoscaler`, `Metrics Server` and `Cluster Autoscaler`.

```bash
aws eks --region us-west-2 update-kubeconfig --name emr-eks-karpenter # Creates k8s config file to authenticate with EKS Cluster

kubectl get nodes # Output shows the EKS Managed Node group nodes

kubectl get ns | grep emr-data-team # Output shows emr-data-team-a and emr-data-team-b namespaces for data teams

kubectl get pods --namespace=prometheus # Output shows Prometheus server and Node exporter pods

kubectl get pods --namespace=vpa  # Output shows Vertical Pod Autoscaler pods

kubectl get pods --namespace=kube-system | grep  metrics-server # Output shows Metric Server pod

kubectl get pods --namespace=kube-system | grep  cluster-autoscaler # Output shows Cluster Autoscaler pod
```

</CollapsibleContent>

<CollapsibleContent header={<h3><span>Execute Spark job - NVMe SSD - Karpenter Compute Optimized Instances</span></h3>}>

### Execute the sample PySpark Job to trigger compute optimized Karpenter provisioner

The following script requires four input parameters `virtual_cluster_id`, `job_execution_role_arn`, `cloudwatch_log_group_name` & S3 Bucket to store PySpark scripts, Pod templates and Input data. You can get these values `terraform apply` output values or by running `terraform output`. For `S3_BUCKET`, Either create a new S3 bucket or use an existing S3 bucket.

:::caution

This shell script downloads the test data to your local machine and uploads to S3 bucket. Verify the shell script before running the job.

:::

```bash
cd data-on-eks/analytics/terraform/emr-eks-karpenter/examples/nvme-ssd/karpenter-compute-provisioner/
./execute_emr_eks_job.sh
Enter the EMR Virtual Cluster ID: 4ucrncg6z4nd19vh1lidna2b3
Enter the EMR Execution Role ARN: arn:aws:iam::123456789102:role/emr-eks-karpenter-emr-eks-data-team-a
Enter the CloudWatch Log Group name: /emr-on-eks-logs/emr-eks-karpenter/emr-data-team-a
Enter the S3 Bucket for storing PySpark Scripts, Pod Templates and Input data. For e.g., s3://<bucket-name>: s3://example-bucket
```

Karpenter may take between 1 and 2 minutes to spin up a new compute node as specified in the provisioner templates before running the Spark Jobs.
Nodes will be drained with once the job is completed

#### Verify the job execution

```bash
kubectl get pods --namespace=emr-data-team-a -w
```

</CollapsibleContent>

<CollapsibleContent header={<h3><span>Execute Spark job - EBS PVC - Karpenter Compute Optimized Instances</span></h3>}>

### Execute the sample PySpark job that uses EBS volumes and compute optimized Karpenter provisioner

This pattern uses EBS volumes for data processing and compute optimized instances.

We will create Storageclass that will be used by drivers and executors. We'll create static Persistent Volume Claim (PVC) for the driver pod but we'll use dynamically created ebs volumes for executors.

Create StorageClass and PVC using example provided
```shell
kubectl apply -f emr-eks-karpenter-ebs.yaml
```
Let's run the job

```shell
cd analytics/terraform/emr-eks-karpenter/examples/ebs-pvc/karpenter-compute-provisioner-ebs
./execute_emr_eks_job.sh

```

You'll notice the PVC `spark-driver-pvc` will be used by driver pod but Spark will create multiple ebs volumes for executors mapped to Storageclass `emr-eks-karpenter-ebs-sc`. All dynamically created ebs volumes will be deleted once the job completes

</CollapsibleContent>

<CollapsibleContent header={<h3><span>Execute Spark job - NVMe SSD - Karpenter Memory Optimized Instances</span></h3>}>

### Execute the sample PySpark Job to trigger Memory optimized Karpenter provisioner

This pattern uses the Karpenter provisioner for memory optimized instances. This template leverages the Karpenter AWS Node template with Userdata.

```bash
cd analytics/terraform/emr-eks-karpenter/examples/nvme-ssd/karpenter-memory-provisioner

./execute_emr_eks_job.sh

```

Karpetner may take between 1 and 2 minutes to spin up a new compute node as specified in the provisioner templates before running the Spark Jobs.
Nodes will be drained with once the job is completed

#### Verify the job execution

```bash
kubectl get pods --namespace=emr-data-team-a -w
```
</CollapsibleContent>

<CollapsibleContent header={<h3><span>Execute Spark job - NVMe SSD - Karpenter Graviton Instances</span></h3>}>

### Execute the sample PySpark Job to trigger Graviton Memory optimized Karpenter provisioner

This pattern uses the Karpenter provisioner for Graviton memory optimized instances. This template leverages the Karpenter AWS Node template with Userdata.

```bash
analytics/terraform/emr-eks-karpenter/examples/nvme-ssd/karpenter-graviton-memory-provisioner

./execute_emr_eks_job.sh

```

Karpetner may take between 1 and 2 minutes to spin up a new compute node as specified in the provisioner templates before running the Spark Jobs.
Nodes will be drained with once the job is completed

#### Verify the job execution

```bash
kubectl get pods --namespace=emr-data-team-a -w
```

</CollapsibleContent>

## FSx for Lustre

Amazon FSx for Lustre is a fully managed shared storage option built on the world’s most popular high-performance file system. It offers highly scalable, cost-effective storage, which provides sub-millisecond latencies, millions of IOPS, and throughput of hundreds of gigabytes per second. Its popular use cases include high-performance computing (HPC), financial modeling, video rendering, and machine learning. FSx for Lustre supports two types of deployments:

For storage, EMR on EKS supports node ephemeral storage using hostPath where the storage is attached to individual nodes, and Amazon Elastic Block Store (Amazon EBS) volume per executor/driver pod using dynamic Persistent Volume Claims. However, some Spark users are looking for an HDFS-like shared file system to handle specific workloads like time-sensitive applications or streaming analytics.

In this example, you will learn how to deploy, configure and use FSx for Lustre as a shuffle storage for running Spark jobs with EMR on EKS.


<CollapsibleContent header={<h3><span>Execute Spark job - FSx for Lustre Static Provisioning</span></h3>}>

Fsx for Lustre Terraform module is disabled by default. Follow the steps to deploy the FSx for Lustre module and execute the Spark job.

1. Update the `analytics/terraform/emr-eks-karpenter/variables.tf` file with the following

```terraform
variable "enable_fsx_for_lustre" {
  default     = true
  description = "Deploys fsx for lustre addon, storage class and static FSx for Lustre filesystem for EMR"
  type        = bool
}

```

2. Execute `terrafrom apply` again. This will deploy FSx for Lustre add-on and all the necessary reosurces.

```terraform
terraform apply -auto-approve
```

3. Execute Spark Job by using `FSx for Lustre` as a Shuffle storage for Driver and Executor pods with statically provisioned volume.
Execute the Spark job using the below shell script.

This script requires input parameters which can be extracted from `terraform apply` output values.

:::caution

This shell script downloads the test data to your local machine and uploads to S3 bucket. Verify the shell script before running the job.

:::

```bash
cd analytics/terraform/emr-eks-karpenter/examples/fsx-for-lustre/fsx-static-pvc-shuffle-storage

./fsx-static-spark.sh
```
Karpetner may take between 1 and 2 minutes to spin up a new compute node as specified in the provisioner templates before running the Spark Jobs.
Nodes will be drained with once the job is completed

**Verify the job execution events**

```bash
kubectl get pods --namespace=emr-data-team-a -w
```
This will show the mounted `/data` directory with FSx DNS name

```bash
kubectl exec -ti ny-taxi-trip-static-exec-1 -c analytics-kubernetes-executor -n emr-data-team-a -- df -h

kubectl exec -ti ny-taxi-trip-static-exec-1 -c analytics-kubernetes-executor -n emr-data-team-a -- ls -lah /static
```

</CollapsibleContent>

<CollapsibleContent header={<h3><span>Execute Spark job - FSx for Lustre Dynamic Provisioning</span></h3>}>
Fsx for Lustre Terraform module is disabled by default. Follow the steps to deploy the FSx for Lustre module and execute the Spark job.

1. Update the `analytics/terraform/emr-eks-karpenter/variables.tf` file with the following

```terraform
variable "enable_fsx_for_lustre" {
  default     = true
  description = "Deploys fsx for lustre addon, storage class and static FSx for Lustre filesystem for EMR"
  type        = bool
}

```

2. Execute `terrafrom apply` again. This will deploy FSx for Lustre add-on and all the necessary reosurces.

```terraform
terraform apply -auto-approve
```

3. Execute Spark Job by using `FSx for Lustre` as a Shuffle storage for Driver and Executor pods with dynamically provisioned FSx filesystem and Persistent volume.
Execute the Spark job using the below shell script.

This script requires input parameters which can be extracted from `terraform apply` output values.

:::caution

This shell script downloads the test data to your local machine and uploads to S3 bucket. Verify the shell script before running the job.

:::

```bash
cd analytics/terraform/emr-eks-karpenter/examples/fsx-for-lustre/fsx-dynamic-pvc-shuffle-storage

./fsx-static-spark.sh
```
Karpetner may take between 1 and 2 minutes to spin up a new compute node as specified in the provisioner templates before running the Spark Jobs.
Nodes will be drained with once the job is completed

**Verify the job execution events**

```bash
kubectl get pods --namespace=emr-data-team-a -w
```

```bash
kubectl exec -ti ny-taxi-trip-dyanmic-exec-1 -c analytics-kubernetes-executor -n emr-data-team-a -- df -h

kubectl exec -ti ny-taxi-trip-dyanmic-exec-1 -c analytics-kubernetes-executor -n emr-data-team-a -- ls -lah /dyanmic
```

</CollapsibleContent>

## Apache YuniKorn - Batch Scheduler

Apache YuniKorn is an open-source, universal resource scheduler for managing distributed big data processing workloads such as Spark, Flink, and Storm. It is designed to efficiently manage resources across multiple tenants in a shared, multi-tenant cluster environment.
Some of the key features of Apache YuniKorn include:
 - **Flexibility**: YuniKorn provides a flexible and scalable architecture that can handle a wide variety of workloads, from long-running services to batch jobs.
 - **Dynamic Resource Allocation**: YuniKorn uses a dynamic resource allocation mechanism to allocate resources to workloads on an as-needed basis, which helps to minimize resource wastage and improve overall cluster utilization.
 - **Priority-based Scheduling**: YuniKorn supports priority-based scheduling, which allows users to assign different levels of priority to their workloads based on business requirements.
 - **Multi-tenancy**: YuniKorn supports multi-tenancy, which enables multiple users to share the same cluster while ensuring resource isolation and fairness.
 - **Pluggable Architecture**: YuniKorn has a pluggable architecture that allows users to extend its functionality with custom scheduling policies and pluggable components.

Apache YuniKorn is a powerful and versatile resource scheduler that can help organizations efficiently manage their big data workloads while ensuring high resource utilization and workload performance.

## Architecture
![Apache YuniKorn](img/yunikorn.png)

<CollapsibleContent header={<h3><span>Apache YuniKorn Gang Scheduling with Karpenter</span></h3>}>
### Apache YuniKorn Gang Scheduling with Karpenter

Apache YuniKorn Scheduler add-on is disabled by default. Follow the steps to deploy the Apache YuniKorn add-on and execute the Spark job.

1. Update the `analytics/terraform/emr-eks-karpenter/variables.tf` file with the following

```terraform
variable "enable_yunikorn" {
  default     = true
  description = "Enable Apache YuniKorn Scheduler"
  type        = bool
}
```

2. Execute `terrafrom apply` again. This will deploy FSx for Lustre add-on and all the necessary reosurces.

```terraform
terraform apply -auto-approve
```

This example demonstrates the [Apache YuniKorn Gang Scheduling](https://yunikorn.apache.org/docs/user_guide/gang_scheduling/) with Karpenter Autoscaler.

```bash
cd analytics/terraform/emr-eks-karpenter/examples/nvme-ssd/karpenter-yunikorn-gangscheduling

./execute_emr_eks_job.sh
```

#### Verify the job execution
Apache YuniKorn Gang Scheduling will create pause pods for total number of executors requested.

```bash
kubectl get pods --namespace=emr-data-team-a -w
```
Verify the driver and executor pods prefix with `tg-` indicates the pause pods.
These pods will be replaced with the actual Spark Driver and Executor pods once the Nodes are scaled and ready by the Karpenter.

![img.png](img/karpenter-yunikorn-gang-schedule.png)

</CollapsibleContent>

<CollapsibleContent header={<h2><span>Cleanup</span></h2>}>
## Cleanup

This script will cleanup the environment using `-target` option to ensure all the resources are deleted in correct order.

```bash
cd analytics/terraform/emr-eks-karpenter/ && chmod +x cleanup.sh
./cleanup.sh
```
</CollapsibleContent>

:::caution

To avoid unwanted charges to your AWS account, delete all the AWS resources created during this deployment
:::
