---
sidebar_position: 3
sidebar_label: Spark on EKS Best Practices
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../src/components/CollapsibleContent';

# Spark on EKS Best Practices

This page is a practical guide to running Apache Spark on Amazon Elastic Kubernetes Service (EKS). It focuses on the decisions that most affect cost, performance, and stability as your workloads grow.


## EKS Networking
### VPC and Subnets Sizing
#### VPC IP address exhaustion

As EKS clusters scale up with additional Spark workloads, the number of pods managed by a cluster can easily grow into the thousands, each consuming an IP address. This creates challenges, since IP addresses within a VPC are limited, and it's not always feasible to recreate a larger VPC or extend the current VPC's CIDR blocks.

Worker nodes and pods both consume IP addresses. By default, VPC CNI has `WARM_ENI_TARGET=1` means that `ipamd` should keep "a full ENI" of available IPs around in the `ipamd` warm pool for the Pod IP assignment.

#### Remediation for IP Address exhaustion
While IP exhaustion remediation methods exist for VPCs, they introduce additional operational complexity and have significant implications to consider. Hence, for new EKS clusters, it is recommended to over-provision the subnets you will use for Pod networking for growth.

For addressing IP address exhaustion, consider adding secondary CIDR blocks to your VPC and creating new subnets from these additional address ranges, then deploying worker nodes in these expanded subnets.

