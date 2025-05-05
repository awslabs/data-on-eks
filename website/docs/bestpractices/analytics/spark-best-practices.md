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

<CollapsibleContent header={<h2><span>Networking Best Practices</span></h2>}>
## EKS Networking
### VPC and Subnets Sizing
    * As EKS clusters are scaled up and more workloads are deployed, the number of pods managed by a cluster can grow easily to above thousands of pods. Each pod will consume an IP address. This scenario might become challenging as the availability of IP addresses on a VPC is limited and it is not always possible to recreate a larger VPC or extend the current VPC’s CIDR blocks. 
    * It is also worth noting that both worker nodes and pods require IP addresses. By default, VPC CNI has WARM_ENI_TARGET=1 means that ipamd should keep "a full ENI" of available IPs around in the IPAMD warm pool for the Pod IP assignment. 
    * For new EKS clusters, it is recommended to over-provision the subnets you will use for Pod networking for growth.
* Remediation for IP Address exhaustion
    * Ideally, we recommend you to over-provision your subnets to accommodate future growth. Although, IP exhaustion remediation methods exist for VPCs, they introduce additional operational complexity and have consequential implications to consider.
    * One of the first options to consider for addressing IP address exhaustion, is creating new subnets with larger CIDR blocks within the VPC and deploying worker nodes in these expanded subnets.
    * If adding more subnets, is not an option, then you will have to work on optimising the IP address assignment by tweaking CNI Configuration Variables as described below. Also evaluate the implications of tweaking these variables.
    * VPC CNI Variables → WARM_IP_TARGET & MINIMUM_IP_TARGET
        * The default behaviour of `WARM_ENI_TARGET=1` can be changed by configuring  `MINIMUM_IP_TARGET` and `WARM_IP_TARGET` variables. This configuration, optimizes the number of WARM IPs held at Instance level. The VPC CNI's ipamd regularly communicates with the EC2 API to maintain and monitor a WARM IPs.
        * The appropriate values for these settings will vary based on your specific instance type and anticipated pod density.
        * It is recommended to set MINIMUM_IP_TARGET to slightly higher number than the `maximum` expected number of pods (driver/executors) that you plan to run on each node. This reduces the frequency of EC2 API calls required for managing ENI and IP address assignments.
        * Implication:
            * Careful consideration is needed with this configuration as it increases EC2 API call frequency for IP attachment and detachment operations by ipamd. Excessive API calls can trigger throttling, preventing new ENI or IP assignments across the entire cluster.
            * Hence this configuration is ideally recommended for small clusters or clusters with very low pod churn. 
### CoreDNS Recommendations
    * VPC resolver has a hard cap of 1024 packets per second for each ENI. By default, an EKS cluster runs two replicas of CoreDNS. Anything beyond 1024 packets per second will be throttled, and will result in `unknownHostException`. 
    * While running Spark applications on Kubernetes, there could be scenarios where executors might perform significant number of external DNS lookups. It could be that Spark application, often needs to communicate with external services or databases, for data ingestion, processing, or need to reach external shuffle service. 
    * To address the scalability of default coreDNS, consider implementing one of the following two options:
        * Enable coreDNS auto-scaling.
        * Implement Node local cache.
    * While scaling out `CoreDNS` it is crucial to distribute replicas across different nodes. Co-locating CoreDNS on same nodes, will again end up throttling the ENI, rendering additional replicas ineffective.
    * In order to distribute `CoreDNS` across nodes, apply node anti-affinity policy to the pods:

```
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchExpressions:
        - key: k8s-app
          operator: In
          values:
          - kube-dns
      topologyKey: kubernetes.io/hostname
```

