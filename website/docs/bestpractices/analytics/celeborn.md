---
sidebar_position: 4
sidebar_label: Apache Celeborn Best Practices
---

## Apache Celeborn Best Practices

Apache Celeborn is an elastic and high-performance Remote Shuffle Service (RSS) designed to handle intermediate data processing for big data compute engines like Spark, Flink, and MapReduce.

#### Celeborn for Spark Dynamic Allocation

For Spark dynamic allocation, Celeborn addresses a critical challenge: when executors are dynamically scaled up or down based on workload demands, shuffle data traditionally stored on executor local disks would be lost when those executors are terminated. 

Celeborn solves this by externalizing shuffle operations to dedicated worker nodes that persist shuffle data independently of executor lifecycles. This enables true elastic scaling where Spark can safely add and remove executors without losing intermediate computation results, significantly improving resource utilization and cost efficiency. The service provides high availability through data replication and asynchronous processing, making dynamic allocation more reliable compared to traditional local shuffle mechanisms.

## Running Celeborn on Kubernetes

### Storage Configuration

Apache Celeborn pods run as StatefulSets in the official Helm chart. Performance is heavily dependent on the underlying storage used for shuffle data. 

**When to Use Instance Stores:** If you need absolute maximum performance from your cluster, use instance store volumes. Instance stores provide high IOPS and throughput that significantly improve Celeborn's shuffle operations compared to network-attached storage like EBS.

**Trade-offs:** Instance stores are ephemeral and tied to the instance lifecycle. For most workloads, network-attached storage (e.g., gp3 EBS volumes) provides sufficient performance with better operational flexibility.

**Implementation:** Use the [Kubernetes Local Static Provisioner](https://github.com/kubernetes-sigs/sig-storage-local-static-provisioner) to automate configuration and provisioning of local storage to Celeborn pods.

### StatefulSet Update Strategies

Workers and masters are deployed as StatefulSets, which have restrictions on which fields can be updated in-place.

#### Updating Immutable Fields

If you need to modify immutable fields (like volume claim templates or pod management policy):

1. **For Worker Pods:**
   - Use a blue-green deployment strategy with two separate StatefulSets
   - Use Celeborn's decommission API to mark workers for rotation
   - Decommissioned workers accept existing requests but reject new ones
   - Once drained, delete the old StatefulSet

2. **For Master Pods:**
   - Deploy a new StatefulSet with updated configuration
   - Update client configurations (e.g., Spark `spark.celeborn.master.endpoints`) to point to the new master endpoints
   - Verify connectivity and wait for all clients to stop talking to the old master before removing the old StatefulSet

### Local Storage Considerations

When using local static provisioner, be aware of these behaviors:

**Node Affinity:** Local PVs have node affinity, binding them to specific nodes. StatefulSets will remount the same PVC to the same pod only if the pod reschedules to the same node.

**Pod Rescheduling Issue:** If a worker StatefulSet is restarted with PVC retention policy set to `Retain` (default), but pods reschedule to different nodes, the pods will be stuck in `Pending` state because:
- The PVC is still bound to the original node
- The pod is scheduled to a different node
- Kubernetes cannot satisfy the pod's volume requirements

**Solutions:**
- Set PVC deletion policy to `Delete` to allow pods to create new volumes on their new nodes
- Use node affinity/selectors to ensure pods stay on the same nodes
- Consider using `WhenDeleted` retention policy for automatic cleanup

### Node Rotation with Karpenter

When Karpenter drains a node, you can trigger graceful decommission using a `preStop` hook:

**Lifecycle Flow:**
1. Karpenter initiates node drain → Pod receives SIGTERM
2. `preStop` hook executes immediately, triggering Celeborn's graceful shutdown
3. Celeborn stops accepting new requests and completes in-flight operations
4. Kubernetes waits up to `terminationGracePeriodSeconds` before sending SIGKILL
5. Pod terminates after decommission completes or grace period expires

**Configuration Example:**

```yaml
spec:
  template:
    spec:
      terminationGracePeriodSeconds: 3600
      containers:
      - name: celeborn-worker
        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh", "-c", "/opt/celeborn/sbin/decommission-worker.sh"] # you will have to create this file.
```

**Best Practices:**
- Set `terminationGracePeriodSeconds` high enough for typical decommission operations (varies depending on your envionrment)
- Configure Celeborn's graceful shutdown timeout to be ~30s less than `terminationGracePeriodSeconds` to allow cleanup
- If decommission exceeds the grace period, Kubernetes will forcefully terminate the pod with SIGKILL
- This approach handles disruptions gracefully but cannot prevent or delay them (unlike PodDisruptionBudgets or `karpenter.sh/do-not-disrupt` annotations)
- Monitor decommission duration to tune grace period appropriately

## Monitoring

Use the community-maintained [Grafana dashboards](https://github.com/apache/celeborn/tree/main/assets/grafana) to monitor Celeborn performance. These dashboards provide visibility into:
- Registered shuffle count and active shuffle size
- Worker availability and health (available, excluded, lost, shutdown workers)
- Shuffle read/write operations and throughput
- Storage capacity and utilization (device capacity, memory file storage)
- Push/fetch data latency and failure counts
- Flush operations and commit times
- Memory usage (Netty memory, direct memory, buffer allocations)
- Sort operations and performance
- Active connections and slots

