---
title: Spark Operator on EKS with IPv6
sidebar_position: 3
---

This example showcases the usage of Spark Operator running on Amazon EKS in IPv6 mode. the idea is to show and demonstarte running spark workloads on EKS IPv6 cluster.

## Deploy the EKS Cluster with all the add-ons and infrastructure needed to test this example

The Terraform blueprint will provision the following resources required to run Spark Jobs with open source Spark Operator on Amazon EKS IPv6

* A Dual Stack Amazon Virtual Private Cloud (Amazon VPC) with 3 Private Subnets and 3 Public Subnets
* An Internet gateway for Public Subnets, NAT Gateway for Private Subnets and Egress-only Internet gateway
* An Amazon EKS cluster in IPv6 mode (version 1.30)
* Amazon EKS core-managed node group used to host some of the add-ons that we’ll provision on the cluster
* Deploys Spark-k8s-operator, Apache Yunikorn, Karpenter, Prometheus and Grafana server.

### Prerequisites

Ensure that you have installed the following tools on your machine.

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

Before installing the cluster create a EKS IPv6 CNI policy. Follow the instructions from the link:
[AmazonEKS_CNI_IPv6_Policy ](https://docs.aws.amazon.com/eks/latest/userguide/cni-iam-role.html#cni-iam-role-create-ipv6-policy)

### Clone the repository

```bash
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks
export DOEKS_HOME=$(pwd)
```

### Initialize Terraform

Navigate into the example directory and run the initialization script `install.sh`.

```bash
cd ${DOEKS_HOME}/analytics//terraform/spark-eks-ipv6/
chmod +x install.sh
./install.sh
```

### Export Terraform Outputs

```bash
export CLUSTER_NAME=$(terraform output -raw cluster_name)
export AWS_REGION=$(terraform output -raw region)
export S3_BUCKET=$(terraform output -raw s3_bucket_id_spark_event_logs_example_data)
```

The S3_BUCKET variable that holds the name of the bucket created
during the install. This bucket will be used in later examples to store output
data.

### Update kubeconfig

Update the kubeconfig to verify the deployment.

```bash
aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME
```

### Verify the deployment

Examine the IP addresses assigned to the cluster nodes and the pods. You will notice that both have IPv6 addresses allocated.

```bash
kubectl get node -o custom-columns='NODE_NAME:.metadata.name,INTERNAL-IP:.status.addresses[?(@.type=="InternalIP")].address'
NODE_NAME                                 INTERNAL-IP
ip-10-1-0-212.us-west-2.compute.internal  2600:1f13:520:1303:c87:4a71:b9ea:417c
ip-10-1-26-137.us-west-2.compute.internal 2600:1f13:520:1304:15b2:b8a3:7f63:cbfa
ip-10-1-46-28.us-west-2.compute.internal  2600:1f13:520:1305:5ee5:b994:c0c2:e4da
```

```bash
kubectl get pods -A -o custom-columns='NAME:.metadata.name,NodeIP:.status.hostIP,PodIP:status.podIP'
NAME                                                     NodeIP                                  PodIP
....
karpenter-5fd95dffb8-l8j26                               2600:1f13:520:1304:15b2:b8a3:7f63:cbfa  2600:1f13:520:1304:a79b::
karpenter-5fd95dffb8-qpv55                               2600:1f13:520:1303:c87:4a71:b9ea:417c   2600:1f13:520:1303:60ac::
kube-prometheus-stack-grafana-9f5c9d8fc-zgn98            2600:1f13:520:1304:15b2:b8a3:7f63:cbfa  2600:1f13:520:1304:a79b::a
kube-prometheus-stack-kube-state-metrics-98c74d866-56275 2600:1f13:520:1304:15b2:b8a3:7f63:cbfa  2600:1f13:520:1304:a79b::9
kube-prometheus-stack-operator-67df8bc57d-2d8jh          2600:1f13:520:1304:15b2:b8a3:7f63:cbfa  2600:1f13:520:1304:a79b::b
kube-prometheus-stack-prometheus-node-exporter-5qrqs     2600:1f13:520:1303:c87:4a71:b9ea:417c   2600:1f13:520:1303:c87:4a71:b9ea:417c
kube-prometheus-stack-prometheus-node-exporter-hcpvk     2600:1f13:520:1304:15b2:b8a3:7f63:cbfa  2600:1f13:520:1304:15b2:b8a3:7f63:cbfa
kube-prometheus-stack-prometheus-node-exporter-ztkdm     2600:1f13:520:1305:5ee5:b994:c0c2:e4da  2600:1f13:520:1305:5ee5:b994:c0c2:e4da
prometheus-kube-prometheus-stack-prometheus-0            2600:1f13:520:1304:15b2:b8a3:7f63:cbfa  2600:1f13:520:1304:a79b::7
spark-history-server-6c9f9d7cc4-xzj4c                    2600:1f13:520:1305:5ee5:b994:c0c2:e4da  2600:1f13:520:1305:64b::1
spark-operator-84c6b48ffc-z2glj                          2600:1f13:520:1304:15b2:b8a3:7f63:cbfa  2600:1f13:520:1304:a79b::5
spark-operator-webhook-init-kbl4s                        2600:1f13:520:1305:5ee5:b994:c0c2:e4da  2600:1f13:520:1305:64b::2
yunikorn-admission-controller-d675f89c5-f2p47            2600:1f13:520:1303:c87:4a71:b9ea:417c   2600:1f13:520:1303:c87:4a71:b9ea:417c
yunikorn-scheduler-59d6879975-2rh4d                      2600:1f13:520:1304:15b2:b8a3:7f63:cbfa  2600:1f13:520:1304:a79b::4
....
```

### Execute Sample Spark job with Karpenter

Navigate to example directory and submit the Spark job.

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-eks-ipv6/examples/karpenter
kubectl apply -f pyspark-pi-job.yaml
```

Monitor the job status using the below command. You should see the new nodes triggered by the Karpenter.

```bash
kubectl get pods -n spark-team-a -w
```

### Apache YuniKorn Gang Scheduling with NVMe based SSD disk for shuffle storage

Gang Scheduling Spark jobs using Apache YuniKorn and Spark Operator

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-eks-ipv6/examples/karpenter/nvme-yunikorn-gang-scheduling
```

Run the `taxi-trip-execute.sh` script with the following input. You will use the `S3_BUCKET` variable created earlier. Additionally, you must change YOUR_REGION_HERE with the region of your choice, us-west-2 for example.

This script will download some example taxi trip data and create duplicates of it in order to increase the size a bit. This will take a bit of time and will require a relatively fast internet connection.

```bash
${DOEKS_HOME}/analytics/scripts/taxi-trip-execute.sh ${S3_BUCKET} YOUR_REGION_HERE
```

Once our sample data is uploaded you can run the Spark job. You will need to replace the `<S3_BUCKET>` placeholders in this file with the name of the bucket created earlier. You can get that value by running echo $S3_BUCKET.

To do this automatically you can run the following, which will create a .old backup file and do the replacement for you.

```bash
sed -i.old s/\<S3_BUCKET\>/${S3_BUCKET}/g ./nvme-storage-yunikorn-gang-scheduling.yaml
```

Now that the bucket name is in place you can create the Spark job.

```bash
kubectl apply -f nvme-storage-yunikorn-gang-scheduling.yaml
```

## Cleanup

This script will cleanup the environment using `-target` option to ensure all the resources are deleted in correct order.

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-eks-ipv6 && chmod +x cleanup.sh
./cleanup.sh
```

:::caution
To avoid unwanted charges to your AWS account, delete all the AWS resources created during this deployment
:::
