---
sidebar_position: 3
sidebar_label: Spark on EKS Best Practices
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../src/components/CollapsibleContent';

# Spark on EKS Best Practices

This page aims to provide comprehensive best practices and guidelines for deploying, managing, and optimizing Apache Spark workloads on Amazon Elastic Kubernetes Service (EKS). This helps organizations to successfully run and scale their Spark Applications at scale in a containerised environment on Amazon EKS.

For deploying Spark on EKS you can leverage the [blueprints](https://awslabs.github.io/data-on-eks/docs/blueprints/data-analytics/spark-operator-yunikorn), which readily incorporates most of the best practices. You can further customize this blueprint, to tweak the configurations to match your specific application requirements and environment constraints, as outlined in this guide.

## EKS Networking
### VPC and Subnets Sizing
#### VPC IP address exhaustion

As EKS clusters scale up with additional Spark workloads, the number of pods managed by a cluster can easily grow into the thousands, each consuming an IP address. This creates challenges, since IP addresses within a VPC are limited, and it's not always feasible to recreate a larger VPC or extend the current VPC's CIDR blocks.

Worker nodes and pods both consume IP addresses. By default, VPC CNI has `WARM_ENI_TARGET=1` means that `ipamd` should keep "a full ENI" of available IPs around in the `ipamd` warm pool for the Pod IP assignment.

#### Remediation for IP Address exhaustion
While IP exhaustion remediation methods exist for VPCs, they introduce additional operational complexity and have significant implications to consider. Hence, for new EKS clusters, it is recommended to over-provision the subnets you will use for Pod networking for growth.

For addressing IP address exhaustion, consider adding secondary CIDR blocks to your VPC and creating new subnets from these additional address ranges, then deploying worker nodes in these expanded subnets.

If adding more subnets, is not an option, then you will have to work on optimising the IP address assignment by tweaking CNI Configuration Variables. Refer to [configure MINIMUM_IP_TARGET](/docs/bestpractices/networking#avoid-using-warm_ip_target-in-large-clusters-or-cluster-with-a-lot-of-churn).


### CoreDNS Recommendations
#### DNS Lookup Throttling
Spark applications running on Kubernetes generate high volumes of DNS lookups when executors communicate with external services.

This occurs because Kubernetes' DNS resolution model requires each pod to query the cluster's DNS service (kube-dns or CoreDNS) for every new connection, and during task executions Spark executors frequently create new connections for communicating with external services. By default, Kubernetes does not cache DNS results at the pod level, meaning each executor pod must perform a new DNS lookup even for previously resolved hostnames.

This behavior is amplified in Spark applications due to their distributed nature, where multiple executor pods simultaneously attempt to resolve the same external service endpoints.This occurs during data ingestion, processing, and when connecting to external databases or shuffle services.

When DNS traffic exceeds 1024 packets per second for a CoreDNS replica, DNS requests will be throttled, resulting in `unknownHostException` errors.

#### Remediation
It is recommended to scale CoreDNS, as your workload scales. Refer to [Scaling CoreDNS](/docs/bestpractices/networking#scaling-coredns) for more details on implementation choices.

It is also recommended to continuously monitor CoreDNS metrics. Refer to [EKS Networking Best Practices](https://docs.aws.amazon.com/eks/latest/best-practices/monitoring_eks_workloads_for_network_performance_issues.html#_monitoring_coredns_traffic_for_dns_throttling_issues) for detailed information.


### Reduce Inter AZ Traffic

#### Inter AZ Costs
During the shuffle stage, Spark executors may need to exchange data between them. If the Pods are spread across multiple Availability Zones (AZs), this shuffle operation can turn out to be very expensive, especially on Network I/O front, which will be charged as Inter-AZ Traffic costs.

#### Remediation
For Spark workloads, it is recommended to colocate executor pods and worker nodes in the same AZ. Colocating workloads in the same AZ serves two main purposes:
* Reduce inter-AZ traffic costs
* Reduce network latency between executors/Pods

Refer to [Inter AZ Network Optimization](/docs/bestpractices/networking#inter-az-network-optimization) for having pods co-locate on the same AZ.

## Karpenter Recommendations

[Karpenter](https://karpenter.sh/docs/) enhances Spark on EKS deployments by providing rapid node provisioning capability that aligns with Spark's dynamic resource scaling needs. This automated scaling solution improves resource utilization and cost-efficiency by bringing in right-sized nodes as needed. This also allows Spark jobs to scale seamlessly without the need for pre-configured node groups or manual intervention, there by simplifying operational management.

Here are the Karpenter recommendations for scaling compute nodes while running Spark workloads. For complete Karpenter configuration details, refer [Karpenter documentation](https://karpenter.sh/docs/).

Consider creating separate NodePools for driver and executor pods.

### Driver Nodepool
The Spark driver is a single pod and manages the entire lifecycle of the Spark application. Terminating Spark driver pod, effectively means terminating the entire Spark job.
* Configure Driver Nodepool to always use `on-demand` nodes only. When Spark driver pods run on spot instances, they are vulnerable to unexpected terminations due to spot instance reclamation, resulting in computation loss and interrupted processing that requires manual intervention to restart.
* Disable [`consolidation`](https://karpenter.sh/docs/concepts/disruption/#consolidation) on Driver Nodepool.
* Use `node selectors` or `taints/tolerations` for placing driver pods on this designated Driver NodePool.

### Executor Nodepool
#### Configure Spot instances
In the absence of [Amazon EC2 Reserved Instances](https://aws.amazon.com/ec2/pricing/reserved-instances/) or [Savings Plans](https://aws.amazon.com/savingsplans/), consider using [Amazon EC2 Spot Instances](https://aws.amazon.com/ec2/spot/) for executors to reduce dataplane costs.

When spot instances are interrupted, executors will be terminated and rescheduled on available nodes. For details on interruption behaviour and node termination management, refer to the `Handling Interruptions` section.

#### Instance and Capacity type selection

Using multiple instance types in the node pool enables access to various spot instance pools, increasing capacity availability and optimizing for both price and capacity across the available instance options.

With `Weighted Nodepools`, node selection can be optimized using weighted nodepools arranged in priority order. By assigning different weights to each nodepool, you can establish a selection hierarchy, such as: Spot (highest weight), followed by Graviton, AMD, and Intel (lowest weight).

#### Consolidation Configuration
While enabling `consolidation` for Spark executor pods can lead to better cluster resource utilization, it's crucial to strike a balance with job performance. Frequent consolidation events can result in slower execution times for Spark jobs, as executors are forced to recompute the shuffle data and RDD blocks.

This impact is particularly noticeable in long-running Spark jobs. To mitigate this, it's essential to carefully tune the consolidation interval.

Enable graceful executor pods shutdown:
* `spark.executor.decommission.enabled=true`: Enables graceful decommissioning of executors, allowing them to complete their current tasks and transfer their cached data before shutting down. This is particularly useful when using spot instances for executors.

* `spark.storage.decommission.enabled=true`: Enables the migration of cached RDD blocks from the decommissioning executor to other active executors before shutdown, preventing data loss and the need for recomputation.


To explore other means to save intermediate data computed in Spark Executors, refer to [Storage Best Practices](#storage-best-practices).

#### Handling interruptions during Karpenter Consolidation/Spot Termination

Perform controlled decommissioning instead of abruptly killing executors when nodes are scheduled for termination. To achieve this:
* Configure appropriate TerminationGracePeriod values for Spark workloads.
* Implement executor-aware termination handling.
* Ensure shuffle data is saved before nodes are decommissioned.

Spark provides native configurations to control termination behavior:

**Controlling executor interruptions**
* **Configs**:
* `spark.executor.decommission.enabled`
* `spark.executor.decommission.forceKillTimeout`
These configurations are particularly useful in scenarios where executors might be terminated due to spot instance interruptions or Karpenter consolidation events. When enabled, executors will gracefully shutdown by stopping task acceptance and notifying the driver about their decommissioning state.

**Controlling executor's BlockManager behavior**
* **Configs**:
* `spark.storage.decommission.enabled`
* `spark.storage.decommission.shuffleBlocks.enabled`
* `spark.storage.decommission.rddBlocks.enabled`
* `spark.storage.decommission.fallbackStorage.path`
These settings enable the migration of shuffle and RDD blocks from decommissioning executors to other available executors or to a fallback storage location. This approach helps in dynamic environments by reducing the need to recompute shuffle data or RDD blocks, thereby improving job completion times and resource efficiency.

## Advanced Scheduling Considerations
### Default Kubernetes Scheduler behaviour.

Default Kubernetes scheduler uses `least allocated` approach. This strategy aims to distribute pods evenly across cluster, which helps in maintaining availability and a balanced resource utilization across all nodes, rather than packing more pods in fewer nodes.

`Most allocated` approach on the other hand, aims to favor nodes with most amount of allocated resources, which leads to packing more pods onto nodes that are already heavily allocated. This approach is favourable for Spark jobs, as it aims for high utilization on select nodes at pod scheduling time, leading to better consolidation of nodes. You will have to leverage a custom kube-scheduler with this option enabled, or leverage Custom Schedulers purpose built for more advanced orchestration.

### Custom Schedulers

Custom schedulers enhance Kubernetes’ native scheduling capabilities by providing advanced features tailored for batch and high-performance computing workloads. Custom schedulers enhance resource allocation by optimizing bin-packing and offering scheduling tailored to specific application needs. Here are popular custom schedulers for running Spark workloads on Kubernetes.
* [Apache Yunikorn](https://yunikorn.apache.org/)
* [Volcano](https://volcano.sh/en/)

Advantages of leveraging custom schedulers like Yunikorn.
* Hierarchical queue system and configurable policies allowing for complex resource management.
* Gang scheduling, which ensures all related pods (like Spark executors) start together, preventing resource wastage.
* Resource fairness across different tenants and workloads.


### How will Yunikorn and Karpenter work together?

Karpenter and Yunikorn complement each other by handling different aspects of workload management in Kubernetes:

* **Karpenter** focuses on node provisioning and scaling, determining when to add or remove nodes based on resource demands.

* **Yunikorn** brings application awareness to scheduling through advanced features like queue management, resource fairness, and gang scheduling.

In a typical workflow, Yunikorn first schedules pods based on application-aware policies and queue priorities. When these pods remain pending due to insufficient cluster resources, Karpenter detects these pending pods and provisions appropriate nodes to accommodate them. This integration ensures both efficient pod placement (Yunikorn) and optimal cluster scaling (Karpenter).

For Spark workloads, this combination is particularly effective: Yunikorn ensures executors are scheduled according to application SLAs and dependencies, while Karpenter ensures the right node types are available to meet those specific requirements.


## Storage Best Practices
### Node Storage
By default, the EBS root volumes of worker nodes are set to 20GB. Spark Executors use local storage for temporary data like shuffle data, intermediate results, and temporary files. This default storage of 20GB root volume attached to worker nodes can be limiting in both size and performance. Consider the following options to address your performance and storage size requirements:
* Expand the root volume capacity to provide ample space for intermediate Spark data. You will have to arrive at optimal capacity based on average size of the dataset that each executor will be processing and complexity of Spark job.
* Configure high-performance storage with better I/O and latency.
* Mount additional volumes on worker nodes for temporary data storage.
* Leverage dynamically provisioned PVCs that can be attached directly to executor pods.

### Reuse PVC
This option allows reusing PVCs associated with Spark executors even after the executors are terminated (either due to consolidation activity or preemption in case of Spot instances).

This allows for preserving the intermediate shuffle data and cached data on the PVC. When Spark requests new executor pod to replace the terminated one, the system attempts to reuse an existing PVC that belonged to terminated executor. This option can be enabled by the following configuration:

`spark.kubernetes.executor.reusePersistentVolume=true`

### External Shuffle services
Leverage external shuffle services like Apache Celeborn to decouple compute and storage, allowing Spark executors to write data to an external shuffle service instead of local disks. This reduces the risk of data loss and data re-computation due to executor termination or consolidation.

This also allows for better resource management, especially when `Spark Dynamic Resource Allocation` is enabled. External shuffle service allows Spark to preserve shuffle data even after executors are removed during dynamic resource allocation, preventing the need for recomputation of shuffle data when new executors are added. This enables more efficient scale-down of resources when they're not needed.

Also consider the performance implications of external shuffle services. For smaller datasets or applications with low shuffle data volues, the overhead of setting up and managing external shuffle service might outweigh its benefits.

External shuffle services is recommended when dealing with either shuffle data volumes exceeding 500GB to 1TB per job or long running Spark applications that run for several hours to multiple days.

Refer to this [Celeborn Documentation](https://celeborn.apache.org/docs/latest/deploy_on_k8s/) for deployment on Kubernetes and integration configuration with Apache Spark.