### Reduce Inter AZ Traffic
    * During the shuffle stage, Spark executors may need to exchange data between them. If the Pods are spread across multiple Availability Zones (AZs), this shuffle operation can turn out to be very expensive, especially on Network I/O front. Hence, for these workloads, it is recommended to colocate executors or worker pods in the same AZ. Colocating workloads in the same AZ serves two main purposes:
        * Reduce inter-AZ traffic costs
        * Reduce network latency between executors/Pods
    * To have pods co-located on the same AZ, we can use podAffinity based scheduling constraints. The scheduling constraint preferredDuringSchedulingIgnoredDuringExecution can be enforced in the Pod spec. For example, in Spark we can use a custom template for our driver and executor pods:

```
spec:
  executor:
    affinity:
      podAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
              matchExpressions:
              - key: sparkoperator.k8s.io/app-name
                operator: In
                values:
                - <<spark-app-name>>
          topologyKey: topology.kubernetes.io/zone
          ...
```

</CollapsibleContent>

<CollapsibleContent header={<h2><span>Scaling Best Practices</span></h2>}>
## Karpenter Recommendations
    ### NodePools configuration
        Consider creating separate NodePools for driver and executor pods. 
        * Driver Nodepool
            * Spark driver will be a single replica, and manages the entire lifecycle of the Spark application. Terminating spark driver pod, effectively means terminating the entire spark job. Hence: 
                * Configure Driver Nodepool to use on-demand nodes only. 
                * Disable consolidation on Driver Nodepool. 
            * Use node selectors or taints/tolerations for placing driver pods on this designated Driver NodePool.
        * Executor Nodepool
            * Instance and Capacity type selection:
                * Consider using spot instances for executors to reduce operational costs. 
                * When spot instances are interrupted, executors will be terminated and rescheduled on available nodes. For details on interruption behaviour and node termination management, refer to the `Handling Interruptions` section.
                * Using multiple instance types in the node pool enables access to various spot instance pools, increasing capacity availability and optimizing for both price and capacity across the available instance options.
                * `Weighted Nodepools`: Node selection can be optimized using weighted nodepools arranged in priority order. By assigning different weights to each nodepool, you can establish a selection hierarchy, such as: Spot (highest weight), followed by Graviton, AMD, and Intel (lowest weight).
            * Consolidation Configuration:
                * While enabling `consolidation` for Spark executor pods can lead to better cluster resource utilization, it's crucial to strike a balance with job performance. Frequent consolidation events can result in slower execution times for Spark jobs, as executors are forced to recompute the shuffle data and RDD blocks. 
                * This impact is particularly noticeable in long-running Spark jobs. To mitigate this, it's essential to carefully tune the consolidation interval. 
                * To save intermediate data computed in Spark Executors, consider the following options, which are discussed in `Storage section`:
                    * PVC attach
                    * External Shuffle storage
    * Executor handling (Related to handling interruptions)
        * spark.executor.decommission.enabled=true
        * spark.storage.decommission.enabled=true
    ### Handling interruptions during Karpenter Consolidation/Spot Termination
      Perform a controlled decommissioning instead of killing an executor
        * Leverage `TerminationGracePeriod`, be executor aware and save shuffle data before node being decommissioned.
        * Spark also provides native configurations, to control the termination behaviour. 
        * Controlling the `executor` interruptions
            * Config:
                * `spark.executor.decommission.enabled`
                * `spark.executor.decommission.forceKillTimeout`
            * This is particularly useful in scenarios where executors might be terminated due to spot instance interruptions or Karpenter consolidation events.
            * This will allow executor to gracefully shutdown. Executors will stop accepting tasks and would notify driver about decommissioning state. 
        * To control executor’s `BlockManager` behaviour
            * Config:
                * `spark.storage.decommission.enabled`
                * `spark.storage.decommission.shuffleBlocks.enabled`
                * `spark.storage.decommission.rddBlocks.enabled`
                * `spark.storage.decommission.fallbackStorage.path`
            * This enables the migration of shuffle and RDD blocks from decommissioning executor to other available executors or to a fallback storage location if configured. 
            * This helps in dynamic environment by reducing the need to recompute the shuffle data or RDD blocks, there by improving the job completion times and resource efficiency.

