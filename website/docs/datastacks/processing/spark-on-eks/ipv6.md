---
title: IPv6 Networking
sidebar_position: 13
---

This guide explains how to deploy and run Apache Spark on an IPv6-enabled Amazon EKS cluster.

:::info Prerequisites
This guide assumes you have cloned the `data-on-eks` repository and deployed the Spark stack.
:::

---

## Step 1: Enable IPv6 in Terraform

To deploy an IPv6-enabled cluster, open the `data-stacks/spark-on-eks/terraform/data-stack.tfvars` file and set the `enable_ipv6` variable to `true`.

```hcl title="data-stacks/spark-on-eks/terraform/data-stack.tfvars"
enable_ipv6 = true
```

Setting this variable to `true` automatically configures the following:

*   **EKS Cluster:** The EKS cluster and its networking components are provisioned with an IPv6 CIDR block.
*   **Spark Operator:** The Spark Operator controller is configured with the necessary JVM arguments (`-Djava.net.preferIPv6Addresses=true`) to ensure it communicates over IPv6.

After enabling the setting, run the deployment script from the `data-stacks/spark-on-eks` directory:

```bash
./deploy.sh
```

---

## Step 2: Verify the Deployment (Optional)

Once deployment is complete, you can verify that the cluster is running in IPv6 mode.

<details>
<summary>Click to see verification commands</summary>

You can check the internal IP addresses of your Kubernetes nodes. The output should show IPv6 addresses in the `INTERNAL-IP` column.
```bash
kubectl get node -o custom-columns='NODE_NAME:.metadata.name,INTERNAL-IP:.status.addresses[?(@.type=="InternalIP")].address'

# example output
NODE_NAME                                 INTERNAL-IP
ip-10-1-0-212.us-west-2.compute.internal  2600:1f13:520:1303:c87:4a71:b9ea:417c
ip-10-1-26-137.us-west-2.compute.internal 2600:1f13:520:1304:15b2:b8a3:7f63:cbfa
ip-10-1-46-28.us-west-2.compute.internal  2600:1f13:520:1305:5ee5:b994:c0c2:e4da
```

You can also inspect pod IPs to confirm they are receiving IPv6 addresses.
```bash
kubectl get pods -A -o custom-columns='NAME:.metadata.name,NodeIP:.status.hostIP,PodIP:status.podIP'

# example output
NAME                                                     NodeIP                                  PodIP
karpenter-5fd95dffb8-l8j26                               2600:1f13:520:1304:15b2:b8a3:7f63:cbfa  2600:1f13:520:1304:a79b::
karpenter-5fd95dffb8-qpv55                               2600:1f13:520:1303:c87:4a71:b9ea:417c   2600:1f13:520:1303:60ac::
```

</details>

---

## Step 3: Configure Spark Jobs for IPv6

The example manifest at `data-stacks/spark-on-eks/examples/pyspark-pi-job.yaml` includes the required IPv6 settings commented out. You must uncomment them for your jobs.

#### A. Update SparkConf for the Driver Service

This ensures the Spark driver's network service gets an IPv6 address, allowing executors to connect to it.

```yaml title="pyspark-pi-job.yaml"
spec:
  sparkConf:
    # ...
    # ipv6 configurations
    "spark.kubernetes.driver.service.ipFamilies": "IPv6"
    "spark.kubernetes.driver.service.ipFamilyPolicy": "SingleStack"
```

#### B. Configure IMDS Endpoint for Driver and Executors

This is critical for allowing Spark to securely access other AWS services like Amazon S3.

:::info What is IMDS and Why is This Needed?

The EC2 Instance Metadata Service (IMDS) is a service available on all EC2 instances that provides data about the instance, such as its ID, and is also used to fetch temporary AWS credentials for accessing services like Amazon S3.

By default, AWS SDKs connect to IMDS using its fixed IPv4 endpoint (`http://169.254.169.254`). In an IPv6 cluster, pods may be in a network environment where they cannot reach this IPv4 address.

Setting the `AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE` environment variable to `IPv6` instructs the AWS SDK to use the IPv6 endpoint (`http://[fd00:ec2::254]`) instead. This feature is only supported on **Nitro-based EC2 instances**.
:::

You must set this environment variable for both the driver and executor pods.

```yaml title="pyspark-pi-job.yaml"
spec:
  driver:
    # ...
    # instruct java sdk to use ipv6 when talking to the IMDS
    env:
      - name: AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE
        value: IPv6
---
spec:
  executor:
    # ...
    # instruct java sdk to use ipv6 when talking to the IMDS
    env:
      - name: AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE
        value: IPv6
```

:::caution
If you do not configure the IMDS endpoint, any Spark job that interacts with Amazon S3 will fail with an authentication error.
:::

---

## Cleanup

To avoid ongoing charges, clean up the resources by following the instructions in the main [Infrastructure Deployment Guide](./infra.md#cleanup). The same process applies to both IPv4 and IPv6 deployments.
