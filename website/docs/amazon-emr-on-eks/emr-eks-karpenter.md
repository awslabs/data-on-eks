---
sidebar_position: 2
sidebar_label: EMR on EKS with Karpenter
---

# EMR on EKS with [Karpenter](https://karpenter.sh/)

## Introduction

In this [pattern](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/emr-eks-karpenter), you will deploy an EMR on EKS cluster and use [Karpenter](https://karpenter.sh/) provisioners for scaling Spark jobs.

The examples showcases how multiple data teams within an organization can run Spark jobs using Karpenter provisioners that are unique to each workload. For example, you can use compute optimized provisioner that has `taints` and use pod templates to specify `tolerations` so that you can run spark on compute optimized EC2 instances

This pattern deploys three Karpenter provisioners.

- `spark-compute-optimized` provisioner to run spark jobs on `c5d` instances.
- `spark-memory-optimized` provisioner to run spark jobs on `r5d` instances.
- `spark-graviton-memory-optimized` provisioner to run spark jobs on `r6gd` Graviton instances(`ARM64`).

Let's review the Karpenter provisioner for computed optimized instances deployed by this pattern.

**Karpenter provisioner for compute optimized instances. This template leverages the pre-created AWS Launch templates.**

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
  subnetSelector:
    Name: "${eks_cluster_id}-private*"       # required
  launchTemplate: "${launch_template_name}"  # optional, see Launch Template documentation
  tags:
    InstanceType: "spark-compute-optimized"  # optional, add tags for your own use

```

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
    InstanceType: "spark-memory-optimized"    # optional, add tags for your own use

```

Spark Jobs can use this provisioner to submit the jobs by adding `tolerations` to pod templates.

e.g.,

```yaml
spec:
  tolerations:
    - key: "spark-memory-optimized"
      operator: "Exists"
      effect: "NoSchedule"
```
## Deploying the Solution

In this [example](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/emr-eks-karpenter), you will provision the following resources required to run Spark Jobs using EMR on EKS with [Karpenter](https://karpenter.sh/) as Autoscaler, as well as monitor job metrics using Amazon Managed Prometheus and Amazon Managed Grafana.

- Creates EKS Cluster Control plane with public endpoint (recommended for demo/poc environment)
- One managed node group
  - Core Node group with 3 AZs for running system critical pods. e.g., Cluster Autoscaler, CoreDNS, Observability, Logging etc.
- Enables EMR on EKS and creates two Data teams (`emr-data-team-a`, `emr-data-team-b`)
  - Creates new namespace for each team
  - Creates Kubernetes role and role binding(`emr-containers` user) for the above namespace
  - New IAM role for the team execution role
  - Update `AWS_AUTH` config map with `emr-containers` user and `AWSServiceRoleForAmazonEMRContainers` role
  - Create a trust relationship between the job execution role and the identity of the EMR managed service account
- EMR Virtual Cluster for `emr-data-team-a` and IAM policy for `emr-data-team-a`
- Amazon Managed Prometheus workspace to remotely write metrics from Prometheus server
- Deploys the following Kubernetes Add-ons
  - Managed Add-ons
    - VPC CNI, CoreDNS, KubeProxy, AWS EBS CSi Driver
  - Self Managed Add-ons
    - Karpetner, Apache YuniKorn, Metrics server with HA, CoreDNS Cluster proportional Autoscaler, Cluster Autoscaler, Prometheus Server and Node Exporter, VPA for Prometheus, AWS for FluentBit, CloudWatchMetrics for EKS

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

## Execute Sample Spark job

### Execute the sample PySpark Job to trigger compute optimized Karpenter provisioner

1. The following script requires three input parameters in which `EMR_VIRTUAL_CLUSTER_NAME` and `EMR_JOB_EXECUTION_ROLE_ARN` values can be extracted from `terraform apply` output values.
2. For `S3_BUCKET`, Either create a new S3 bucket or use an existing S3 bucket to store the scripts, input and output data required to run this sample job.

```text
EMR_VIRTUAL_CLUSTER_NAME=$1   # Terraform output variable is emrcontainers_virtual_cluster_name
S3_BUCKET=$2                  # This script requires S3 bucket as input parameter e.g., s3://<bucket-name>
EMR_JOB_EXECUTION_ROLE_ARN=$3 # Terraform output variable is emr_on_eks_role_arn
```

:::caution

This shell script downloads the test data to your local machine and uploads to S3 bucket. Verify the shell script before running the job.

:::

```bash
cd data-on-eks/analytics/terraform/emr-eks-karpenter/examples/karpenter-compute-provisioner/

./execute_emr_eks_job.sh "<EMR_VIRTUAL_CLUSTER_NAME>" \
  "s3://<ENTER-YOUR-BUCKET-NAME>" \
  "<EMR_JOB_EXECUTION_ROLE_ARN>"
```

Karpenter may take between 1 and 2 minutes to spin up a new compute node as specified in the provisioner templates before running the Spark Jobs.
Nodes will be drained with once the job is completed

#### Verify the job execution

```bash
kubectl get pods --namespace=emr-data-team-a -w
```

### Execute the sample PySpark Job to trigger Memory optimized Karpenter provisioner

This pattern uses the Karpenter provisioner for memory optimized instances. This template leverages the Karpenter AWS Node template with Userdata.

```bash
cd data-on-eks/analytics/terraform/emr-eks-karpenter/examples/karpenter-memory-provisioner

./execute_emr_eks_job.sh "<EMR_VIRTUAL_CLUSTER_NAME>" \
  "s3://<ENTER-YOUR-BUCKET-NAME>" \
  "<EMR_JOB_EXECUTION_ROLE_ARN>"
```

Karpetner may take between 1 and 2 minutes to spin up a new compute node as specified in the provisioner templates before running the Spark Jobs.
Nodes will be drained with once the job is completed

#### Verify the job execution

```bash
kubectl get pods --namespace=emr-data-team-a -w
```

### Apache YuniKorn Gang Scheduling with Karpenter

This example demonstrates the [Apache YuniKorn Gang Scheduling](https://yunikorn.apache.org/docs/user_guide/gang_scheduling/) with Karpenter Autoscaler.

```bash
cd data-on-eks/analytics/terraform/emr-eks-karpenter/examples/karpenter-yunikorn-gangscheduling

./execute_emr_eks_job.sh "<EMR_VIRTUAL_CLUSTER_NAME>" \
  "s3://<ENTER-YOUR-BUCKET-NAME>" \
  "<EMR_JOB_EXECUTION_ROLE_ARN>"
```

#### Verify the job execution
Apache YuniKorn Gang Scheduling will create pause pods for total number of executors requested.

```bash
kubectl get pods --namespace=emr-data-team-a -w
```
Verify the driver and executor pods prefix with `tg-` indicates the pause pods.
These pods will be replaced with the actual Spark Driver and Executor pods once the Nodes are scaled and ready by the Karpenter.

![img.png](img/karpenter-yunikorn-gang-schedule.png)

## Cleanup

To clean up your environment, destroy the Terraform modules in reverse order with `--target` option to avoid destroy failures.

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