If adding more subnets, is not an option, then you will have to work on optimising the IP address assignment by tweaking CNI Configuration Variables. Refer to [configure MINIMUM_IP_TARGET](/docs/bestpractices/networking#avoid-using-warm_ip_target-in-large-clusters-or-cluster-with-a-lot-of-churn).


### CoreDNS
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

## Karpenter

[Karpenter](https://karpenter.sh/docs/) enhances Spark on EKS deployments by providing rapid node provisioning capability that aligns with Spark's dynamic resource scaling needs. This automated scaling solution improves resource utilization and cost-efficiency by bringing in right-sized nodes as needed. This also allows Spark jobs to scale seamlessly without the need for pre-configured node groups or manual intervention, there by simplifying operational management.

Recommendations below center on a single trade-off: maximizing node utilization and cost savings without destabilizing running jobs through premature node disruption or executor loss.

### Spark pod characteristics

Spark pods behave differently from typical Kubernetes workloads such as web apps or cron jobs, and these differences drive most of the tuning decisions in this guide.

- Driver and executor pods are not interchangeable. Each job has exactly one driver that owns the job's lifecycle, so losing it kills the whole job. The many executors that do the actual work can tolerate being replaced.
- Pods often arrive in bursts. A single job can request hundreds or thousands of executor pods at once and then release them all when it finishes, which produces sharp spikes in node demand rather than steady load.
- Executors hold state that is expensive to lose. Shuffle data and cached RDD blocks live on the executor, so evicting one without decommissioning it first forces recomputation and slows the job.
- Resource shape and lifetime vary widely. Jobs range from compute heavy, such as large joins and merges, to memory heavy when large datasets are held in memory. Runtimes range from sub-minute experimental queries to jobs that run for days.

Because of this variability, no single pod archetype or NodePool configuration fits every Spark job. The right setup depends on your users and workloads, and the next section covers how to characterize them.


### Establish visibility

#### Grafana dashboards

Before making any changes, put a monitoring stack in place so every change can be measured against a baseline. Grafana and Prometheus are among the most popular options for Spark workloads on Kubernetes.

For Karpenter, this pre-built dashboard is a good starting point: https://github.com/aws/karpenter-provider-aws/tree/main/website/content/en/docs/getting-started/getting-started-with-karpenter

If you are using YuniKorn as your pod scheduler, use the official dashboard available at https://yunikorn.apache.org/docs/user_guide/observability/prometheus/#download-json-files-for-yunikorn-dashboard

#### Know your workloads

Spark workloads are rarely homogeneous, so start by measuring the mix you actually run:

- Look at the distribution of completed job runtimes. Capturing the p10, p50, p90, and p99 values tells you how many jobs are short-lived versus long-running, which is the main input to NodePool design.
- Measure daily and hourly concurrency, including the number of concurrent jobs and the number of pods per job. This surfaces peak-load scaling and performance issues before they hit production.

Once you know the shape of the mix, group jobs into tiers by disruption tolerance rather than runtime alone. If the mix is multimodal, for example a large share of sub-minute jobs alongside multi-hour jobs, split drivers across separate NodePools per tier so aggressive cost tuning stays away from the jobs that cannot absorb it. See the [NodePool configuration summary](#nodepool-configuration-summary) for recommended starting settings per tier.


### NodePool design

Once you understand your workload mix, design NodePools to match it.

#### Topology-aware NodePools

Keep a given Spark workload within a single Availability Zone rather than spreading it across AZs. Spark executors constantly exchange data with each other, and when they sit in different AZs that traffic is billed as cross-AZ data transfer, which adds up quickly on shuffle-heavy jobs.

#### Driver NodePool

Consider creating separate NodePools for driver and executor pods. The Spark driver is a single pod that manages the entire lifecycle of the application, so terminating it terminates the whole job. Drivers are also fairly uniform across jobs, which makes them a good fit for a dedicated pool tuned for stability.

##### Use a dedicated driver NodePool

Drivers do a different job from executors and generally need fewer resources, since executors carry the bulk of the work. That means you can place drivers on smaller, less expensive instance types to save cost. Use node selectors and taints to keep driver pods on their own nodes.

##### Use On-Demand instances for drivers

Configure driver NodePools to use On-Demand capacity only. A driver on a Spot instance can be reclaimed at any time, which loses the job's progress and requires manual intervention to restart. Use node selectors and taints to enforce On-Demand placement for the driver pool.

##### Protect driver pods from disruption

Consider adding the `karpenter.sh/do-not-disrupt: "true"` annotation to driver pods. This stops Karpenter from voluntarily consolidating or drift-replacing the node the driver runs on, so the job is not interrupted by a node the platform decides to reclaim.

Be aware of a side effect. Karpenter leaves the node uncordoned and fully schedulable, so it stays a normal target for the kube-scheduler. That can lead to the following situation:

1. A driver pod with `do-not-disrupt` lands on a node.
2. The kube-scheduler keeps placing more pods on that same node, since it looks like any other node.
3. Some of those pods finish while others may also be long-lived.
4. As long as the `do-not-disrupt` pod is still running, Karpenter cannot consolidate or drift-replace the node, even when it is underutilized or running a stale AMI.

When you want such a node to drain, you may need to cordon it manually or build a workflow that handles the drain for you.

#### Executor NodePool

##### Configure Spot instances

In the absence of [Amazon EC2 Reserved Instances](https://aws.amazon.com/ec2/pricing/reserved-instances/) or [Savings Plans](https://aws.amazon.com/savingsplans/), consider using [Amazon EC2 Spot Instances](https://aws.amazon.com/ec2/spot/) for executors to reduce data plane costs.

When a Spot instance is interrupted, its executors are terminated and rescheduled on available nodes. Without a remote shuffle service, any work those executors held on the terminated node is lost and has to be recomputed. For details on interruption behavior and node termination management, see [Disruption and consolidation](#disruption-and-consolidation).

##### Instance and capacity type selection

Allowing multiple instance types in the NodePool gives Karpenter access to more Spot capacity pools, which improves availability and lets it optimize for both price and capacity across the available options.

Weighted NodePools let you express a preference order across pools. By assigning each pool a weight, you create a fallback hierarchy where Karpenter tries the most-preferred pool first and moves to the next when capacity is unavailable. A common ordering favors cheaper architectures first, for example Graviton, then AMD, then Intel, since Graviton is typically the lowest priced and Intel the highest.

Depending on your job's I/O profile, also consider instance types with local NVMe SSDs, which give Spark faster local storage for reading and writing shuffle and spill data.

### Disruption and consolidation

Enabling consolidation improves cluster utilization, but it has to be balanced against job performance. Frequent disruption slows jobs down, because evicted executors have to recompute shuffle data and RDD blocks. This is the central tuning lever for cost versus stability, and you control it through disruption budgets, consolidation policy, and graceful decommissioning.

#### Disruption budgets and scheduling

Always set disruption budgets on your NodePools. Without a budget, Karpenter can mark every eligible node for disruption at the same time, which is especially damaging for short, bursty jobs that create many executor pods at once.

Consider this scenario without a budget:

- A job requests 1000 pods.
- The job finishes in one minute.
- The nodes sit idle for three minutes and become consolidation eligible.
- Every node is marked for termination.
- Another job requests 1000 pods.
- Karpenter has to stand up all those nodes again from scratch.

A disruption budget caps how many nodes are removed at once, so nodes are retired gradually and are more likely to be reused by the next wave of pods. Budgets matter more for executors than for drivers: a driver pool has one driver per job, so there is nothing to budget, while an executor pool can have hundreds of executors spread across many jobs.

If you know your job submission patterns, use the `schedule` field on a budget to align disruption with them. For example, if jobs run during the day but not at night, allow aggressive consolidation overnight and restrict it during working hours.

```yaml
disruption:
  consolidationPolicy: WhenEmptyOrUnderutilized
  budgets:
    - nodes: "0"
      schedule: "0 9 * * mon-fri"
      duration: 8h
      reasons:
        - Drifted
        - Underutilized
```

This budget allows zero nodes to be disrupted for Drifted or Underutilized reasons Monday through Friday, starting at 09:00 for eight hours. Outside that window, the default budget applies.

#### Consolidation policy and dynamic allocation

Set the consolidation policy per NodePool according to job tier (see the [NodePool configuration summary](#nodepool-configuration-summary)). Short-lived jobs tolerate aggressive consolidation, while long-running jobs need `WhenEmpty` only or consolidation disabled so executors are not evicted mid-job.

Dynamic allocation interacts with consolidation because Spark scales executors up and down on its own schedule. Layering aggressive Karpenter consolidation on top of that can cause double-eviction storms: Spark removes an idle executor, Karpenter then consolidates the now-emptier node, and stable executors on that node are evicted as well. To avoid this, set `consolidateAfter` longer than your dynamic allocation idle timeout so Karpenter waits for Spark to settle before acting.

#### Graceful shutdown and handling interruptions

When a node is scheduled for termination, whether from consolidation or a Spot interruption, decommission its executors in a controlled way rather than killing them abruptly:

- Set an appropriate termination grace period for Spark workloads.
- Use executor-aware termination handling.
- Make sure shuffle data is saved before the node is decommissioned.

Enable graceful executor shutdown with the following settings:

- `spark.executor.decommission.enabled=true`: lets executors finish their current tasks and transfer cached data before shutting down. When enabled, an executor stops accepting tasks and notifies the driver of its decommissioning state. This is especially useful when executors run on Spot instances.
- `spark.executor.decommission.forceKillTimeout`: bounds how long to wait before force-killing a decommissioning executor.
- `spark.storage.decommission.enabled=true`: migrates cached data from a decommissioning executor before shutdown, avoiding data loss and recomputation.

Fine-grained BlockManager migration is controlled by:

- `spark.storage.decommission.shuffleBlocks.enabled`
- `spark.storage.decommission.rddBlocks.enabled`
- `spark.storage.decommission.fallbackStorage.path`

These migrate shuffle and RDD blocks from a decommissioning executor to other executors or to a fallback storage location. In dynamic environments this reduces recomputation, which improves job completion times and resource efficiency.

For other ways to preserve intermediate data computed by executors, see [Storage Best Practices](./spark-best-practices#storage-best-practices).

#### Avoiding node churn

Build a dashboard that compares node creation against empty disruption, broken out per cluster:

```promql
sum by (cluster) (increase(karpenter_nodeclaims_disrupted_total{reason="empty"}[24h]))
sum by (cluster) (increase(karpenter_nodeclaims_launched_total[24h]))
```

When the empty-disruption count approaches the launch count, nodes are being created and torn down in a cycle instead of being reused. That cycle is the churn you want to reduce.

Also track the share of nodes sitting near-empty. Memory allocation across the fleet tends to be bimodal, with nodes either well packed or nearly empty, and the near-empty population is usually the largest single contributor to idle cost.

```promql
yunikorn_scheduler_memory_node_usage_total{range="(0%, 10%]"}
```

If you see churn, adjust the consolidation policy and disruption budgets first. You can also tune `BATCH_MAX_DURATION` in the Karpenter controller configuration. Shorter batches let Karpenter make provisioning decisions more frequently, so each batch can account for nodes from the previous batch that are already in flight, which reduces over-provisioning during bursts. The trade-off is that shorter batches can select smaller instances and slightly increase controller CPU usage.

### NodePool configuration summary

The table below is recommended NodePool classes and starting configurations. Treat them as a baseline to classify and tune against your own workloads.

| Job class | Configuration |
|-----------|---------------|
| Short (under a few minutes) | `WhenEmptyOrUnderutilized`, short `consolidateAfter`, low `expireAfter`, small instance shapes. No `do-not-disrupt` needed, since jobs finish before disruption matters. |
| Medium (hours) | `WhenEmpty` or `WhenEmptyOrUnderutilized`, `do-not-disrupt` on drivers, tight disruption budgets. |
| Long (days) | `WhenEmpty` only or consolidation disabled, `do-not-disrupt` on drivers, larger instances, tight disruption budgets, and manual drain windows for AMI drift. |


## Advanced Scheduling Considerations
### Default Kubernetes Scheduler behaviour.

Default Kubernetes scheduler uses `least allocated` approach. This strategy aims to distribute pods evenly across cluster, which helps in maintaining availability and a balanced resource utilization across all nodes, rather than packing more pods in fewer nodes.

`Most allocated` approach on the other hand, aims to favor nodes with most amount of allocated resources, which leads to packing more pods onto nodes that are already heavily allocated. This approach is favourable for Spark jobs, as it aims for high utilization on select nodes at pod scheduling time, leading to better consolidation of nodes. You will have to leverage a custom kube-scheduler with this option enabled, or leverage Custom Schedulers purpose built for more advanced orchestration.

### Custom Schedulers

The default Kubernetes scheduler places one pod at a time and has no concept of a job. For Spark that creates two problems. Executors can be admitted piecemeal, so a job can hold a partial set of executors while waiting for the rest, tying up resources without making progress. And there is no way to enforce fair sharing or quotas across teams competing for the same cluster.

Custom schedulers such as [Apache YuniKorn](https://yunikorn.apache.org/) and [Volcano](https://volcano.sh/en/) add job-aware and queue-aware scheduling on top of Kubernetes. The capabilities that matter most for Spark are:

* Gang scheduling admits a job's driver and executors together, or not at all, which avoids the partial-allocation stall described above.
* Hierarchical queues with quotas let you cap and prioritize resources per team or job class, so one tenant cannot starve another.
* Bin-packing concentrates pods onto fewer nodes, which pairs with Karpenter consolidation to reduce idle capacity and cost.

The rest of this guide uses YuniKorn.


### How do YuniKorn and Karpenter work together?

The two tools operate at different layers, so they combine cleanly. YuniKorn schedules pods according to application-aware policies and queue priorities. When pods stay pending because the cluster is out of capacity, Karpenter detects them and provisions the right nodes to fit them.

For Spark, that means YuniKorn places executors according to queue quotas and gang-scheduling constraints, while Karpenter makes sure the matching node types show up to run them.

### YuniKorn

**Dedicated queue for short-lived jobs, with resource limits**

Capping the short-job queue throttles bursts. When many short-job pods arrive at once, the excess waits in the queue, and because these jobs finish quickly, slots free up and the pending pods land on existing nodes instead of triggering new provisioning. Before capping, confirm that the short jobs can tolerate a brief queue wait within their latency SLA, and that the cap is sized at or above the largest gang if you use gang scheduling.

**Dedicated queue for long-running jobs**

Isolating long jobs in their own queue reduces contention with short, bursty workloads and lets you tune each class independently.


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
