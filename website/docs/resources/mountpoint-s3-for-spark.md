---
sidebar_position: 3
sidebar_label: Mounpoint-S3 for Spark Workloads
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../src/components/CollapsibleContent';

import CodeBlock from '@theme/CodeBlock';
import DaemonSetWithConfig from '!!raw-loader!../../../analytics/terraform/spark-k8s-operator/examples/mountpoint-s3-spark/mountpoint-s3-daemonset.yaml';

# Mountpoint-S3 for Spark Workloads
When working with the [SparkApplication](https://www.kubeflow.org/docs/components/spark-operator/user-guide/using-sparkapplication/) Custom Resource Definition (CRD) managed by the [SparkOperator](https://github.com/kubeflow/spark-operator), handling multiple dependency JAR files can become a significant challenge. Traditionally, these JAR files are bundled within the container image, leading to several inefficiencies:

* **Increased Build Time:** Downloading and adding JAR files during the build process significantly inflates the build time of the container image.
* **Larger Image Size:** Including JAR files directly in the container image increases its size, resulting in longer download times when pulling the image to execute jobs.
* **Frequent Rebuilds:** Any updates or additions to the dependency JAR files necessitate rebuilding and redeploying the container image, further increasing operational overhead.

[Mountpoint for Amazon S3](https://aws.amazon.com/s3/features/mountpoint/) offers an effective solution to these challenges. As an open-source file client, Mountpoint-S3 allows you to mount an S3 bucket on your compute instance, making it accessible as a local virtual file system. It automatically translates local file system API calls into REST API calls on S3 objects, providing seamless integration with Spark jobs.

## What is Mountpoint-S3?

[Mountpoint-S3](https://github.com/awslabs/mountpoint-s3) is an open-source file client developed by AWS that translates file operations into S3 API calls, enabling your applications to interact with [Amazon S3](https://aws.amazon.com/s3/) buckets as if they were local disks. [Mountpoint for Amazon S3](https://aws.amazon.com/s3/features/mountpoint/) is optimized for applications that need high read throughput to large objects, potentially from many clients at once, and to write new objects sequentially from a single client at a time. It offers significant performance gains compared to traditional S3 access methods, making it ideal for data-intensive workloads or AI/ML training.

[Mountpoint for Amazon S3](https://aws.amazon.com/s3/features/mountpoint/) is optimized for high-throughput performance, largely due to its foundation on the [AWS Common Runtime (CRT)](https://docs.aws.amazon.com/sdkref/latest/guide/common-runtime.html) library. The CRT library is a collection of libraries and modules designed to deliver high performance and low resource usage, specifically tailored for AWS services. Key features of the CRT library that enable high-throughput performance include:

 * **Efficient I/O Management:** The CRT library is optimized for non-blocking I/O operations, reducing latency and maximizing the utilization of network bandwidth.
 * **Lightweight and Modular Design:** The library is designed to be lightweight, with minimal overhead, allowing it to perform efficiently even under high load. Its modular architecture ensures that only the necessary components are loaded, further enhancing performance.
 * **Advanced Memory Management:** CRT employs advanced memory management techniques to minimize memory usage and reduce garbage collection overhead, leading to faster data processing and reduced latency.
 * **Optimized Network Protocols:** The CRT library includes optimized implementations of network protocols, such as HTTP/2, that are specifically tuned for AWS environments. These optimizations ensure rapid data transfer between S3 and your compute instances, which is critical for large-scale Spark workloads.

## Using Mountpoint-S3 with EKS
For Spark workloads, we'll specifically focus on **loading external JARs located in S3 for Spark Applications**. We’ll examine two primary deployment strategies for Mountpoint-S3;
1. Leveraging the [EKS Managed Addon CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html) with Persistent Volumes (PV) and Persistent Volume Claims (PVC)
2. Deploying Mountpoint-S3 at the Node level using either [USERDATA](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html) scripts or DaemonSets.

The first approach is considered mounting at a *Pod* level because the PV created is available to individual pods. The second Approach is considered mounting at a *Node* level because the S3 is mounted on the host Node itself. Each approach is discussed in detail below, highlighting their respective strengths and considerations to help you determine the most effective solution for your specific use case.

| Metric              | Pod Level | Node Level |
| :----------------: | :------ | :---- |
| Access Control            |   Provides fine-grained access control through service roles and RBAC, limiting PVC access to specific Pods. This is not possible with host-level mounts, where the mounted S3 bucket is accessible to all Pods on the Node.   | Simplifies configuration but lacks the granular control offered by Pod-level mounting. |
| Scalabbility and Overhead |   Involves managing individual PVCs, which can increase overhead in large-scale environments.   | Reduces configuration complexity but provides less isolation between Pods. |
| Performance Considerations|  Offers predictable and isolated performance for individual Pods.   | May lead to contention if multiple Pods on the same Node access the same S3 bucket. |
| Flexibility and Use Cases |  Best suited for use cases where different Pods require access to different datasets or where strict security and compliance controls are necessary.   | Ideal for environments where all Pods on a Node can share the same dataset, such as when running batch processing jobs or Spark jobs that require common dependencies. |

## Resource Allocation
Before being able to implement the Mountpoint-s3 solution provided, AWS cloud resources need to be allocated. To do deploy the Terraform stack following the instructions below. After allocating the resources and setting up the EKS environment, you can explore the two different approaches of utilizing Mountpoint-S3 in detail.

<CollapsibleContent header={<h2><span>Deploy Solution Resources</span></h2>}>

In this [example](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/spark-k8s-operator), you will provision the following resources required to run Spark Jobs with open source Spark Operator.

This example deploys an EKS Cluster running the Spark K8s Operator into a new VPC.

- Creates a new sample VPC, 2 Private Subnets and 2 Public Subnets
- Creates Internet gateway for Public Subnets and NAT Gateway for Private Subnets
- Creates EKS Cluster Control plane with public endpoint (for demo reasons only) with core managed Node group, on-demand Node group and Spot Node group for Spark workloads.
- Deploys Metrics server, Cluster Autoscaler, Spark-k8s-operator, Apache Yunikorn, Karpenter, Grafana, AMP and Prometheus server.

### Prerequisites

Ensure that you have installed the following tools on your machine.

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### Deploy

Clone the repository.

```bash
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks
export DOEKS_HOME=$(pwd)
```

If DOEKS_HOME is ever unset, you can always set it manually using `export
DATA_ON_EKS=$(pwd)` from your data-on-eks directory.

Navigate into one of the example directories and run `install.sh` script.

```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator
chmod +x install.sh
./install.sh
```

Now create an S3_BUCKET variable that holds the name of the bucket created
during the install. This bucket will be used in later examples to store output
data. If S3_BUCKET is ever unset, you can run the following commands again.

```bash
export S3_BUCKET=$(terraform output -raw s3_bucket_id_spark_history_server)
echo $S3_BUCKET
```

</CollapsibleContent>

## Approach 1: Deploy Mountpoint-S3 on EKS at *Pod level*

Deploying Mountpoint-S3 at the Pod level involves using the [EKS Managed Addon CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html) with Persistent Volumes (PV) and Persistent Volume Claims (PVC) to mount an S3 bucket directly within a Pod. This method allows for fine-grained control over which Pods can access specific S3 buckets, ensuring that only the necessary workloads have access to the required data.

Once [Mountpoint-S3](https://github.com/awslabs/mountpoint-s3) is enabled and the PV is created, the S3 bucket becomes a cluster-level resource, allowing any Pod to request access by creating a PVC that references the PV. To achieve fine-grained control over which Pods can access specific PVCs, you can use service roles within namespaces. By assigning specific service accounts to Pods and defining Role-Based Access Control (RBAC) policies, you can limit which Pods can bind to certain PVCs. This ensures that only authorized Pods can mount the S3 bucket, providing tighter security and access control compared to a host-level mount, where the hostPath is accessible to all Pods on the Node.

Using this approach can also be simplified using the [EKS Managed Addon CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html). However, this does not support taints/tolerations and therefore cannot be used with GPUs. Additionally, because the Pods are not sharing the mount and therefore not sharing the cache it would lead to more S3 API calls.

 For more information on how to deploy this approach refer to the [deployment instructions](https://awslabs.github.io/data-on-eks/docs/resources/mountpoint-s3)

## Approach 2:  Deploy Mountpoint-S3 on EKS at *Node level*

Mounting a S3 Bucket at a Node level can streamline the management of dependency JAR files for SparkApplications by  reducing build times and speeding up deployment. It can be implemented using either **USERDATA** or **DaemonSet.** USERDATA is the preferred method for implementing [Mountpoint-S3](https://github.com/awslabs/mountpoint-s3). However, if you have static Nodes in your EKS cluster that you cannot bring down, the DaemonSet approach provides an alternative. Make sure to understand all of the security mechanisms that need to be enabled in order to utilize the DaemonSet approach before implementing it.

### Approach 2.1: Using USERDATA

This approach is recommended for new clusters or where auto-scaling is customized to run workloads as the user-data script is run when a Node is initialized. Using the below script, the Node can be updated to have the S3 bucket mounted upon initialization in the EKS cluster that hosts the Pods. The below script outlines downloading, installing, and running the Mountpoint S3 package. There are a couple of arguments that are set for this application and defined below that can be altered depending on the use case. More information about these arguments and others can be found [here](https://github.com/awslabs/mountpoint-s3/blob/main/doc/CONFIGURATION.md#caching-configuration)

* metadata-ttl: this is set to indefinite because the jar files are meant to be used as read only and will not change.
* allow-others: this is set so that the Node can have access to the mounted volume when using SSM
* cache: this is set to enable caching and limit the S3 API calls that need to be made by storing the files in cache for consecutive re-reads.

:::note
These same arguments can also be used in the DaemonSet approach. In addition to these arguments that are set by this example, there are also a number of other options for additional [logging and debugging](https://github.com/awslabs/mountpoint-s3/blob/main/doc/LOGGING.md)
:::

When autoscaling with [Karpenter](https://karpenter.sh/), this method allows for more flexibility and performance. For example when configuring Karpenter in the terraform code, the user data for different types of Nodes can be unique with different buckets depending on the workload so when Pods are scheduled and need a certain set of dependencies, Taints and Tolerations will allow Karpenter to allocate the specific instance type with the unique user data to ensure the correct bucket with the dependent files is mounted on the Node so that Pods can access is. Additionally, the user script will depend on the OS that the newly allocated Node is configured with.

#### USERDATA script:

```
#!/bin/bash
yum update -y
yum install -y wget
wget https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.rpm
yum install -y mount-s3.rpm mkdir -p /mnt/s3
/opt/aws/mountpoint-s3/bin/mount-s3 --metadata-ttl indefinite --allow-other --cache /tmp <S3_BUCKET_NAME> /mnt/s3
```

### Approach 2.2: Using DaemonSet

This approach is recommended for existing clusters. This approach is made up of 2 resources, a ConfigMap with a script that maintains the S3 Mount Point package onto the Node and a DaemonSet that runs a Pod on every Node in the cluster which will execute the script on the Node.

The ConfigMap script will run a loop to check the mountPoint every 60 seconds and remount it if there are any issues. There are multiple environment variables that can be altered for the mount location, cache location, S3 bucket name, log file location, and the URL of the package installation and the location of the of the installed package. These variables can be left as default as only the S3 bucket name is required to run.

The DaemonSet Pods will copy the script onto the Node, alter the permissions to allow execution, and then finally run the script. The Pod installs ```util-linux``` in order to have access to [nsenter](https://man7.org/linux/man-pages/man1/nsenter.1.html), which allows the Pod to execute the script in the Node space which allows the S3 Bucket to be mounted on to the Node directly by the Pod.
:::danger
The DaemonSet Pod requires the ```securityContext``` to be privileged as well as ```hostPID```, ```hostIPC```, and ```hostNetwork``` to be set to true.
Review below why these are required to be configured for this solution and their security implications.
:::
1. ```securityContext: privileged```
    * **Purpose:** privileged mode gives the container full access to all host resources, similar to root access on the host.
    * To install software packages, configure the system, and mount the S3 bucket onto the host, your container will likely need elevated permissions. Without privileged mode, the container might not have sufficient permissions to perform these actions on the host filesystem and network interfaces.
2. hostPID
    * **Purpose:** nsenter allows you to enter various namespaces, including the PID namespace of the host.
    * When using nsenter to enter the host’s PID namespace, the container needs access to the host’s PID namespace. Thus, enabling ```hostPID: true``` is necessary to interact with processes on the host, which is crucial for operations like installing packages or running commands that require host-level process visibility like mountpoint-s3.
3. hostIPC
    * **Purpose:** hostIPC enables your container to share the host’s inter-process communication namespace, which includes shared memory.
    * If nsenter commands or the script to run involves shared memory or other IPC mechanisms on the host, ```hostIPC: true``` will be necessary. While it’s less common than hostPID, it’s often enabled alongside it when nsenter is involved, especially if the script needs to interact with host processes that rely on IPC.
4. hostNetwork
    * **Purpose:** hostNetwork allows the container to use the host’s network namespace, giving the container access to the host’s IP address and network interfaces.
    * During the installation process, the script will likely need to download packages from the internet (e.g., from repositories hosting the mountpoint-s3 package). By enabling hostNetwork with ```hostNetwork: true```, you ensure that the download processes have direct access to the host’s network interface, avoiding issues with network isolation.
:::warning
This sample code uses the ```spark-team-a``` namespace to run the job and host the DaemonSet. This is primarily because the Terraform stack already sets up [IRSA](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/setting-up-enable-IAM.html) for this namespace and allows the service account to access any S3 bucket.
When using in production make sure create your own separate namespace, service account, and IAM role that follows the policy of least-privilege permissions and follows [IAM role best practice](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
:::

<details>
<summary> To view the DaemonSet, Click to toggle content!</summary>

<CodeBlock language="yaml">{DaemonSetWithConfig}</CodeBlock>
</details>


## Executing Spark Job
Here are the steps to test the scenario using Approach 2 with DaemonSet:

1. Deploy [Spark Operator Resources](#resource-allocation)
2. Prepare the S3 Bucket
    1. ``` cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator/examples/mountpoint-s3-spark/ ```
    2. ``` chmod +x copy-jars-to-s3.sh ```
    3. ``` ./copy-jars-to-s3.sh ```
3. Set-up Kubeconfig
    1. ```aws eks update-kubeconfig --name spark-operator-doeks```
4. Apply DaemonSet
    1. ```kubectl apply -f mountpoint-s3-daemonset.yaml ```
4. Apply Spark Job sample
    1. 1. ```kubectl apply -f mountpoint-s3-spark-job.yaml ```
4. View Job Running
    * There are a couple different resources of which we can view logs of as this SparkApplication CRD is running. Each of these logs should be in a separate terminal to view all of the logs simultaneously.
        1. **spark operator**
            1. ``` kubectl -n spark-operator get pods```
            2. copy the name of the spark operator pod
            2. ``` kubectl -n spark-operator logs -f <POD_NAME>```
        2. **spark-team-a Pods**
            1. In order to get the logs for the driver and exec Pods for the SparkApplication, we need to first verify that the Pods are running. Using wide output we should be able to see the Node that the Pods are running on and using ```-w``` we can see the status updates for each of the Pods.
            2. ``` kubectl -n spark-team-a get pods -o wide -w ```
        3. **driver Pod**
            1. Once the driver Pod is in the running state, which will be visible in the previous terminal, we can get the logs for the driver Pod
            2. ``` kubectl -n spark-team-a logs -f taxi-trip ```
        4. **exec Pod**
            1. Once the exec Pod is in the running state which will be visible in the previous terminal, we can get the logs for the exec Pod. Make sure that the exec-1 is running before getting the logs, otherwise use another exec Pod that is in the running state.
            2. 2. ``` kubectl -n spark-team-a logs -f taxi-trip-exec-1 ```


## Verification
Once the job is done running you can see in the exec logs that the files are being copied from the local mountpoint-s3 location on the Node to the spark Pod in order to do the processing.
```
24/08/13 00:08:46 INFO Utils: Copying /mnt/s3/jars/hadoop-aws-3.3.1.jar to /var/data/spark-5eae56b3-3999-4c2f-8004-afc46d1c82ba/spark-a433e7ce-db5d-4fd5-b344-abf751f43bd3/-14716855631723507720806_cache
24/08/13 00:08:46 INFO Utils: Copying /var/data/spark-5eae56b3-3999-4c2f-8004-afc46d1c82ba/spark-a433e7ce-db5d-4fd5-b344-abf751f43bd3/-14716855631723507720806_cache to /opt/spark/work-dir/./hadoop-aws-3.3.1.jar
24/08/13 00:08:46 INFO Executor: Adding file:/opt/spark/work-dir/./hadoop-aws-3.3.1.jar to class loader
24/08/13 00:08:46 INFO Executor: Fetching file:/mnt/s3/jars/aws-java-sdk-bundle-1.12.647.jar with timestamp 1723507720806
24/08/13 00:08:46 INFO Utils: Copying /mnt/s3/jars/aws-java-sdk-bundle-1.12.647.jar to /var/data/spark-5eae56b3-3999-4c2f-8004-afc46d1c82ba/spark-a433e7ce-db5d-4fd5-b344-abf751f43bd3/14156613201723507720806_cache
24/08/13 00:08:47 INFO Utils: Copying /var/data/spark-5eae56b3-3999-4c2f-8004-afc46d1c82ba/spark-a433e7ce-db5d-4fd5-b344-abf751f43bd3/14156613201723507720806_cache to /opt/spark/work-dir/./aws-java-sdk-bundle-1.12.647.jar
```
Additionally, when viewing status of the spark-team-a Pods, you would notice that another Node comes online, this Node is is optimized to the run the SparkApplication and as soon as it comes online the DaemonSet Pod will also spin up and start running on the new Node so that any Pods that are run that new Node will also have access to the S3 Bucket. Using Systems Sessions Manager (SSM), you can connect any of the Nodes and verify the that the mountpoint-s3 package has been downloaded and installed by running:
* ```mount-s3 --version```

The largest advantage to using the mountpoint-S3 on the Node level for multiple Pods is that the data can be cached to allow other Pods to access the same data without having to make their own API calls. Once the *karpenter-spark-compute-optimized* optimized Node is allocated you can use Sessions Manager (SSM) to connect to the Node and verify that the files will be cached on the Node when the job is run and the volume is mounted. you can see the cache at:
* ```sudo ls /tmp/mountpoint-cache/```

## Conclusion

By leveraging the CRT library, Mountpoint for Amazon S3 can deliver the high throughput and low latency needed to efficiently manage and access large volumes of data stored in S3. This allows dependency JAR files to be stored and managed externally from the container image, decoupling them from the Spark jobs. Additionally, storing JARs in S3 enables multiple Pods to consume them, leading to cost savings as S3 provides a cost-effective storage solution compared to larger container images. S3 also offers virtually unlimited storage, making it easy to scale and manage dependencies.

Mountpoint-S3 offers a versatile and powerful way to integrate S3 storage with EKS for data and AI/ML workloads. Whether you choose to deploy it at the Pod level using PVs and PVCs, or at the Node level using USERDATA or DaemonSets, each approach has its own set of advantages and trade-offs. By understanding these options, you can make informed decisions to optimize your data and AI/ML workflows on EKS.