</CollapsibleContent>

<CollapsibleContent header={<h2><span>Advanced Scheduling</span></h2>}>
## Scheduling Considerations
### Default Kubernetes Scheduler behaviour.
    * Default kubernetes scheduler uses `least allocated` approach. This strategy aims to distribute pods evenly across cluster, which helps in maintaining availability and a balanced resource utilization across all nodes, rather than packing more pods in fewer nodes.
    * `Most allocated` approach on the other hand, aims to favor nodes with most amount of allocated resources, which leads to packing more pods onto nodes that are already heavily allocated. This approach is favourable for spark jobs, as it aims for high utilization on select nodes at pod scheduling time, leading to better consolidation of nodes. You will have to leverage a custom kube-scheduler with this option enabled, or leverage Custom Schedulers purpose built for more advanced orchestration.
### Custom Schedulers
    * Custom schedulers enhance Kubernetes’ native scheduling capabilities by providing advanced features tailored for batch and high-performance computing workloads. Custom schedulers enhance resource allocation by optimizing bin-packing and offering scheduling tailored to specific application needs. Here are most frequently used custom schedulers for running Spark workloads on Kubernetes.
        * [Apache Yunikorn](https://yunikorn.apache.org/)
        * [Volcano](https://volcano.sh/en/)
    * Advantages of leveraging custom schedulers like Yunikorn.
        * It provides hierarchical queue system and configurable policies allow for complex resource management.
        * Gang Scheduling
    * How will Yunikorn and Karpenter work together?
        * Karpenter focuses on node provisioning and scaling, while custom schedulers like Yunikorn, brings in application awareness for scheduling.
        * Yunikorn manages the advanced application scheduling aspects like queue management, resource fairness, gang scheduling. 
        * Once Yunikorn schedules the pods, based on application awareness, Karpenter will then fulfil needs of pending pods, spawned by Yunikorn.

</CollapsibleContent>

<CollapsibleContent header={<h2><span>Storage Best Practices</span></h2>}>
## Storage Considerations
### Node Storage
    * By default, the EBS root volumes of worker nodes is set to 20GB.
    * Spark Executors use local storage for temporary data like shuffle data, intermediate results and temporary files. Default storage of 20GB of root volume attached to worker nodes can be limiting in size and performance. Consider the following options to cater to your performance and storage size requirements.
        * Expand the root volume capacity.
        * Configure high-performance storage with better I/O and latency. 
        * Mount additional volumes on worker nodes for temporary data storage.
        * Leverage dynamically provisioned PVCs that can be attached directly to executor pods. 
### Re-Use PVC.
    * This option allows reusing PVCs associated with Spark executors even after the executors are terminated (either due to consolidation activity or preemption in case of Spot instances). 
    * This allows for preserving the intermediate shuffle data and cached data on the PVC. When Spark requests new executor pod to replace the terminated one, the system attempts to reuse an existing PVC that belonged to terminated executor.
    * This option can be enabled by the following configuration:

`spark.kubernetes.executor.reusePersistentVolume=true`

### External Shuffle services like `Apache Celeborn`
    * Leverage external shuffle service to decouple compute and storage, allowing spark executors to write data to external shuffle service instead of local disks, reducing the risk of data loss and data re-computation due to executor termination/consolidation.
    * Allows for better resource management, when Spark Dynamic Resource Allocation is enabled.
    * Also consider the performance implications of Apache Celeborn. 
        * External shuffle services is typically suitable for extremely large volumes of shuffle data. 
        * For smaller datasets or applications with low shuffle data volues, the overhead of setting up and managing external shuffle service might outweigh its benefits.
    * Refer to this [Celeborn Documentation](https://celeborn.apache.org/docs/latest/deploy_on_k8s/) for deployment on Kubernetes and integration configuration with Apache Spark.

</CollapsibleContent>
