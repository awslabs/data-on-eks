---
sidebar_position: 6
sidebar_label: EMR Runtime with Spark Operator
---
import CollapsibleContent from '../../../src/components/CollapsibleContent';

# EMR Runtime with Spark Operator

## Introduction
In this post, we will learn to deploy EKS with EMR Spark Operator and execute sample Spark job with EMR runtime.

In this [example](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/emr-eks-karpenter), you will provision the following resources required to run Spark Applications using the Spark Operator and EMR runtime.

- Creates EKS Cluster Control plane with public endpoint (for demo purpose only)
- Two managed node groups
  - Core Node group with 3 AZs for running system critical pods. e.g., Cluster Autoscaler, CoreDNS, Observability, Logging etc.
  - Spark Node group with single AZ for running Spark jobs
- Creates one Data team (`emr-data-team-a`)
  - Creates new namespace for the team
  - New IAM role for the team execution role
- IAM policy for `emr-data-team-a`
- Spark History Server Live UI is configured for monitoring running Spark jobs through an NLB and NGINX ingress controller
- Deploys the following Kubernetes Add-ons
    - Managed Add-ons
        - VPC CNI, CoreDNS, KubeProxy, AWS EBS CSi Driver
    - Self Managed Add-ons
        - Metrics server with HA, CoreDNS Cluster proportional Autoscaler, Cluster Autoscaler, Prometheus Server and Node Exporter, AWS for FluentBit, CloudWatchMetrics for EKS


<CollapsibleContent header={<h2><span>EMR Spark Operator</span></h2>}>

The Kubernetes Operator for Apache Spark aims to make specifying and running Spark applications as easy and idiomatic as running other workloads on Kubernetes. To submit Spark Applications to Spark Operator and leverage the EMR Runtime we use the Helm Chart hosted in the EMR on EKS ECR repository. The charts are stored under the following path: `ECR_URI/spark-operator`. The ECR repository can be obtained from this [link](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/setting-up-emr-runtime.html).

* a SparkApplication controller that watches events of creation, updates, and deletion of SparkApplication objects and acts on the watch events,
* a submission runner that runs spark-submit for submissions received from the controller,
* a Spark pod monitor that watches for Spark pods and sends pod status updates to the controller,
* a Mutating Admission Webhook that handles customizations for Spark driver and executor pods based on the annotations on the pods added by the controller

</CollapsibleContent>

<CollapsibleContent header={<h2><span>Deploying the Solution</span></h2>}>
### Prerequisites:

Ensure that you have installed the following tools on your machine.

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### Deploy

Clone the repository

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

Navigate to `analytics/terraform/emr-eks-karpenter` and run `terraform init`

```bash
cd ./data-on-eks/analytics/terraform/emr-eks-karpenter
terraform init
```

:::info
To deploy the EMR Spark Operator Add-on. You need to set the the below value to `true` in `variables.tf` file.

```hcl
variable "enable_emr_spark_operator" {
  description = "Enable the Spark Operator to submit jobs with EMR Runtime"
  default     = true
  type        = bool
}
```

:::

Deploy the pattern

```bash
terraform apply
```

Enter `yes` to apply.

## Verify the resources

Let’s verify the resources created by `terraform apply`.

Verify the Spark Operator and Amazon Managed service for Prometheus.

```bash

helm list --namespace spark-operator -o yaml

aws amp list-workspaces --alias amp-ws-emr-eks-karpenter

```

Verify Namespace `emr-data-team-a` and Pod status for `Prometheus`, `Vertical Pod Autoscaler`, `Metrics Server` and `Cluster Autoscaler`.

```bash
aws eks --region us-west-2 update-kubeconfig --name spark-operator-doeks # Creates k8s config file to authenticate with EKS Cluster

kubectl get nodes # Output shows the EKS Managed Node group nodes

kubectl get ns | grep emr-data-team # Output shows emr-data-team-a for data team

kubectl get pods --namespace=vpa  # Output shows Vertical Pod Autoscaler pods

kubectl get pods --namespace=kube-system | grep  metrics-server # Output shows Metric Server pod

kubectl get pods --namespace=kube-system | grep  cluster-autoscaler # Output shows Cluster Autoscaler pod
```

</CollapsibleContent>

<CollapsibleContent header={<h2><span>Execute Sample Spark job with Karpenter</span></h2>}>

Navigate to example directory and submit the Spark job.

```bash
cd data-on-eks/analytics/terraform/emr-eks-karpenter/examples/emr-spark-operator
kubectl apply -f pyspark-pi-job.yaml
```

Monitor the job status using the below command.
You should see the new nodes triggered by the karpenter and the YuniKorn will schedule one driver pod and 2 executor pods on this node.

```bash
kubectl get pods -n spark-team-a -w
```
</CollapsibleContent>

<CollapsibleContent header={<h2><span>Cleanup</span></h2>}>

This script will cleanup the environment using `-target` option to ensure all the resources are deleted in correct order.

```bash
cd analytics/terraform/emr-eks-karpenter && chmod +x cleanup.sh
./cleanup.sh
```
</CollapsibleContent>

:::caution

To avoid unwanted charges to your AWS account, delete all the AWS resources created during this deployment

:::
