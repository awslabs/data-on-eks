---
sidebar_position: 4
sidebar_label: Apache Celeborn Best Practices
---

# Apache Celeborn: Production Operations Guide

Apache Celeborn is an elastic and high-performance Remote Shuffle Service (RSS) designed to handle intermediate data processing for big data compute engines like Spark, Flink, and MapReduce.

This guide provides production-grade best practices for operating Celeborn at scale (200+ nodes), covering deployment, maintenance, upgrades, and troubleshooting scenarios encountered in large-scale data platforms.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Deployment Best Practices](#deployment-best-practices)
- [Day 2 Operations](#day-2-operations-rolling-restarts-and-maintenance)
- [Scaling Considerations](#scaling-to-200-nodes)
- [Monitoring and Observability](#monitoring)
- [Troubleshooting](#troubleshooting-common-scenarios)

## Architecture Overview

Understanding Celeborn's architecture helps explain why certain configurations are critical for production operations.

### Default Spark Shuffle Architecture

In traditional Spark deployments, shuffle data is stored on executor local disks:

[![Default Spark Shuffle Architecture](../../benchmarks/img/spark-shuffler-architecture.png)](../../benchmarks/img/spark-shuffler-architecture.png)

**Limitations of Default Shuffle:**
- ❌ Shuffle data lost when executors are terminated (blocks dynamic allocation)
- ❌ Executors must stay alive until all downstream stages complete
- ❌ No fault tolerance - executor failure requires recomputing upstream stages
- ❌ Poor resource utilization - can't scale down during shuffle-heavy stages

### Spark with Apache Celeborn Architecture

Celeborn externalizes shuffle operations to dedicated worker nodes:

[![Spark with Apache Celeborn Architecture](../../benchmarks/img/celeborn-architecture.png)](../../benchmarks/img/celeborn-architecture.png)

**Celeborn Architecture Components:**

1. **Celeborn Masters (3+ nodes):**
   - Coordinate shuffle operations and slot assignments
   - Track worker health via heartbeats
   - Manage metadata for active shuffles
   - Provide HA through Raft consensus (deploy in odd numbers: 3, 5, 7)

2. **Celeborn Workers (N nodes):**
   - Store and serve shuffle data on local disks (EBS or NVMe)
   - Handle push operations from Spark executors (write shuffle data)
   - Handle fetch operations to Spark executors (read shuffle data)
   - Replicate data to other workers for fault tolerance

3. **Spark Client Library:**
   - Embedded in Spark executors and driver
   - Handles retries, failover, and replica selection
   - Communicates with masters for slot allocation
   - Pushes/fetches shuffle data to/from workers

**Benefits of Celeborn Architecture:**
- ✅ Shuffle data persists independently of executor lifecycle
- ✅ Enables true dynamic allocation (scale executors up/down freely)
- ✅ Fault tolerance through replication (survive worker failures)
- ✅ Better resource utilization (executors can be terminated after map stage)
- ✅ Improved performance through dedicated shuffle infrastructure

### Celeborn for Spark Dynamic Allocation

For Spark dynamic allocation, Celeborn addresses a critical challenge: when executors are dynamically scaled up or down based on workload demands, shuffle data traditionally stored on executor local disks would be lost when those executors are terminated.

Celeborn solves this by externalizing shuffle operations to dedicated worker nodes that persist shuffle data independently of executor lifecycles. This enables true elastic scaling where Spark can safely add and remove executors without losing intermediate computation results, significantly improving resource utilization and cost efficiency. The service provides high availability through data replication and asynchronous processing, making dynamic allocation more reliable compared to traditional local shuffle mechanisms.

### High Availability Architecture

For production deployments, Celeborn uses a master-worker architecture with HA capabilities:

- **Masters (3+ nodes):** Coordinate shuffle operations, track worker health, manage metadata. Deploy in odd numbers (3, 5, 7) for Raft consensus.
- **Workers (N nodes):** Store and serve shuffle data. Scale horizontally based on workload demands.
- **Replication:** Shuffle data replicated across workers (typically factor=2) for fault tolerance.
- **Client Library:** Embedded in Spark executors, handles retries, failover, and replica selection.

:::tip Production Recommendation
For clusters serving 200+ Spark executors, start with 6-12 worker nodes and scale based on shuffle volume metrics. Each worker should handle 10-20 concurrent Spark applications comfortably.
:::

## Deployment Best Practices

### Storage Configuration

Apache Celeborn pods run as StatefulSets in the official Helm chart. Performance is heavily dependent on the underlying storage used for shuffle data.

#### Storage Options: NVMe vs EBS

Choosing the right storage is critical for Celeborn performance and reliability. Here's a clear comparison:

| Storage Type | IOPS | Throughput | Durability | Cost | Replication Required |
|--------------|------|------------|------------|------|---------------------|
| **Instance Store (NVMe SSD)** | 3M+ | 14 GB/s | ❌ Ephemeral | Included with instance | ✅ **MANDATORY** |
| **EBS gp3** | 16K (configurable) | 1 GB/s | ✅ Persistent | $0.08/GB/month | ✅ Recommended |
| **EBS io2** | 64K+ | 4 GB/s | ✅ Persistent | $0.125/GB/month | ✅ Recommended |

#### NVMe Instance Stores: High Performance, High Risk

**Advantages:**
- ⚡ Extremely high IOPS (3M+) and throughput (14 GB/s)
- 💰 No additional storage cost (included with instance)
- 🚀 Best performance for shuffle-intensive workloads

**Critical Limitations:**

:::danger Data Loss Risk with NVMe Instance Stores
NVMe instance stores are **ephemeral storage** - all data is permanently lost when:
- Node is terminated (EC2 retirement, spot interruption)
- Node is replaced (Karpenter consolidation, AMI updates)
- Instance is stopped or hibernated
- Hardware failure occurs

**This means shuffle data disappears instantly when nodes die.**

To prevent job failures with NVMe storage, you MUST:
1. ✅ Enable replication: `spark.celeborn.client.push.replicate.enabled: "true"` (factor=2 minimum)
2. ✅ Configure aggressive retries: `maxRetriesForEachReplica: 10`, `retryWait: 20s`
3. ✅ Maintain 50%+ extra worker capacity to handle node losses
4. ✅ Use on-demand instances (not spot) for stability
5. ✅ Monitor node replacement events closely

**Without replication enabled, NVMe instance store failures WILL cause job failures and data loss.**
:::

**When to Use NVMe Instance Stores:**
- ✅ Shuffle I/O is proven bottleneck (profiled with metrics)
- ✅ Workloads can tolerate occasional retry storms during node replacements
- ✅ Team has operational maturity to handle ephemeral storage
- ✅ Cost savings from included storage justify operational complexity

#### EBS Volumes: Balanced Performance, Operational Safety

**Advantages:**
- 💾 Persistent across pod restarts and node replacements
- 🔄 Enables graceful rolling updates without data loss
- 📈 Resize volumes online without downtime
- 🛡️ Survives node failures (volumes reattach to new nodes)
- 🔧 Simpler operations and maintenance

**Performance:**
- gp3: 16K IOPS, 1 GB/s throughput (sufficient for most workloads)
- io2: 64K IOPS, 4 GB/s throughput (high-performance option)

:::tip Recommended for Production: EBS gp3
For 200+ node clusters, **use EBS gp3 volumes** as the default choice:

**Why EBS over NVMe:**
1. **Operational Safety** - No data loss during node replacements, AMI updates, or EKS upgrades
2. **Easier Maintenance** - Rolling restarts work smoothly without aggressive retry tuning
3. **Predictable Behavior** - No surprise retry storms when nodes are replaced
4. **Sufficient Performance** - Network and CPU are usually bottlenecks, not storage I/O
5. **Replication Optional** - Can run without replication (though still recommended for HA)

**When to Consider NVMe:**
- Only after profiling proves storage I/O is the bottleneck
- Only if team can handle operational complexity
- Only with mandatory replication enabled

**Cost Comparison:**
- r8g.8xlarge with 4TB NVMe: $1.63/hour (storage included)
- r8g.8xlarge with 4TB gp3 EBS: $1.63/hour + $320/month storage = ~$2.07/hour
- Extra cost: ~$0.44/hour for persistent storage and operational simplicity
:::

**Implementation:**

For NVMe instance stores, use the [Kubernetes Local Static Provisioner](https://github.com/kubernetes-sigs/sig-storage-local-static-provisioner) to automate configuration.

For EBS volumes, use standard Kubernetes PersistentVolumeClaims in the Celeborn Helm chart.

**Implementation:** Use the [Kubernetes Local Static Provisioner](https://github.com/kubernetes-sigs/sig-storage-local-static-provisioner) to automate configuration and provisioning of local storage to Celeborn pods.

### Critical Configuration for Production

These configurations are **non-negotiable** for production deployments. Missing any of these will cause job failures, data loss, or operational issues.

#### Server-Side Configuration (Helm Values)

Copy this configuration into your Celeborn Helm values file:

```yaml
celeborn:
  # ============================================================================
  # CRITICAL: Fixed Ports (Required for Graceful Shutdown)
  # ============================================================================
  # All 4 ports MUST be fixed (non-zero) when graceful shutdown is enabled.
  # Dynamic ports (port=0) cause assertion failures during worker restarts.
  celeborn.worker.rpc.port: "9091"
  celeborn.worker.fetch.port: "9092"
  celeborn.worker.push.port: "9093"
  celeborn.worker.replicate.port: "9094"

  # ============================================================================
  # Graceful Shutdown (Enables Zero-Downtime Rolling Updates)
  # ============================================================================
  celeborn.worker.graceful.shutdown.enabled: "true"
  celeborn.worker.graceful.shutdown.timeout: "600s"
  celeborn.worker.graceful.shutdown.checkSlotsFinished.interval: "1s"
  celeborn.worker.graceful.shutdown.checkSlotsFinished.timeout: "480s"

  # ============================================================================
  # CRITICAL: Network Binding (Required for Stable Worker Registration)
  # ============================================================================
  # Without this, workers register with pod IPs that change after restart,
  # causing routing failures and connection errors.
  celeborn.network.bind.preferIpAddress: "false"

  # ============================================================================
  # Heartbeat Timeout (Allow Time for EBS Reattachment)
  # ============================================================================
  # EBS volumes take 60-120s to reattach during pod restarts on EKS.
  # This timeout prevents false "worker lost" events during restarts.
  celeborn.master.heartbeat.worker.timeout: "180s"

  # ============================================================================
  # Storage Configuration
  # ============================================================================
  celeborn.storage.availableTypes: "SSD"
  celeborn.worker.storage.dirs: "/mnt/disk1:disktype=SSD:capacity=900Gi,/mnt/disk2:disktype=SSD:capacity=900Gi,/mnt/disk3:disktype=SSD:capacity=900Gi,/mnt/disk4:disktype=SSD:capacity=900Gi"

  # ============================================================================
  # Slot Assignment (For Large Clusters)
  # ============================================================================
  celeborn.master.slot.assign.policy: "ROUNDROBIN"
  celeborn.master.slot.assign.maxWorkers: "10000"
```

:::danger CRITICAL: Fixed Ports Are Mandatory
When `celeborn.worker.graceful.shutdown.enabled: true`, you **MUST** configure all 4 fixed ports:
- `celeborn.worker.rpc.port: "9091"`
- `celeborn.worker.fetch.port: "9092"`
- `celeborn.worker.push.port: "9093"`
- `celeborn.worker.replicate.port: "9094"`

**Do NOT use dynamic ports (port=0).** This will cause assertion failures during graceful shutdown and break rolling restarts.

**Symptom if misconfigured:** Workers crash with `AssertionError` during graceful shutdown.
:::

:::danger CRITICAL: Network Binding Configuration
You **MUST** set `celeborn.network.bind.preferIpAddress: "false"` for production deployments.

**Why:** Without this, workers register with pod IPs instead of DNS names. When a worker pod restarts, it gets a new IP address, but clients still try to connect to the old IP, causing connection failures.

**Symptom if misconfigured:** After worker restarts, you see `Connection refused` errors and workers don't re-register properly with the master.
:::

#### Client-Side Configuration (Spark Jobs)

Add this configuration to **EVERY** Spark job that uses Celeborn:

```yaml
sparkConf:
  # ============================================================================
  # Shuffle Manager (Required to Use Celeborn)
  # ============================================================================
  spark.shuffle.manager: "org.apache.spark.shuffle.celeborn.SparkShuffleManager"
  spark.serializer: "org.apache.spark.serializer.KryoSerializer"
  spark.shuffle.service.enabled: "false"

  # ============================================================================
  # Master Endpoints (Use All Masters for HA)
  # ============================================================================
  spark.celeborn.master.endpoints: "celeborn-master-0.celeborn-master-svc.celeborn.svc.cluster.local:9097,celeborn-master-1.celeborn-master-svc.celeborn.svc.cluster.local:9097,celeborn-master-2.celeborn-master-svc.celeborn.svc.cluster.local:9097"

  # ============================================================================
  # CRITICAL: Replication (MANDATORY for Zero-Downtime Operations)
  # ============================================================================
  # Without replication, worker failures cause immediate job failures.
  # With NVMe instance stores, replication is ABSOLUTELY MANDATORY.
  spark.celeborn.client.push.replicate.enabled: "true"

  # ============================================================================
  # Retry Configuration (Tuned for Worker Restarts)
  # ============================================================================
  # These settings allow Spark to survive worker restarts (~13s) and
  # EBS reattachment delays (~60-120s) without failing tasks.
  spark.celeborn.client.fetch.maxRetriesForEachReplica: "5"
  spark.celeborn.data.io.retryWait: "15s"
  spark.celeborn.client.rpc.maxRetries: "5"

  # ============================================================================
  # Shuffle Writer (Use "sort" for Large Partition Counts)
  # ============================================================================
  spark.celeborn.client.spark.shuffle.writer: "sort"

  # ============================================================================
  # Batch Commit (Required for Graceful Shutdown)
  # ============================================================================
  spark.celeborn.client.shuffle.batchHandleCommitPartition.enabled: "true"

  # ============================================================================
  # CRITICAL: Adaptive Query Execution (Local Shuffle Reader MUST Be Disabled)
  # ============================================================================
  spark.sql.adaptive.enabled: "true"
  spark.sql.adaptive.localShuffleReader.enabled: "false"  # MUST BE FALSE

  # ============================================================================
  # Network Timeouts (Generous for Large-Scale Clusters)
  # ============================================================================
  spark.network.timeout: "2000s"
  spark.executor.heartbeatInterval: "300s"
  spark.rpc.askTimeout: "600s"
```

:::danger CRITICAL: Replication Must Be Enabled
You **MUST** set `spark.celeborn.client.push.replicate.enabled: "true"` in ALL Spark jobs.

**Why replication is mandatory:**
1. **Worker failures** - When a worker pod restarts, shuffle data becomes temporarily unavailable. Replication allows Spark to fetch from the replica worker.
2. **Node replacements** - During EKS upgrades or AMI updates, nodes are replaced and workers move to new nodes. Replication prevents data loss.
3. **NVMe instance stores** - If using NVMe storage, replication is ABSOLUTELY MANDATORY because all data is lost when nodes die.

**Without replication:**
- ❌ Worker restarts cause immediate task failures
- ❌ Node replacements cause job failures
- ❌ NVMe node losses cause permanent data loss and job failures

**Symptom if disabled:** You'll see `FetchFailed` exceptions and task failures during any worker disruption.
:::

:::danger CRITICAL: Local Shuffle Reader Must Be Disabled
You **MUST** set `spark.sql.adaptive.localShuffleReader.enabled: "false"` when using Celeborn.

**Why:** When set to `true`, Spark's Adaptive Query Execution tries to read shuffle data from local executors instead of Celeborn workers. This causes:
- ❌ `FileNotFoundException` errors (data doesn't exist on executors)
- ❌ Job failures
- ❌ Celeborn is completely bypassed

**This is the #1 most common misconfiguration that breaks Celeborn.**

**Symptom if misconfigured:** Jobs fail with `FileNotFoundException` for shuffle files, even though Celeborn is running fine.
:::

:::warning Retry Configuration for NVMe Instance Stores
If using NVMe instance stores, increase retry settings to handle node replacement events:

```yaml
spark.celeborn.client.fetch.maxRetriesForEachReplica: "10"  # Increased from 5
spark.celeborn.data.io.retryWait: "20s"  # Increased from 15s
spark.celeborn.client.rpc.maxRetries: "10"  # Increased from 5
```

This gives Spark more time to wait for replica workers when primary workers are lost due to node terminations.
:::

### StatefulSet Update Strategies

Workers and masters are deployed as StatefulSets, which have restrictions on which fields can be updated in-place.

#### Mutable vs Immutable Fields

**Mutable (can update in-place):**
- Container image
- Environment variables
- ConfigMaps and Secrets
- Resource requests/limits
- Annotations and labels

**Immutable (require StatefulSet replacement):**
- Volume claim templates
- Pod management policy
- Service name
- Persistent volume size (requires manual PVC resize)

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

:::warning Master Endpoint Changes
Changing master endpoints requires updating ALL Spark job configurations and restarting active applications. Plan master replacements during maintenance windows when no critical workloads are running.
:::

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

## Day 2 Operations: Rolling Restarts and Maintenance

This section covers production operations for maintaining Celeborn clusters at scale, including version upgrades, configuration changes, security patches, and infrastructure updates.

### Common Maintenance Scenarios

| Scenario | Requires Restart | Approach | Downtime | Risk Level |
|----------|------------------|----------|----------|------------|
| **Celeborn version upgrade** | Yes (workers + masters) | Rolling restart with decommission | Zero | Medium |
| **Helm chart update** | Yes (triggered automatically) | Rolling restart with decommission | Zero | Medium |
| **Configuration change** | Yes (ConfigMap triggers restart) | Rolling restart with decommission | Zero | Low |
| **Container security patch** | Yes (image update) | Rolling restart with decommission | Zero | Low |
| **EKS version upgrade** | Yes (node replacement) | Drain nodes with decommission | Zero | High |
| **AMI update** | Yes (node replacement) | Drain nodes with decommission | Zero | High |
| **Instance type change** | Yes (node replacement) | Blue-green worker pool | Zero | Medium |
| **Storage expansion** | No (resize PVC) | Online resize | Zero | Low |
| **Master endpoint change** | Yes (all clients) | Blue-green master deployment | Requires maintenance window | High |

:::tip Planning Maintenance Windows
For large-scale clusters (200+ nodes), schedule maintenance during low-traffic periods. A full rolling restart of 200 workers takes approximately 6-8 hours with decommission-based approach (2-3 minutes per worker including drain time).
:::

### Understanding Orphaned Shuffle Data After Restarts

When a Celeborn worker pod restarts (due to upgrades, configuration changes, or node maintenance), an interesting behavior occurs with shuffle data on persistent volumes:

**What Happens During a Worker Restart:**

1. **Before Restart:** Worker has shuffle files on EBS volumes (e.g., `/mnt/disk1/celeborn-worker/shuffle_data/`) and maintains an in-memory index of all files
2. **Pod Deleted:** Worker process stops, in-memory metadata is lost
3. **EBS Volumes Persist:** Physical shuffle files remain on disk (EBS volumes are persistent storage)
4. **Pod Recreated:** New worker process starts with empty in-memory index
5. **Result:** Physical files exist on disk, but worker doesn't know about them - they become "orphaned"

**Why You See FileNotFoundException Errors:**

After a worker restarts, Spark executors may request shuffle files that were written before the restart:

```
ERROR FetchHandler: Read file: 42-0-1 with shuffleKey: spark-xxx-163 error
java.io.FileNotFoundException: Could not find file 42-0-1 for spark-xxx-163
```

**File naming pattern:** `{partitionId}-{attemptId}-{epoch}`
- Example: `42-0-1` = partition 42, attempt 0, epoch 1

**This is expected and normal!** The worker's in-memory index was reset, so it doesn't know about files written before the restart. Spark automatically fetches from the replica worker and the task succeeds.

### Celeborn's Cleanup Mechanisms

Celeborn uses multiple mechanisms to clean up shuffle data and prevent disk exhaustion:

#### 1. Application-Level Cleanup (Primary Mechanism)

Based on the [LifecycleManager documentation](https://celeborn.apache.org/docs/latest/developers/lifecyclemanager/), Celeborn tracks active applications and their shuffle data:

**Normal Cleanup Flow:**
1. Spark application calls `unregisterShuffle()` when a shuffle completes
2. LifecycleManager waits for an expiration period, then sends `UnregisterShuffle` to Master
3. Master removes the shuffle ID from its active list
4. Master sends cleanup commands to workers during heartbeat
5. Workers delete shuffle files for unregistered shuffles from disk

**Application Failure Cleanup:**
- LifecycleManager sends periodic heartbeats to Master
- If Master detects application heartbeat timeout, it marks the application as failed
- Master tells workers to clean up all shuffle data for the failed application
- Workers remove files from disk based on Master's instructions

**Key Point:** Cleanup is coordinated by the Master based on application lifecycle, not by individual workers independently scanning their disks.

#### 2. Orphaned Data After Worker Restarts

When a worker restarts, orphaned shuffle files (files on disk but not in the worker's in-memory index) are handled through Master coordination:

**Cleanup Process:**
1. Worker restarts and re-registers with Master
2. Worker sends heartbeat with its current active shuffle IDs (from in-memory state)
3. Master compares worker's shuffle IDs with Master's authoritative list
4. Master tells worker to clean up any shuffle IDs that are no longer active
5. Worker scans disk and removes files for those shuffle IDs

**Important:** Workers do NOT automatically delete orphaned files on startup. Cleanup happens when:
- The application completes and unregisters the shuffle
- The application fails and Master detects heartbeat timeout
- Master explicitly tells the worker to clean up specific shuffle IDs

#### 3. Metadata Persistence for Rolling Upgrades

According to the [rolling upgrade documentation](https://celeborn.apache.org/docs/latest/upgrading/), Celeborn supports metadata persistence to enable reading existing shuffle data after worker restarts:

**With Graceful Shutdown Enabled:**
- Workers store shuffle file metadata in RocksDB during shutdown
- After restart, workers restore metadata from RocksDB
- This allows workers to serve existing shuffle files even after restart
- Configuration: `celeborn.worker.graceful.shutdown.enabled: true`

**Without Graceful Shutdown:**
- In-memory metadata is lost on restart
- Orphaned files remain on disk until Master-coordinated cleanup
- Spark relies on replicas for data availability

### Disk Space Management Considerations

**Orphaned Data Accumulation Risk:**

If workers restart frequently (e.g., during testing, configuration changes, or node issues), orphaned shuffle data can accumulate on disk because:
- Files remain on persistent volumes after restart
- Worker's in-memory index doesn't know about them
- Cleanup only happens when Master tells worker to remove specific shuffle IDs
- If applications are still running, Master won't trigger cleanup yet

**Monitoring Disk Usage:**

```bash
# Check disk usage on a worker
kubectl exec -n celeborn celeborn-worker-0 -- df -h | grep mnt

# Check shuffle data directory size
kubectl exec -n celeborn celeborn-worker-0 -- du -sh /mnt/disk1/celeborn-worker/shuffle_data
```

**Mitigation Strategies:**

1. **Enable Graceful Shutdown:** Set `celeborn.worker.graceful.shutdown.enabled: true` to persist metadata in RocksDB, allowing workers to track and serve existing files after restart

2. **Use Decommission API for Planned Restarts:** The decommission-based rolling restart approach drains active shuffle data before termination, reducing orphaned data accumulation

3. **Monitor Application Lifecycle:** Ensure Spark applications properly call `unregisterShuffle()` when jobs complete so Master can trigger cleanup

4. **Provision Adequate Storage:** Size EBS volumes with headroom for orphaned data between application completions (e.g., 1TB volumes for 500GB typical shuffle data)

5. **Periodic Worker Rotation:** In long-running clusters, consider periodic full worker rotation during maintenance windows to reset disk state

6. **Manual Cleanup (Emergency Only):** If disk space is critically low and applications have completed, you can manually delete shuffle data directories, but this should be a last resort:
   ```bash
   # DANGER: Only do this if you're certain no active jobs need the data
   kubectl exec -n celeborn celeborn-worker-0 -- rm -rf /mnt/disk1/celeborn-worker/shuffle_data/*
   ```

### Rolling Restart Best Practices

Rolling restarts are essential for production operations like version upgrades, configuration changes, and node maintenance. Celeborn supports zero-downtime rolling restarts when properly configured.

:::info What Triggers Automatic Rolling Restarts
When you update Celeborn configuration in Helm values (e.g., adding `celeborn.network.bind.preferIpAddress: "false"`), Kubernetes detects the ConfigMap change and automatically triggers a rolling restart of all worker pods. This happens as fast as pods become Ready (~13s between restarts). For controlled restarts with longer pauses, use the decommission-based script AFTER the config is deployed.
:::

#### Production Validation Results

We validated rolling restarts using a TPC-DS 10TB benchmark with 32 executors running for 15+ hours:

**Test Configuration:**
- 6 Celeborn workers (r8g.8xlarge: 32 vCPU, 256GB RAM)
- 4x 1000GB gp3 EBS volumes per worker
- Replication enabled (factor=2)
- All workers restarted during active shuffle operations

**Results:**
- ✅ Zero task failures across all 6 worker restarts
- ✅ Zero stage failures during 12-minute rolling restart window
- ✅ All 32 executors survived throughout
- ✅ 226 retry attempts all succeeded automatically
- ✅ Average restart time: ~13 seconds per worker
- ✅ Job completed successfully after 15+ hours including restarts

**Key Findings:**

1. **Fixed Ports Are Critical:** All 4 worker ports (rpc:9091, fetch:9092, push:9093, replicate:9094) must be set to non-zero values when graceful shutdown is enabled. Dynamic ports cause assertion failures.

2. **Replication Provides Resilience:** With replication factor=2, executors automatically fetch from replica workers when primary is unavailable. This is why replication is mandatory for zero-downtime restarts.

3. **Retry Configs Matter:** Client-side retry settings (maxRetriesForEachReplica: 5, retryWait: 15s) give workers sufficient time to restart (~13s) before exhausting retries.

4. **Revive Mechanism Works:** LifecycleManager automatically detects shutting-down workers and redirects new shuffle writes to available workers.

5. **Transient Errors Are Normal:** During rolling restarts, expect ERROR messages in logs for connection timeouts and fetch failures. These are automatically recovered through retries and do not indicate job failure. Monitor for task failures, not transient errors.

#### Two Approaches for Rolling Restarts

We validated two approaches - both work successfully with proper configuration, but they have different characteristics:

| Aspect | Decommission API | Simple Pod Delete |
|--------|------------------|-------------------|
| **Shuffle data handling** | Proactively drains before termination | Relies on graceful shutdown + replication |
| **Transient errors** | Minimal - workers reject new writes during drain | More frequent - connection timeouts during restart |
| **Retry attempts** | Fewer - clients redirected before worker stops | More - clients retry until worker restarts (~13s) |
| **Observability** | Full visibility via master API polling | Limited - only pod status |
| **Complexity** | Higher - requires API calls, port-forwarding, polling | Lower - simple kubectl delete |
| **Duration per worker** | Variable - depends on shuffle data volume | Predictable - ~13s restart + configurable pause |
| **Risk level** | Lower - explicit drain reduces edge cases | Moderate - depends on replication + retries |

**Decommission-Based Restart (RECOMMENDED for production):**
```bash
cd data-stacks/spark-on-eks/benchmarks/celeborn-benchmarks
export KUBECONFIG=../../kubeconfig.yaml
./rolling-restart-celeborn-with-decommission.sh
```

This script calls the decommission API, polls master to verify drain completion, deletes the pod, waits for Ready status, verifies re-registration, then proceeds to the next worker.

**Simple Pod Delete (acceptable for specific scenarios):**
```bash
cd data-stacks/spark-on-eks
export KUBECONFIG=kubeconfig.yaml
./scripts/rolling-restart-celeborn.sh 120  # 120s pause between workers
```

This script deletes pods one at a time, waits for Ready status, pauses for the specified duration, then proceeds to the next worker.

**When to Use Each Approach:**

Use **Decommission API** for:
- Planned maintenance windows (version upgrades, config changes)
- High-value production workloads where transient errors should be minimized
- Large shuffle volumes (>100GB) requiring controlled drain
- Multi-tenant clusters serving multiple teams simultaneously
- Risk-averse environments requiring maximum safety
- Compliance/audit requirements needing detailed operational logs

Use **Simple Pod Delete** for:
- Emergency recovery (worker stuck, unresponsive, CrashLoopBackOff)
- Development/testing environments
- Quick restarts where predictable timing is more important than minimizing retries
- Low shuffle activity scenarios
- Automated operations (CI/CD, GitOps) where simpler kubectl approach is easier
- Configuration-triggered restarts from Helm/ArgoCD

#### Prerequisites Checklist

Before performing rolling restarts in production, verify ALL of these configurations are in place:

:::danger Rolling Restart Prerequisites - ALL Must Be Configured
**If ANY of these are missing, rolling restarts WILL cause job failures.**

**Server-Side (Celeborn Helm values):**
- [ ] `celeborn.worker.graceful.shutdown.enabled: "true"`
- [ ] `celeborn.worker.rpc.port: "9091"` (fixed, NOT 0)
- [ ] `celeborn.worker.fetch.port: "9092"` (fixed, NOT 0)
- [ ] `celeborn.worker.push.port: "9093"` (fixed, NOT 0)
- [ ] `celeborn.worker.replicate.port: "9094"` (fixed, NOT 0)
- [ ] `celeborn.network.bind.preferIpAddress: "false"`
- [ ] `celeborn.master.heartbeat.worker.timeout: "180s"` (or higher)

**Client-Side (ALL Spark jobs):**
- [ ] `spark.celeborn.client.push.replicate.enabled: "true"` ← **MANDATORY**
- [ ] `spark.celeborn.client.fetch.maxRetriesForEachReplica: "5"` (or higher)
- [ ] `spark.celeborn.data.io.retryWait: "15s"` (or higher)
- [ ] `spark.celeborn.client.rpc.maxRetries: "5"` (or higher)
- [ ] `spark.sql.adaptive.localShuffleReader.enabled: "false"` ← **MUST BE FALSE**

**Verification Commands:**
```bash
# Verify server-side config
kubectl get configmap -n celeborn celeborn-config -o yaml | grep -E "graceful.shutdown|port|preferIpAddress|heartbeat"

# Verify worker pods have fixed ports
kubectl logs -n celeborn celeborn-worker-0 | grep "port"
# Should show: rpc.port=9091, fetch.port=9092, push.port=9093, replicate.port=9094

# Verify client-side config in running Spark job
kubectl logs -n spark-team-a <driver-pod> | grep -E "replicate.enabled|localShuffleReader"
# Should show: replicate.enabled=true, localShuffleReader.enabled=false
```
:::

**Expected Behavior During Restarts:**
- FileNotFoundException errors for shuffle files on restarted workers (normal - Spark fetches from replicas)
- Connection timeout errors during ~13s restart window (normal - clients retry automatically)
- Revive events when workers enter graceful shutdown (normal - redirects new writes to available workers)
- Zero task failures if replication and retry configs are properly set

**Monitoring During Restarts:**
```bash
# Watch worker status
kubectl get pods -n celeborn -l app.kubernetes.io/role=worker -w

# Monitor Spark executors
kubectl get pods -n <namespace> -l spark-role=executor

# Check for Revive events (normal during restarts)
kubectl logs <driver-pod> -n <namespace> | grep -i "revive\|shutting"

# Check retry attempts (normal during restarts)
kubectl logs <executor-pod> -n <namespace> | grep -i "retry"
```

**What to Look For:**

✅ Normal (expected during restarts):
- ERROR messages for connection timeouts
- ERROR messages for fetch failures
- WARN messages for retry attempts
- "Current worker is shutting down!" messages
- "Destroyed partitions" messages

❌ Abnormal (indicates real problems):
- Task failures in driver logs
- Executor pod restarts or crashes
- "FetchFailed" exceptions that exhaust all retries
- Job termination or stage failures

## Scaling to 200+ Nodes

Operating Celeborn at scale (200+ worker nodes) requires careful planning for capacity, networking, and operational procedures.

### Capacity Planning

**Worker Node Sizing:**

For large-scale deployments, choose instance types based on your shuffle characteristics:

| Instance Type | vCPU | RAM | Network | Storage | Best For |
|---------------|------|-----|---------|---------|----------|
| **r8g.8xlarge** | 32 | 256GB | 12.5 Gbps | 4x NVMe or EBS | Balanced, memory-intensive shuffles |
| **r8g.12xlarge** | 48 | 384GB | 18.75 Gbps | 4x NVMe or EBS | Large partition counts, high concurrency |
| **i4i.8xlarge** | 32 | 256GB | 18.75 Gbps | 2x 3.75TB NVMe | Maximum I/O performance |
| **c7gn.16xlarge** | 64 | 128GB | 100 Gbps | EBS only | Network-bound shuffles, small partitions |

**Sizing Formula:**

```
Workers needed = (Peak concurrent executors × Avg shuffle per executor) / Worker capacity

Example:
- 2000 concurrent executors
- 50GB average shuffle data per executor
- r8g.8xlarge workers (4TB usable storage, 200GB/s aggregate throughput)
- Target 70% utilization

Workers = (2000 × 50GB) / (4TB × 0.7) = 36 workers minimum
Recommended: 50-60 workers (includes headroom for failures, maintenance)
```

:::tip Production Recommendation
For 200+ node clusters, deploy workers in batches of 20-30 nodes. This allows gradual capacity validation and easier troubleshooting if issues arise. Use Karpenter NodePools with taints to control which workers accept traffic during rollout.
:::

### Network Considerations

**Network Bandwidth Planning:**

Celeborn is network-intensive. Each worker needs sufficient bandwidth for:
- Push operations (executors → workers)
- Fetch operations (workers → executors)
- Replication traffic (worker → worker)

**Bandwidth Formula:**
```
Required bandwidth per worker = (Concurrent push streams × Push rate) + (Concurrent fetch streams × Fetch rate) + Replication overhead

Example for r8g.8xlarge (12.5 Gbps network):
- 100 concurrent push streams × 100 MB/s = 10 GB/s
- 50 concurrent fetch streams × 200 MB/s = 10 GB/s
- Replication overhead (2x writes) = 10 GB/s
Total: 30 GB/s required → r8g.8xlarge is undersized

Better choice: c7gn.16xlarge (100 Gbps) or multiple smaller workers
```

:::warning Network Bottlenecks at Scale
At 200+ nodes, network bandwidth becomes the primary bottleneck. Monitor network saturation metrics and consider:
- Using enhanced networking instances (c7gn, i4i series)
- Deploying more workers with smaller instance types to distribute network load
- Enabling jumbo frames (MTU 9001) on EKS for better throughput
- Using placement groups for low-latency worker-to-worker replication
:::

### Master Scaling

**Master Node Requirements:**

Masters are CPU and memory-intensive for metadata management. At 200+ workers:

| Workers | Masters | Instance Type | Heap Size | Notes |
|---------|---------|---------------|-----------|-------|
| 1-50 | 3 | r8g.xlarge | 8GB | Standard deployment |
| 51-100 | 3 | r8g.2xlarge | 16GB | Increased metadata load |
| 101-200 | 5 | r8g.4xlarge | 32GB | High availability critical |
| 201-500 | 5-7 | r8g.8xlarge | 64GB | Enterprise scale |

:::danger Master Overload Symptoms
If masters are undersized, you'll see:
- Slow worker registration (>30s)
- Heartbeat timeouts causing false worker failures
- Slot reservation failures with "Master is busy" errors
- Increased Revive frequency due to master unavailability

Monitor master CPU and heap usage closely. Scale vertically (larger instances) before scaling horizontally (more masters).
:::

### Configuration Tuning for Large Clusters

**Master Configuration (200+ workers):**

```yaml
celeborn:
  # Increase worker capacity limits
  celeborn.master.slot.assign.maxWorkers: "10000"

  # Tune heartbeat intervals for scale
  celeborn.master.heartbeat.worker.timeout: "180s"
  celeborn.worker.heartbeat.timeout: "120s"

  # Increase thread pools for concurrent operations
  celeborn.master.rpc.dispatcher.numThreads: "64"
  celeborn.master.slot.assign.threads: "32"

  # Metadata management
  celeborn.master.estimatedPartitionSize.update.interval: "10s"
  celeborn.master.estimatedPartitionSize.initialSize: "64mb"

  # Garbage collection tuning
  celeborn.master.gc.interval: "300s"
  celeborn.master.gc.threads: "16"
```

**Worker Configuration (high concurrency):**

```yaml
celeborn:
  # Increase connection limits
  celeborn.worker.rpc.io.threads: "64"
  celeborn.worker.fetch.io.threads: "64"
  celeborn.worker.push.io.threads: "64"

  # Buffer management for high throughput
  celeborn.worker.directMemoryRatioForReadBuffer: "0.3"
  celeborn.worker.directMemoryRatioForShuffleStorage: "0.3"
  celeborn.worker.directMemoryRatioToResume: "0.5"

  # Disk I/O tuning
  celeborn.worker.flusher.threads: "32"
  celeborn.worker.flusher.buffer.size: "256k"

  # Commit thread pool
  celeborn.worker.commitFiles.threads: "128"
  celeborn.worker.commitFiles.timeout: "120s"
```

:::tip Performance Tuning
Start with default configurations and tune based on metrics. Over-tuning thread pools can cause excessive context switching and degrade performance. Monitor CPU utilization and thread pool queue depths before increasing thread counts.
:::

### Rolling Restart Strategy for Large Clusters

**Phased Restart Approach (200+ workers):**

For large clusters, restart workers in phases to minimize risk:

**Phase 1: Canary (5% of workers)**
```bash
# Restart first 10 workers (out of 200)
for i in {0..9}; do
  ./rolling-restart-celeborn-with-decommission.sh celeborn-worker-$i
  # Monitor for 10 minutes before proceeding
done
```

**Phase 2: Progressive Rollout (20% batches)**
```bash
# Restart in batches of 40 workers
for batch in {10..49} {50..89} {90..129} {130..169} {170..199}; do
  ./rolling-restart-celeborn-with-decommission.sh celeborn-worker-$batch
  # 5-minute pause between batches
  sleep 300
done
```

**Phase 3: Validation**
```bash
# Verify all workers registered
kubectl get pods -n celeborn -l app.kubernetes.io/role=worker | grep Running | wc -l

# Check master sees all workers
kubectl port-forward -n celeborn celeborn-master-0 9098:9098
curl http://localhost:9098/api/v1/workers | jq '.workers | length'
```

:::warning Large-Scale Restart Duration
A full rolling restart of 200 workers with decommission takes approximately 6-8 hours (2-3 minutes per worker including drain time). Plan maintenance windows accordingly and consider:
- Pausing non-critical Spark jobs during maintenance
- Increasing retry timeouts for critical jobs
- Monitoring master CPU/memory during restart (metadata churn is high)
- Having rollback plan if issues detected in canary phase
:::

### EKS and AMI Upgrade Procedures

**Node Replacement Strategy:**

When upgrading EKS versions or AMIs, nodes are replaced (not restarted in-place). This requires careful coordination:

**Option 1: Karpenter-Managed Replacement (Recommended)**

```yaml
# Update NodePool with new AMI/EKS version
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: celeborn-workers
spec:
  template:
    spec:
      requirements:
        - key: karpenter.k8s.aws/instance-family
          operator: In
          values: ["r8g"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
      nodeClassRef:
        name: celeborn-node-class
  disruption:
    consolidationPolicy: WhenEmpty
    expireAfter: 720h
```

```yaml
# Update EC2NodeClass with new AMI
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: celeborn-node-class
spec:
  amiFamily: AL2
  amiSelectorTerms:
    - id: ami-new-version-id  # Updated AMI
  role: KarpenterNodeRole
```

**Procedure:**
1. Update EC2NodeClass with new AMI ID
2. Cordon old nodes: `kubectl cordon <node-name>`
3. Decommission workers on old nodes using API
4. Drain nodes: `kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data`
5. Karpenter provisions new nodes with updated AMI
6. Workers schedule on new nodes and register with master
7. Verify worker count and health before proceeding to next batch

:::danger CRITICAL: Always Decommission Before Draining Nodes
When replacing nodes (EKS upgrades, AMI updates), you **MUST** decommission Celeborn workers BEFORE draining the node.

**Correct Order:**
1. ✅ Call decommission API on worker
2. ✅ Wait for drain completion (poll master API)
3. ✅ Drain node (`kubectl drain`)
4. ✅ Delete node (Karpenter replaces automatically)

**Wrong Order (causes problems):**
1. ❌ Drain node immediately
2. ❌ Worker forcefully terminated
3. ❌ Active shuffle data lost
4. ❌ Massive retry storms in Spark jobs
5. ❌ Potential job failures even with replication

**Why this matters:**
- Decommissioning gracefully drains shuffle data before termination
- Draining without decommissioning causes abrupt worker termination
- Even with replication, abrupt termination causes retry storms and job slowdowns
- With NVMe instance stores, abrupt termination can cause data loss if replica is also on a dying node

**Script to use:** `rolling-restart-celeborn-with-decommission.sh` (handles decommission automatically)
:::

**Option 2: Blue-Green Node Pool**

For maximum safety, deploy a new node pool alongside the existing one:

```bash
# Deploy new NodePool with updated AMI
kubectl apply -f celeborn-nodepool-v2.yaml

# Scale up new worker StatefulSet
kubectl scale statefulset celeborn-worker-v2 -n celeborn --replicas=200

# Wait for all new workers to register
# Monitor master API for worker count

# Decommission old workers in batches
for i in {0..199}; do
  curl -X POST http://celeborn-master:9098/api/v1/workers/celeborn-worker-$i/exit
done

# Wait for all old workers to drain
# Monitor master API for decommissioning status

# Delete old StatefulSet
kubectl delete statefulset celeborn-worker -n celeborn

# Delete old NodePool
kubectl delete nodepool celeborn-workers-v1
```

:::tip Blue-Green Advantages
Blue-green node pool replacement provides:
- Zero risk of capacity shortage (both pools active during transition)
- Instant rollback capability (keep old pool until validation complete)
- No impact on active workloads (new workers absorb traffic gradually)
- Better for risk-averse environments (financial, healthcare, compliance)

Trade-off: Requires 2x capacity during transition (cost consideration for large clusters)
:::

## Troubleshooting Common Scenarios

### Scenario 1: Workers Not Registering After Restart

**Symptoms:**
- Worker pod shows Running but not in master's worker list
- Logs show: `Failed to register with master` or `Connection refused`

**Root Causes:**

1. **Network binding misconfiguration:**
```bash
# Check worker logs
kubectl logs -n celeborn celeborn-worker-0 | grep "bind"

# If you see pod IP instead of DNS name, add:
celeborn.network.bind.preferIpAddress: "false"
```

2. **Fixed ports not configured:**
```bash
# Check if ports are dynamic (0)
kubectl logs -n celeborn celeborn-worker-0 | grep "port"

# Should see: rpc.port=9091, fetch.port=9092, push.port=9093, replicate.port=9094
# If you see port=0, graceful shutdown will fail
```

3. **Master endpoint unreachable:**
```bash
# Test connectivity from worker pod
kubectl exec -n celeborn celeborn-worker-0 -- curl -v celeborn-master-0.celeborn-master-svc:9097

# Check master logs for registration attempts
kubectl logs -n celeborn celeborn-master-0 | grep "register"
```

**Resolution:**
```yaml
# Update Helm values
celeborn:
  celeborn.network.bind.preferIpAddress: "false"
  celeborn.worker.rpc.port: "9091"
  celeborn.worker.fetch.port: "9092"
  celeborn.worker.push.port: "9093"
  celeborn.worker.replicate.port: "9094"

# Restart workers after config update
```

### Scenario 2: Disk Space Exhaustion

**Symptoms:**
- Workers rejecting new shuffle writes
- Logs show: `No space left on device` or `Disk usage exceeds threshold`

**Diagnosis:**
```bash
# Check disk usage on all workers
for i in {0..5}; do
  echo "Worker $i:"
  kubectl exec -n celeborn celeborn-worker-$i -- df -h | grep mnt
done

# Check shuffle data directory sizes
kubectl exec -n celeborn celeborn-worker-0 -- du -sh /mnt/disk*/celeborn-worker/shuffle_data
```

**Root Causes:**

1. **Orphaned shuffle data accumulation** (workers restarted frequently without cleanup)
2. **Long-running applications** (shuffle data not cleaned up until app completes)
3. **Undersized storage** (insufficient capacity for workload)

**Immediate Mitigation:**
```bash
# Check for completed applications
kubectl port-forward -n celeborn celeborn-master-0 9098:9098
curl http://localhost:9098/api/v1/applications | jq '.applications[] | select(.status=="COMPLETED")'

# Trigger manual cleanup (DANGER: only if applications are truly completed)
# This forces master to send cleanup commands to workers
curl -X POST http://localhost:9098/api/v1/gc
```

**Long-Term Solutions:**

1. **Enable graceful shutdown with metadata persistence:**
```yaml
celeborn:
  celeborn.worker.graceful.shutdown.enabled: "true"
  # This persists metadata to RocksDB, enabling better cleanup tracking
```

2. **Increase storage capacity:**
```bash
# Resize EBS volumes (requires PVC resize)
kubectl patch pvc celeborn-worker-data-0 -n celeborn -p '{"spec":{"resources":{"requests":{"storage":"2000Gi"}}}}'

# Wait for resize to complete
kubectl get pvc -n celeborn -w
```

3. **Tune garbage collection:**
```yaml
celeborn:
  celeborn.master.gc.interval: "180s"  # More frequent GC
  celeborn.master.gc.threads: "16"     # More GC threads
  celeborn.worker.gc.checkInterval: "60s"
```

:::warning Emergency Disk Cleanup
If disk space is critically low (>95%) and applications have completed, you can manually delete shuffle data:

```bash
# DANGER: Only do this if you're certain no active jobs need the data
# Check for active applications first
curl http://localhost:9098/api/v1/applications | jq '.applications[] | select(.status=="RUNNING")'

# If no active applications, safe to clean
kubectl exec -n celeborn celeborn-worker-0 -- rm -rf /mnt/disk1/celeborn-worker/shuffle_data/*
```

This should be a LAST RESORT. Proper solution is fixing GC configuration and capacity planning.
:::

### Scenario 3: High Retry Rates During Normal Operations

**Symptoms:**
- Spark jobs show high retry counts even without restarts
- Logs show frequent: `Fetch chunk failed`, `Retry create client`

**Diagnosis:**
```bash
# Check worker health
kubectl get pods -n celeborn -l app.kubernetes.io/role=worker

# Check for worker restarts
kubectl get pods -n celeborn -l app.kubernetes.io/role=worker -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].restartCount}{"\n"}{end}'

# Check network connectivity
kubectl exec -n celeborn celeborn-worker-0 -- ping -c 5 celeborn-worker-1.celeborn-worker-svc
```

**Root Causes:**

1. **Network saturation** (workers exceeding network bandwidth)
2. **Worker overload** (too many concurrent connections)
3. **Insufficient retry timeouts** (clients giving up too quickly)

**Resolution:**

1. **Scale out workers** (distribute load):
```bash
kubectl scale statefulset celeborn-worker -n celeborn --replicas=12
```

2. **Increase client retry configuration:**
```yaml
sparkConf:
  spark.celeborn.client.fetch.maxRetriesForEachReplica: "10"  # Increased from 5
  spark.celeborn.data.io.retryWait: "20s"  # Increased from 15s
  spark.celeborn.client.rpc.maxRetries: "10"
```

3. **Tune worker thread pools:**
```yaml
celeborn:
  celeborn.worker.fetch.io.threads: "128"  # Increased from 64
  celeborn.worker.push.io.threads: "128"
```

### Scenario 4: Master Failover Not Working

**Symptoms:**
- Master pod crashes but clients don't failover to other masters
- Logs show: `All masters unreachable` or `Connection refused to all endpoints`

**Diagnosis:**
```bash
# Check master pod status
kubectl get pods -n celeborn -l app.kubernetes.io/role=master

# Check master endpoints
kubectl get endpoints -n celeborn celeborn-master-svc

# Test connectivity to all masters
for i in {0..2}; do
  kubectl exec -n spark-team-a <executor-pod> -- curl -v celeborn-master-$i.celeborn-master-svc:9097
done
```

**Root Causes:**

1. **Client configuration has only one master endpoint** (no HA)
2. **Network policy blocking cross-namespace communication**
3. **DNS resolution issues** (CoreDNS overloaded)

**Resolution:**

1. **Update client configuration with all master endpoints:**
```yaml
sparkConf:
  spark.celeborn.master.endpoints: "celeborn-master-0.celeborn-master-svc.celeborn.svc.cluster.local:9097,celeborn-master-1.celeborn-master-svc.celeborn.svc.cluster.local:9097,celeborn-master-2.celeborn-master-svc.celeborn.svc.cluster.local:9097"
```

2. **Verify network policies allow traffic:**
```bash
kubectl get networkpolicies -n celeborn
kubectl get networkpolicies -n spark-team-a

# Ensure policies allow egress to celeborn namespace
```

3. **Scale CoreDNS if DNS resolution is slow:**
```bash
kubectl scale deployment coredns -n kube-system --replicas=5
```

## Monitoring

Comprehensive monitoring is critical for operating Celeborn at scale. Use the community-maintained [Grafana dashboards](https://github.com/apache/celeborn/tree/main/assets/grafana) as a starting point.

### Key Metrics to Monitor

**Worker Health Metrics:**

| Metric | Alert Threshold | Description | Action |
|--------|----------------|-------------|--------|
| `celeborn_worker_available_count` | < 80% of expected | Workers registered with master | Check worker logs, network connectivity |
| `celeborn_worker_excluded_count` | > 0 | Workers excluded due to failures | Investigate excluded workers, check disk space |
| `celeborn_worker_lost_count` | > 0 | Workers lost (heartbeat timeout) | Check network, master capacity, worker health |
| `celeborn_worker_shutdown_count` | > 0 (outside maintenance) | Workers in graceful shutdown | Verify no unplanned restarts |
| `celeborn_worker_disk_usage_percent` | > 85% | Disk space utilization | Scale storage, tune GC, check for orphaned data |
| `celeborn_worker_memory_usage_percent` | > 90% | Direct memory utilization | Tune memory ratios, scale workers |

**Shuffle Performance Metrics:**

| Metric | Alert Threshold | Description | Action |
|--------|----------------|-------------|--------|
| `celeborn_shuffle_write_throughput_mb_per_sec` | < 50% of baseline | Write throughput per worker | Check network saturation, disk I/O, thread pools |
| `celeborn_shuffle_read_throughput_mb_per_sec` | < 50% of baseline | Read throughput per worker | Check network saturation, fetch thread pools |
| `celeborn_shuffle_push_data_fail_count` | > 100/min | Failed push operations | Check worker availability, replication config |
| `celeborn_shuffle_fetch_data_fail_count` | > 100/min | Failed fetch operations | Check worker availability, retry config |
| `celeborn_shuffle_commit_files_fail_count` | > 10/min | Failed commit operations | Check disk space, commit thread pool |

**Master Health Metrics:**

| Metric | Alert Threshold | Description | Action |
|--------|----------------|-------------|--------|
| `celeborn_master_registered_shuffle_count` | Sudden drop | Active shuffles tracked | Check for master restarts, application failures |
| `celeborn_master_slot_allocation_latency_p99` | > 5000ms | Slot allocation latency | Scale master vertically, tune thread pools |
| `celeborn_master_heartbeat_from_worker_latency_p99` | > 10000ms | Worker heartbeat processing | Scale master, check network |
| `celeborn_master_heap_usage_percent` | > 85% | JVM heap utilization | Scale master vertically, tune heap size |
| `celeborn_master_gc_time_percent` | > 10% | GC overhead | Tune GC settings, scale master |

**Client-Side Metrics (Spark):**

Monitor these metrics from Spark executors to detect Celeborn issues:

```bash
# Fetch retry rate (should be low during normal operations)
spark_executor_celeborn_fetch_retry_count

# Push retry rate (should be low during normal operations)
spark_executor_celeborn_push_retry_count

# Revive frequency (indicates worker unavailability)
spark_driver_celeborn_revive_count
```

### Alerting Rules

**Critical Alerts (Page immediately):**

```yaml
# Worker availability below 80%
- alert: CelebornWorkerAvailabilityLow
  expr: celeborn_worker_available_count / celeborn_worker_expected_count < 0.8
  for: 5m
  annotations:
    summary: "Celeborn worker availability is {{ $value }}%"
    description: "Less than 80% of expected workers are available. Active Spark jobs may fail."

# Disk space critical
- alert: CelebornWorkerDiskSpaceCritical
  expr: celeborn_worker_disk_usage_percent > 95
  for: 2m
  annotations:
    summary: "Worker {{ $labels.worker_id }} disk usage is {{ $value }}%"
    description: "Disk space critically low. Worker will reject new shuffle writes."

# Master unavailable
- alert: CelebornMasterUnavailable
  expr: up{job="celeborn-master"} == 0
  for: 1m
  annotations:
    summary: "Celeborn master {{ $labels.instance }} is down"
    description: "Master unavailable. Check pod status and logs immediately."
```

**Warning Alerts (Investigate within 30 minutes):**

```yaml
# High retry rate
- alert: CelebornHighRetryRate
  expr: rate(celeborn_shuffle_fetch_data_fail_count[5m]) > 100
  for: 10m
  annotations:
    summary: "High fetch retry rate: {{ $value }} failures/sec"
    description: "Elevated retry rate may indicate network issues or worker overload."

# Disk space warning
- alert: CelebornWorkerDiskSpaceWarning
  expr: celeborn_worker_disk_usage_percent > 85
  for: 15m
  annotations:
    summary: "Worker {{ $labels.worker_id }} disk usage is {{ $value }}%"
    description: "Disk space approaching limit. Plan capacity expansion or cleanup."

# GC overhead high
- alert: CelebornMasterGCOverhead
  expr: celeborn_master_gc_time_percent > 10
  for: 15m
  annotations:
    summary: "Master GC overhead is {{ $value }}%"
    description: "High GC overhead may indicate undersized heap or memory leak."
```

### Grafana Dashboard Recommendations

Import the official Celeborn dashboards and customize for your environment:

**Dashboard 1: Cluster Overview**
- Worker availability (available, excluded, lost, shutdown)
- Total shuffle data volume (read + write)
- Active shuffle count
- Master CPU and memory usage

**Dashboard 2: Worker Performance**
- Per-worker disk usage (heatmap)
- Per-worker network throughput (time series)
- Per-worker shuffle operations (push, fetch, commit)
- Thread pool utilization (fetch, push, commit threads)

**Dashboard 3: Shuffle Operations**
- Shuffle write throughput (MB/s)
- Shuffle read throughput (MB/s)
- Push/fetch failure rates
- Commit latency (p50, p95, p99)

**Dashboard 4: Client Metrics (Spark)**
- Retry rates per executor
- Revive frequency per application
- Shuffle data volume per application
- Fetch latency distribution

:::tip Dashboard Best Practices
For 200+ node clusters, use aggregated views (sum, avg) rather than per-worker graphs to avoid overwhelming Grafana. Create separate dashboards for:
- Executive view (cluster-level KPIs)
- Operations view (worker health, alerts)
- Performance view (throughput, latency, bottlenecks)
- Troubleshooting view (per-worker details, error rates)
:::

### Log Aggregation

Centralize logs from all Celeborn components for troubleshooting:

**Recommended Stack:**
- **Fluent Bit** (log collection from pods)
- **Amazon OpenSearch** or **Elasticsearch** (log storage and indexing)
- **Kibana** or **OpenSearch Dashboards** (log visualization)

**Key Log Patterns to Index:**

```bash
# Worker registration events
"Successfully registered with master"
"Failed to register with master"

# Graceful shutdown events
"Graceful shutdown started"
"Graceful shutdown completed"

# Disk space warnings
"Disk usage exceeds threshold"
"No space left on device"

# Replication failures
"Failed to replicate partition"
"Replica worker unavailable"

# Client errors
"FetchFailed"
"PushFailed"
"Connection refused"
```

**Useful Kibana Queries:**

```
# Find workers with registration issues
kubernetes.namespace:"celeborn" AND message:"Failed to register"

# Find disk space warnings
kubernetes.namespace:"celeborn" AND message:"Disk usage exceeds"

# Find replication failures
kubernetes.namespace:"celeborn" AND message:"Failed to replicate"

# Find client fetch failures
kubernetes.namespace:"spark-team-a" AND message:"FetchFailed"
```

## Production Readiness Checklist

Before deploying Celeborn to production or performing major maintenance, verify this checklist:

### Pre-Deployment Checklist

**Infrastructure:**
- [ ] EKS cluster version is supported (1.28+)
- [ ] Karpenter installed and configured for Celeborn NodePool
- [ ] Storage provisioned (EBS gp3 or instance stores)
- [ ] Network bandwidth sufficient for workload (see capacity planning)
- [ ] Security groups allow traffic between Spark and Celeborn namespaces

**Celeborn Configuration:**
- [ ] Fixed ports configured (rpc:9091, fetch:9092, push:9093, replicate:9094)
- [ ] Graceful shutdown enabled (`celeborn.worker.graceful.shutdown.enabled: true`)
- [ ] Network binding set (`celeborn.network.bind.preferIpAddress: "false"`)
- [ ] Master heartbeat timeout increased (`celeborn.master.heartbeat.worker.timeout: 180s`)
- [ ] Storage directories configured with correct capacity
- [ ] Master HA configured (3+ masters)

**Client Configuration (All Spark Jobs):**
- [ ] Replication enabled (`spark.celeborn.client.push.replicate.enabled: true`)
- [ ] Retry configuration set (`maxRetriesForEachReplica: 5`, `retryWait: 15s`)
- [ ] Local shuffle reader disabled (`spark.sql.adaptive.localShuffleReader.enabled: false`)
- [ ] Master endpoints include all masters (comma-separated)
- [ ] Network timeouts generous (`spark.network.timeout: 2000s`)

**Monitoring:**
- [ ] Prometheus scraping Celeborn metrics
- [ ] Grafana dashboards imported and customized
- [ ] Critical alerts configured (worker availability, disk space, master health)
- [ ] Log aggregation configured (Fluent Bit → OpenSearch/Elasticsearch)
- [ ] On-call rotation defined for Celeborn alerts

**Testing:**
- [ ] Smoke test completed (simple Spark job with shuffle)
- [ ] Load test completed (TPC-DS or production-like workload)
- [ ] Rolling restart tested in staging environment
- [ ] Failover tested (kill master pod, verify client failover)
- [ ] Disk space exhaustion tested (verify GC cleanup works)

### Pre-Maintenance Checklist

Before performing rolling restarts or upgrades:

**Preparation:**
- [ ] Maintenance window scheduled and communicated
- [ ] Backup of current Helm values and configurations
- [ ] Rollback plan documented
- [ ] Monitoring dashboards open and ready
- [ ] On-call engineer available during maintenance

**Validation:**
- [ ] All prerequisites verified (see "Prerequisites Checklist" in Rolling Restart section)
- [ ] No active critical Spark jobs (or jobs configured for restarts)
- [ ] Worker count matches expected (`kubectl get pods -n celeborn`)
- [ ] All workers registered with master (check master API)
- [ ] Disk space below 70% on all workers
- [ ] No existing alerts firing

**Execution:**
- [ ] Start with canary phase (5% of workers)
- [ ] Monitor for 10-15 minutes after canary
- [ ] Proceed with progressive rollout if canary successful
- [ ] Monitor metrics continuously during rollout
- [ ] Document any issues encountered

**Post-Maintenance:**
- [ ] All workers registered and healthy
- [ ] Worker count matches expected
- [ ] No alerts firing
- [ ] Smoke test passed (run simple Spark job)
- [ ] Metrics returned to baseline
- [ ] Maintenance report documented

:::tip Maintenance Window Planning
For 200-worker clusters:
- **Canary phase:** 1 hour (10 workers + monitoring)
- **Progressive rollout:** 6-8 hours (190 workers at 2-3 min each)
- **Validation:** 1 hour (smoke tests, metric validation)
- **Total:** 8-10 hours

Schedule maintenance during lowest traffic periods (weekends, holidays) and ensure adequate staffing for the entire window.
:::

## Summary

Operating Apache Celeborn at scale requires careful planning, robust monitoring, and disciplined operational procedures. Key takeaways:

1. **Configuration is Critical:** Fixed ports, graceful shutdown, replication, and retry settings are non-negotiable for zero-downtime operations.

2. **Capacity Planning Matters:** Size workers based on shuffle volume, network bandwidth, and concurrency requirements. Plan for 30-50% headroom.

3. **Monitoring is Essential:** Implement comprehensive metrics, alerting, and log aggregation before going to production.

4. **Rolling Restarts Work:** With proper configuration, Celeborn supports zero-downtime rolling restarts for maintenance and upgrades.

5. **Test Everything:** Validate rolling restarts, failover, and disk exhaustion scenarios in staging before production deployment.

6. **Scale Gradually:** For 200+ node clusters, deploy and restart in phases. Validate each phase before proceeding.

7. **Document Procedures:** Maintain runbooks for common scenarios (rolling restart, disk cleanup, failover, scaling).

For questions or issues, refer to the [Apache Celeborn documentation](https://celeborn.apache.org/docs/latest/) or engage with the community on the [Celeborn mailing list](https://celeborn.apache.org/community/).
