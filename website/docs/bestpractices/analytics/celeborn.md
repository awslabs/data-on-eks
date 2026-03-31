---
sidebar_position: 4
sidebar_label: Apache Celeborn Best Practices
---


# Apache Celeborn: Best Practices


Apache Celeborn is a Remote Shuffle Service (RSS) that externalizes Spark shuffle data to dedicated worker nodes — decoupling executor lifecycle from shuffle storage, enabling true dynamic allocation, and eliminating the performance bottleneck of local-disk shuffle at scale.


## Table of Contents


- [Architecture Fundamentals](#architecture-fundamentals)
- [Decision 1: AZ Topology](#decision-1-az-topology)
- [Decision 2: Instance Type by Scale](#decision-2-instance-type-by-scale)
- [Decision 3: EBS vs NVMe Storage](#decision-3-ebs-vs-nvme-storage)
- [Configuration](#configuration)
- [Day 2 Operations](#day-2-operations)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)


---


## Architecture Fundamentals


[![Default Spark Shuffle vs Celeborn](../../benchmarks/img/spark-shuffler-architecture.png)](../../benchmarks/img/spark-shuffler-architecture.png)


[![Celeborn Architecture](../../benchmarks/img/celeborn-architecture.png)](../../benchmarks/img/celeborn-architecture.png)


**Three components:**
- **Masters (3+):** Slot assignment, worker health tracking, shuffle metadata. HA via Raft consensus — deploy as odd numbers (3, 5, 7).
- **Workers (N):** Shuffle data storage and serving. Scale horizontally. **One pod per node** — this is enforced in the official Helm chart and is non-negotiable for performance.
- **Spark Client:** Embedded in executors. Handles retries, replica selection, and failover.


**Sizing ratio** (from [official Celeborn planning docs](https://celeborn.apache.org/docs/latest/deployment/cluster_planning/)):
```
vCPU : Memory (GB) : Network (Gbps) : Disk IOPS (K) = 2 : 5 : 2 : 1
```
A worker with 32 vCPU ideally pairs with 80GB RAM, 32 Gbps network, and 16K IOPS disk — use this to validate instance choices.


:::note When to Use Celeborn
Not all Spark workloads need Celeborn. Use Celeborn when you need:
- **Dynamic allocation** - scale executors up/down without losing shuffle data
- **Large shuffle volumes** - > 100GB shuffle data per job
- **High concurrency** - multiple jobs sharing shuffle infrastructure
- **Fault tolerance** - survive executor failures without recomputing stages

For small jobs (&lt; 10GB shuffle), streaming workloads, or single-executor jobs, default Spark shuffle is often sufficient.
:::


---


## Decision 1: AZ Topology


### Masters: Spread Across 3 AZs


Deploy one master per AZ (3 total). Raft requires a majority (2/3) — losing one AZ leaves 2 masters running and Celeborn's control plane stays up. Masters hold only metadata, so cross-AZ master traffic is negligible.


**This is the main reason to care about multi-AZ at all for Celeborn.** With masters healthy across AZs, you can provision new worker nodes in AZ2 or AZ3 immediately after an AZ failure — without redeploying or reconfiguring the masters. The cluster recovers for the next batch of jobs with no control plane work.


### Workers: Single AZ, Co-Located with Executors


**Keep workers in the same AZ as your Spark executor nodes.** Do not spread workers across AZs.


Here is why: every shuffle push (executor → worker) and fetch (worker → executor) that crosses an AZ boundary costs **$0.01/GB** on AWS. With replication, that doubles. At terabyte-scale shuffle volumes this is a significant and avoidable cost. More importantly — if an AZ fails, the Spark executors running in that AZ fail too. The job is lost regardless of where the workers are. Cross-AZ worker spread adds cost and latency with no practical resilience benefit for Spark jobs.


**The nuance:** this only works cleanly if your Spark executor node pools are also AZ-pinned. EKS defaults to multi-AZ node groups — if executors spread across AZ1/AZ2/AZ3 and workers are only in AZ1, two-thirds of your executors are already paying cross-AZ costs on every push and fetch. Pin your executor node pools to the same AZ as workers using node affinity or Karpenter NodePool constraints.


```yaml
# Karpenter NodePool — pin Celeborn workers to a single AZ
spec:
 template:
   spec:
     requirements:
       - key: topology.kubernetes.io/zone
         operator: In
         values: ["us-east-1a"]   # same AZ as your Spark executor node pool
       - key: karpenter.sh/capacity-type
         operator: In
         values: ["on-demand"]
```


**AZ failure recovery pattern:**
1. AZ1 fails → workers in AZ1 go down → in-flight jobs fail (executors in AZ1 also gone)
2. Masters in AZ2 and AZ3 are still running (Raft majority intact)
3. Scale up new Celeborn worker nodes in AZ2 — masters register them automatically
4. New Spark jobs submit and run against workers in AZ2
5. Recovery time: time to provision nodes + worker startup (~2-3 minutes with Karpenter)


:::tip The single-AZ worker + 3-AZ master architecture gives you the right tradeoff: zero cross-AZ shuffle costs during normal operation, fast recovery after AZ failure without any master redeployment.
:::


---


## Decision 2: Instance Type by Scale


### Shuffle Volume is Not Dataset Size


The most common sizing mistake: customers assume shuffle data scales linearly with dataset size. It does not. For analytical workloads like TPC-DS, peak concurrent shuffle is typically **5–15% of total dataset size**, depending on query mix, parallelism, and concurrency.


**Validated with TPC-DS 10TB benchmark:**
- Dataset size: 10 TB
- Total shuffle data written: **4.7 TB** (4736 GB across all workers)
- Shuffle as % of dataset: **47%**
- Cluster: 6 x r8g.8xlarge workers with 4x1TB EBS each (24TB total capacity)
- Disk utilization: **19.7%** (4.7 TB / 24 TB)
- Per-worker distribution: 937GB (24%), 878GB (22%), 993GB (25%), 817GB (21%), 637GB (16%), 474GB (12%)
- Resource usage: CPU &lt;1%, Memory ~2%


**Key insight:** The r8g.8xlarge handled this comfortably with minimal resource pressure across all dimensions (CPU, memory, disk, network).


**Implication:** Scale out with r8g.8xlarge first. Add more workers before reaching for larger instances. Adding workers distributes both network and disk load.


### Scale Tiers


| Scale Tier | Typical Dataset | Peak Concurrent Shuffle | Approach | Instance | Storage |
|------------|----------------|------------------------|----------|----------|---------|
| **Small** | &lt; 10 TB | &lt; 500 GB | 3–6 workers | r8g.8xlarge | EBS gp3 (4x1TB) |
| **Medium** | 10–100 TB | 500 GB – 5 TB | 6–20 workers, scale out | r8g.8xlarge | EBS gp3 (4x1TB) |
| **Large** | 100–500 TB | 5–20 TB | 20–80 workers | r8g.12xlarge or r8g.8xlarge | EBS gp3 (4x2TB) |
| **Very Large / I/O-bound** | > 500 TB or confirmed I/O bottleneck | > 20 TB | 50–200+ workers | r8gd.16xlarge or i4i.16xlarge | NVMe (see Decision 3) |


:::tip For Small and Medium scale, **r8g.8xlarge + 4x1TB EBS is the right default.** Start with 6 workers and add more as shuffle volume grows. Don't jump to larger instances without first checking whether you're actually I/O-bound.
:::


### Instance Comparison at Large Scale


Once you've scaled out and still need more capacity per worker:


| | r8g.12xlarge | r8g.16xlarge | r8gd.16xlarge | i4i.16xlarge |
|--|-------------|-------------|--------------|-------------|
| **vCPU** | 48 | 64 | 64 | 64 |
| **RAM** | 384 GB | 512 GB | 512 GB | 512 GB |
| **Network** | 22.5 Gbps | 30 Gbps | 30 Gbps | 37.5 Gbps |
| **EBS Bandwidth** | 15 Gbps | 20 Gbps | 20 Gbps | 20 Gbps |
| **Local NVMe** | ❌ None | ❌ None | 2x1.9 TB | 4x3.75 TB |
| **Arch** | arm64 | arm64 | arm64 | x86-64 |
| **Best For** | Large scale EBS, sweet spot for concurrency | High-memory EBS | NVMe on Graviton | Maximum NVMe density |


**When `r8g.12xlarge` or `r8g.16xlarge` wins:** You've scaled out to 20+ r8g.8xlarge workers and still need more capacity per node. Network or memory is the constraint. EBS gives persistent storage, online resize, and node-failure resilience.


**When `i4i.16xlarge` wins:** You've profiled and confirmed disk I/O is the bottleneck at your scale. You need the 15TB of local NVMe (4x3.75TB) and can handle the operational requirements — replication mandatory, rotate one node at a time, no online resize.


:::note `r8g` and `r8g.16xlarge` have **no local NVMe** — EBS only. For NVMe on Graviton4, use the `r8gd` variant. Don't mix arm64 (`r8g`, `r8gd`, `im4gn`) and x86-64 (`i4i`) in the same StatefulSet.
:::


---


## Decision 3: EBS vs NVMe Storage


### Side-by-Side Comparison


| | EBS gp3 | EBS io2 Block Express | NVMe (i4i/r8gd/im4gn) |
|--|---------|---------|----------------------|
| **IOPS** | Up to 80K/volume | Up to 256K/volume | 500K–1M+ per disk |
| **Throughput** | Up to 2 GB/s/volume | Up to 4 GB/s/volume | 7–14 GB/s aggregate |
| **Max Volume Size** | 64 TiB | 64 TiB | Instance-dependent |
| **Data on node failure** | ✅ Survives (volume reattaches) | ✅ Survives | ❌ **Permanently lost** |
| **Pod restart data** | ✅ PVC reconnects to same volume | ✅ Same | ⚠️ Reconnects only if same node |
| **Online resize** | ✅ Yes | ✅ Yes | ❌ No |
| **Replication required** | Recommended | Recommended | **Mandatory** |
| **StatefulSet PVC policy** | `WhenDeleted: Retain` | `WhenDeleted: Retain` | `WhenDeleted: Delete` |
| **Operational complexity** | Low | Low | **High** |


### EBS: The Right Default for Most Teams


EBS gp3 with StatefulSets is the safest, most operationally simple choice for Celeborn on EKS:


- **Persistent volumes follow pods:** EBS volumes detach from a terminated pod and reattach to the replacement pod — even on a different node. Your shuffle data survives node failures, AMI updates, and EKS upgrades without replication.
- **Online resize:** Grow volumes without pod restarts (see [Storage Vertical Scaling](#storage-vertical-scaling)).
- **Simple rolling updates:** Workers restart in ~13s. With replication enabled, no shuffle data loss.


Use **4 gp3 volumes per worker**, configured with provisioned IOPS for medium/large scale:


```yaml
# Helm values — EBS configuration
worker:
 storage:
   - mountPath: /mnt/disk1
     storageClass: gp3
     size: 2000Gi
   - mountPath: /mnt/disk2
     storageClass: gp3
     size: 2000Gi
   - mountPath: /mnt/disk3
     storageClass: gp3
     size: 2000Gi
   - mountPath: /mnt/disk4
     storageClass: gp3
     size: 2000Gi
```


### NVMe: For Large Scale I/O-Bound Workloads


At large scale (> 5–10TB concurrent shuffle), when you've confirmed disk I/O is the bottleneck, NVMe instance stores provide dramatically higher IOPS at lower latency than EBS. But they require strict operational discipline.


**NVMe operational requirements:**


**1. Use Kubernetes Local Static Provisioner**


NVMe instance stores are not managed by EBS. You must use the [Kubernetes Local Static Provisioner](https://github.com/kubernetes-sigs/sig-storage-local-static-provisioner) (or TopoLVM) to expose NVMe disks as PersistentVolumes.


```yaml
# Local PV has node affinity — pod is pinned to the node with this volume
apiVersion: v1
kind: PersistentVolume
spec:
 capacity:
   storage: 3500Gi
 storageClassName: local-nvme
 local:
   path: /mnt/fast-disk
 nodeAffinity:
   required:
     nodeSelectorTerms:
       - matchExpressions:
           - key: kubernetes.io/hostname
             operator: In
             values: ["node-xyz"]
```


**2. Pod restart must return to the same node**


Because local PVs have node affinity, a Celeborn worker pod can only reconnect to its NVMe data if it restarts on the exact same node. If rescheduled to a different node, the pod gets stuck in `Pending`.


**Set PVC retention to Delete** (not Retain) for NVMe StatefulSets:
```yaml
# In StatefulSet spec
persistentVolumeClaimRetentionPolicy:
 whenDeleted: Delete     # PVC is cleaned up when pod is deleted
 whenScaled: Delete      # PVC is cleaned up when replicas reduced
```


This allows a new pod on a different node to create a fresh local PV. The old NVMe data is permanently lost — which is acceptable because **replication on the other worker preserves the data**.


**3. Replication is mandatory**


With NVMe, a node failure means permanent data loss. Replication ensures every shuffle partition exists on exactly 2 workers in different nodes/AZs. Enable it in all Spark jobs:


```yaml
sparkConf:
 spark.celeborn.client.push.replicate.enabled: "true"
 spark.celeborn.client.reserveSlots.rackAware.enabled: "true"  # replicas on different nodes
```


:::danger Without replication on NVMe, any node termination (Karpenter consolidation, spot interruption, hardware failure) causes immediate job failure. This is not a theoretical risk.
:::


**4. Rotate one node at a time — never two simultaneously**


With replication factor=1 (each partition on exactly 2 workers), if you restart 2 workers at the same time, a partition whose primary is on worker A and replica is on worker B has zero live copies while both are restarting. Rotate sequentially:


```bash
# Always: decommission → drain → wait for re-registration → then next worker
# Never restart two NVMe workers simultaneously
```


**5. Set terminationGracePeriodSeconds: 3600**


Karpenter's default drain timeout is 30 seconds. NVMe workers may take up to 10 minutes to drain active shuffle slots. Without an extended grace period, Kubernetes sends SIGKILL before graceful shutdown completes:


```yaml
spec:
 template:
   spec:
     terminationGracePeriodSeconds: 3600  # Must exceed graceful shutdown timeout
     containers:
     - name: celeborn-worker
       lifecycle:
         preStop:
           exec:
             command: ["/bin/sh", "-c", "/opt/celeborn/sbin/decommission-worker.sh"]
```


**Schedule NVMe maintenance in off-peak hours.** Because decommission can take minutes per worker (active shuffle slots must drain), rolling restarts of NVMe clusters take significantly longer than EBS clusters.


---


## Configuration


### Test-Validated Configuration (TPC-DS 10TB)


The following configuration was validated with a 10TB TPC-DS benchmark running for 15+ hours with rolling restarts during active shuffle. Results: zero job failures, zero executor losses, zero task failures.


**Cluster Setup:**
- 6 x r8g.8xlarge workers (32 vCPU, 256 GB RAM, 15 Gbps network)
- 4 x 1TB EBS gp3 volumes per worker (24TB total capacity)
- 3 x r8g.xlarge masters (8 GB heap each)
- 32 Spark executors with dynamic allocation


**Key Metrics:**
- Total shuffle data: 4.7 TB (47% of 10TB dataset)
- Disk utilization: 19.7% (4.7 TB / 24 TB)
- CPU usage: &lt;1% across all workers
- Memory usage: ~2% across all workers
- Rolling restart: 6 workers restarted successfully during active job


### Server-Side (Helm Values)


```yaml
celeborn:
 # Fixed ports — required when graceful shutdown is enabled
 # port=0 (dynamic) causes AssertionError during graceful shutdown restart
 celeborn.worker.rpc.port: "9091"
 celeborn.worker.fetch.port: "9092"
 celeborn.worker.push.port: "9093"
 celeborn.worker.replicate.port: "9094"


 # Graceful shutdown — persists shuffle metadata to RocksDB before restart
 # Allows workers to serve existing shuffle files after restart
 celeborn.worker.graceful.shutdown.enabled: "true"
 celeborn.worker.graceful.shutdown.timeout: "600s"
 celeborn.worker.graceful.shutdown.checkSlotsFinished.interval: "1s"
 celeborn.worker.graceful.shutdown.checkSlotsFinished.timeout: "480s"

 # RocksDB path for graceful shutdown metadata
 # Default is /tmp/recover which gets cleared on pod restart
 # Use node root filesystem (/var) instead of EBS PVC to avoid storage costs
 # Metadata survives pod restarts as long as pod returns to same node (StatefulSet behavior)
 celeborn.worker.graceful.shutdown.recoverPath: "/var/celeborn/rocksdb"


 # DNS-based worker registration — required for stable re-registration after restart
 # Without this, workers register with pod IPs (ephemeral). After restart the IP changes,
 # clients can't reconnect, master has stale mapping.
 celeborn.network.bind.preferIpAddress: "false"


 # Allow time for EBS volume reattachment (can take 60-120s on EKS)
 # Prevents false "worker lost" events during node replacements
 celeborn.master.heartbeat.worker.timeout: "180s"


 # Storage — use both MEMORY and SSD for tiered storage
 # Memory is used for hot shuffle data, SSD for overflow
 # This maximizes utilization of worker memory allocation
 celeborn.storage.availableTypes: "MEMORY,SSD"
 celeborn.worker.storage.dirs: "/mnt/disk1:disktype=SSD:capacity=900Gi,/mnt/disk2:disktype=SSD:capacity=900Gi,/mnt/disk3:disktype=SSD:capacity=900Gi,/mnt/disk4:disktype=SSD:capacity=900Gi"
 celeborn.worker.storage.storagePolicy.evictPolicy: "LRU"


 celeborn.master.slot.assign.policy: "ROUNDROBIN"
 celeborn.master.slot.assign.maxWorkers: "10000"
```


### Client-Side (Every Spark Job)


```yaml
sparkConf:
 spark.shuffle.manager: "org.apache.spark.shuffle.celeborn.SparkShuffleManager"
 spark.serializer: "org.apache.spark.serializer.KryoSerializer"
 spark.shuffle.service.enabled: "false"


 # All 3 master endpoints — required for HA failover
 spark.celeborn.master.endpoints: "celeborn-master-0.celeborn-master-svc.celeborn.svc.cluster.local:9097,celeborn-master-1.celeborn-master-svc.celeborn.svc.cluster.local:9097,celeborn-master-2.celeborn-master-svc.celeborn.svc.cluster.local:9097"


 # Replication — mandatory for NVMe, strongly recommended for EBS
 spark.celeborn.client.push.replicate.enabled: "true"


 # Retries — sized for ~13s EBS restart window; increase for NVMe (drain takes longer)
 spark.celeborn.client.fetch.maxRetriesForEachReplica: "5"
 spark.celeborn.data.io.retryWait: "15s"
 spark.celeborn.client.rpc.maxRetries: "5"


 spark.celeborn.client.spark.shuffle.writer: "sort"
 spark.celeborn.client.shuffle.batchHandleCommitPartition.enabled: "true"


 # MUST be false — if true, Spark tries to read shuffle data from executor local disks
 # (where Celeborn data doesn't exist), causing FileNotFoundException and job failure
 spark.sql.adaptive.enabled: "true"
 spark.sql.adaptive.localShuffleReader.enabled: "false"


 spark.network.timeout: "2000s"
 spark.executor.heartbeatInterval: "300s"
 spark.rpc.askTimeout: "600s"
```


:::danger Three misconfigurations that silently break Celeborn — check these first on any new deployment:
1. `spark.sql.adaptive.localShuffleReader.enabled: "true"` → Celeborn bypassed entirely, `FileNotFoundException`
2. `spark.celeborn.client.push.replicate.enabled: "false"` → any worker restart causes job failure
3. Worker ports set to `0` (dynamic) → `AssertionError` on every graceful shutdown
:::


### For NVMe at Large Scale: Increase Retries


When workers are draining active NVMe shuffle slots (can take 2-5 minutes), executors need more patience:


```yaml
sparkConf:
 spark.celeborn.client.fetch.maxRetriesForEachReplica: "10"
 spark.celeborn.data.io.retryWait: "30s"
 spark.celeborn.client.rpc.maxRetries: "10"
```


### Large Cluster Tuning (100+ Workers)


```yaml
celeborn:
 # Worker threads — baseline for 100+ concurrent applications
 # Tune based on CPU utilization metrics, not blindly
 celeborn.worker.fetch.io.threads: "64"
 celeborn.worker.push.io.threads: "64"
 celeborn.worker.flusher.threads: "32"   # For NVMe: ≥8 per disk; for HDD: ≤2 per disk
 celeborn.worker.flusher.buffer.size: "256k"
 celeborn.worker.commitFiles.threads: "128"
 celeborn.worker.commitFiles.timeout: "120s"


 # Direct memory — adjust based on worker heap size
 celeborn.worker.directMemoryRatioForReadBuffer: "0.3"
 celeborn.worker.directMemoryRatioForShuffleStorage: "0.3"
 celeborn.worker.directMemoryRatioToResume: "0.5"


 # Master scale
 celeborn.master.estimatedPartitionSize.update.interval: "10s"
 celeborn.master.estimatedPartitionSize.initialSize: "64mb"


# JVM tuning for masters — set via Helm values
master:
 jvmOptions:
   - "-XX:+UseG1GC"
   - "-XX:MaxGCPauseMillis=200"
   - "-XX:G1HeapRegionSize=32m"
   - "-Xms32g"
   - "-Xmx64g"   # Match master sizing table below
```


**Master sizing:**


| Workers | Masters | Instance | Heap |
|---------|---------|----------|------|
| 1–50 | 3 | r8g.xlarge | 8 GB |
| 51–100 | 3 | r8g.2xlarge | 16 GB |
| 101–200 | 5 | r8g.4xlarge | 32 GB |
| 200–500 | 5–7 | r8g.8xlarge | 64 GB |


---


## Day 2 Operations


### Common Operations Reference


| Operation | Method | Downtime | Notes |
|-----------|--------|----------|-------|
| Config / image update | Rolling restart (auto-triggered by ConfigMap) | Zero | ~13s per worker for EBS |
| EBS volume expansion | Online PVC resize + config update | Zero | No pod restart for resize |
| EKS / AMI upgrade | Decommission → drain per node | Zero | See procedure below |
| Instance type change | Blue-green worker pool | Zero | Old + new pools run simultaneously |
| StatefulSet immutable field | Blue-green worker pool | Zero | Required for template changes |


### Rolling Restarts


**Validated with TPC-DS 10TB benchmark:** Two comprehensive tests with 6 workers, 32 executors, active shuffle during restart. Both tests achieved zero job failures and zero executor losses.


#### Test Results Summary


| Test | Method | Worker Errors | Job Impact | Restart Time/Worker | Total Time |
|------|--------|---------------|------------|---------------------|------------|
| **Test 1** | Simple pod delete | 20-30 "file not found" per worker | Zero failures | ~70s | ~13 min |
| **Test 2** | Decommission API | 62 errors (worker-5), 0 (worker-4) | Zero failures | ~70s | ~13 min |


**Key Finding:** Decommission API did NOT eliminate errors. Worker-5 had 62 "file not found" errors despite decommission completing in 0 seconds. The API stops accepting new writes but does not migrate existing shuffle data.


#### Recommended Approach: Simple Restart + Replication


For most deployments, simple pod deletion with replication enabled is sufficient:


```bash
# Rolling restart (validated approach)
cd data-stacks/spark-on-eks/benchmarks/celeborn-benchmarks
./rolling-restart-celeborn.sh 120  # 120s pause between workers
```


**Why this works:**
- ✅ Graceful shutdown (600s timeout) flushes in-flight data
- ✅ Replication ensures data availability during restart
- ✅ Spark retry mechanism (5 retries x 15s) handles transient errors
- ✅ 120s delay ensures worker re-registration before next restart
- ✅ Zero job failures, zero executor losses (validated)


**What's normal during restart:**
- `FileNotFoundException` errors (20-30 per worker) - executors fetch from replicas
- Connection timeouts during ~70s restart window
- Revive events redirecting writes to other workers
- All errors are handled automatically by retry mechanism


**Critical requirements:**
1. **Replication MUST be enabled** - non-negotiable
2. **Graceful shutdown MUST be enabled** - prevents data corruption
3. **Fixed ports MUST be configured** - dynamic ports cause AssertionError
4. **120s delay between restarts** - allows worker re-registration


#### When to Use Decommission API


Based on our testing, decommission API provides minimal benefit for most deployments:


**Decommission API is useful for:**
- ✅ Large clusters (100+ workers) - better coordination with master
- ✅ Automated operations - explicit lifecycle hooks
- ✅ Observability - cleaner shutdown signals


**Decommission API does NOT provide:**
- ❌ Data migration to other workers
- ❌ Elimination of "file not found" errors
- ❌ Faster restarts (still need 120s delay)
- ❌ Ability to disable replication


**Decommission-based restart (optional):**
```bash
# Only use if you need explicit coordination for large clusters
cd data-stacks/spark-on-eks/benchmarks/celeborn-benchmarks
./rolling-restart-celeborn-with-decommission.py --namespace celeborn --release celeborn
```


**Decommission workflow:**
1. Send decommission request to worker API
2. Worker stops accepting new shuffle writes
3. Master redirects new writes to other workers
4. Worker drains in-flight operations (typically 0-5 seconds)
5. Delete pod, wait for re-registration
6. 120s stability wait before next worker


**Important:** Decommission drain time is typically 0-5 seconds because it only waits for in-flight writes to complete, not for data migration. Existing shuffle files remain on disk and rely on replicas for availability.


#### Rolling Restart Best Practices


**For EBS-backed workers:**
```bash
# 1. Verify replication is enabled in all running jobs
kubectl logs <driver-pod> -n spark-operator | grep "push.replicate.enabled"

# 2. Check disk usage before restart (should be &lt; 70%)
bash benchmarks/celeborn-benchmarks/check-celeborn-disk-usage.sh

# 3. Run rolling restart with 120s delay
bash benchmarks/celeborn-benchmarks/rolling-restart-celeborn.sh 120

# 4. Monitor worker re-registration
kubectl get pods -n celeborn -w
```


**For NVMe-backed workers:**
- Use decommission API (drain takes longer with active slots)
- Increase delay to 180-300s between restarts
- Never restart two workers simultaneously
- Schedule during off-peak hours


**Rolling restart WITHOUT graceful shutdown is unsafe.** GitHub issue #3539 confirms: abrupt worker termination causes Spark job hangs with `"CommitManager: Worker shutdown, commit all its partition locations"`. Always use graceful shutdown.


**Canary validation for large clusters (50+ workers):**
```bash
# Test with first 3 workers and monitor for 10 minutes
for i in 5 4 3; do
 kubectl delete pod -n celeborn "celeborn-worker-$i"
 kubectl wait pod/"celeborn-worker-$i" -n celeborn --for=condition=Ready --timeout=300s
 echo "Worker $i ready, waiting 120s..."
 sleep 120
done

# Monitor for errors
kubectl logs -n celeborn celeborn-worker-5 --tail=200 | grep -i "error\|exception"
kubectl logs -n celeborn celeborn-worker-4 --tail=200 | grep -i "error\|exception"
kubectl logs -n celeborn celeborn-worker-3 --tail=200 | grep -i "error\|exception"

# Check Spark driver for task failures (should be zero)
kubectl logs -n spark-operator <driver-pod> | grep -i "task.*failed"

# If metrics look healthy (no task failures, workers re-registered), proceed with rest
bash benchmarks/celeborn-benchmarks/rolling-restart-celeborn.sh 120
```


### Storage Vertical Scaling


EBS volumes resize **online** — no pod downtime for the resize itself. A pod rolling restart is only needed to pick up the updated config.


```bash
# Step 1: verify StorageClass allows expansion
kubectl get storageclass <name> -o jsonpath='{.allowVolumeExpansion}'  # must be true


# Step 2: resize all 4 PVCs per worker
NEW_SIZE="2000Gi"
REPLICAS=$(kubectl get statefulset celeborn-worker -n celeborn -o jsonpath='{.spec.replicas}')
for i in $(seq 0 $((REPLICAS - 1))); do
 for disk in 1 2 3 4; do
   kubectl patch pvc "data-disk${disk}-celeborn-worker-${i}" -n celeborn \
     -p "{\"spec\":{\"resources\":{\"requests\":{\"storage\":\"${NEW_SIZE}\"}}}}"
 done
done
kubectl get pvc -n celeborn -w  # wait for Bound status


# Step 3: update Helm values with new capacity, then apply
# celeborn.worker.storage.dirs capacity values must match new disk size
helm upgrade celeborn apache-celeborn/celeborn --namespace celeborn -f your-values.yaml
```


:::warning `volumeClaimTemplates` is immutable in StatefulSets. This procedure patches existing PVCs — it does not change the template. For new PVCs (when scaling out), use blue-green.
:::


### Blue-Green Worker Pool Upgrade


Required when you need to change instance type, storage type, or any StatefulSet immutable field.


**Procedure:**


```bash
# 1. Deploy new NodePool
kubectl apply -f celeborn-nodepool-v2.yaml   # Karpenter NodePool for new instance type


# 2. Deploy new worker StatefulSet pointing to new NodePool
kubectl apply -f celeborn-worker-v2.yaml


# 3. Wait for new workers to register with masters
kubectl port-forward -n celeborn svc/celeborn-master-svc 9098:9098 &
curl -s http://localhost:9098/api/v1/workers | jq '.registeredWorkers | length'
# Both old and new workers are registered — traffic flows to both


# 4. Decommission old workers (worker HTTP port is 9096)
REPLICAS=$(kubectl get statefulset celeborn-worker -n celeborn -o jsonpath='{.spec.replicas}')
for i in $(seq 0 $((REPLICAS - 1))); do
 kubectl exec -n celeborn "celeborn-worker-$i" -- \
   curl -sf -X POST -H "Content-Type: application/json" \
   -d '{"type":"DECOMMISSION"}' "http://localhost:9096/api/v1/workers/exit"
done


# 5. Poll until all old workers drained
while true; do
 DECOMM=$(curl -s http://localhost:9098/api/v1/workers | jq '.decommissioningWorkers | length')
 [ "$DECOMM" -eq 0 ] && break
 echo "$DECOMM workers still draining..."; sleep 30
done


# 6. Delete old pool
kubectl delete statefulset celeborn-worker -n celeborn
kubectl delete nodepool celeborn-workers-v1
```


**Rollback:** Keep old StatefulSet running until new pool is validated. Scale old pool back up and decommission new pool if issues arise.


### EKS and AMI Upgrades


```yaml
# EC2NodeClass — always use AL2023 with alias (AL2 is EOL)
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
 name: celeborn-node-class
spec:
 amiFamily: AL2023
 amiSelectorTerms:
   - alias: al2023@latest
 role: KarpenterNodeRole
 subnetSelectorTerms:
   - tags:
       karpenter.sh/discovery: "<cluster-name>"
 securityGroupSelectorTerms:
   - tags:
       karpenter.sh/discovery: "<cluster-name>"
```


**Per-node procedure:**
```bash
kubectl cordon <node-name>


# Decommission worker on this node before draining
WORKER=$(kubectl get pods -n celeborn --field-selector spec.nodeName=<node-name> -o name | head -1)
kubectl exec -n celeborn $WORKER -- \
 curl -sf -X POST -H "Content-Type: application/json" \
 -d '{"type":"DECOMMISSION"}' "http://localhost:9096/api/v1/workers/exit"


# Poll master until worker is drained, then drain the node
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```


:::danger Never drain a Celeborn node without decommissioning the worker first. Abrupt termination with active shuffle slots causes retry storms. With NVMe, it can cause data loss if the replica happens to be on another node being drained simultaneously.
::: node being replaced simultaneously.
:::


### Node Rotation with Karpenter


When Karpenter drains a node (consolidation, expiry, or drift), a `preStop` hook triggers graceful decommission:


```yaml
spec:
 template:
   spec:
     terminationGracePeriodSeconds: 3600  # EBS: 600s sufficient; NVMe: 3600s for drain
     containers:
     - name: celeborn-worker
       lifecycle:
         preStop:
           exec:
             command: ["/bin/sh", "-c", "/opt/celeborn/sbin/decommission-worker.sh"]
```


Add `karpenter.sh/do-not-disrupt: "true"` to worker pods if you want to prevent Karpenter from consolidating Celeborn nodes during active workloads. Combine with a disruption budget:


```yaml
# Karpenter NodePool — prevent consolidation of Celeborn nodes
spec:
 disruption:
   consolidationPolicy: WhenEmpty   # Only consolidate completely empty nodes
   expireAfter: 720h                # Rotate every 30 days for AMI freshness
```


---


## Rolling Restart Test Results


### Test Environment


**Benchmark:** TPC-DS 10TB scale factor
**Duration:** 15+ hours
**Cluster:** 6 x r8g.8xlarge workers, 3 x r8g.xlarge masters
**Storage:** 4 x 1TB EBS gp3 per worker (24TB total)
**Spark:** 32 executors with dynamic allocation


### Test 1: Simple Pod Delete (Baseline)


**Method:** `kubectl delete pod` with 120s delay between workers
**Graceful shutdown:** Enabled (600s timeout)
**Replication:** Enabled


**Results:**
- ✅ Zero job failures
- ✅ Zero executor losses
- ✅ Zero task failures
- ⚠️ 20-30 "file not found" errors per restarted worker
- ✅ All errors handled by retry mechanism
- ✅ Job continued running throughout all 6 worker restarts


**Restart timing per worker:**
- Pod deletion: instant
- Pod termination: ~60s
- Pod Ready: ~10s
- Worker re-registration: ~2s
- Total downtime: ~70s per worker
- Total test duration: ~13 minutes (6 workers x 120s delay)


**Error pattern observed:**
```
WARN FetchHandler: Could not find file 32-0-0 for shuffle-105
ERROR FetchHandler: Read file: 32-0-0 with shuffleKey error
```
- Errors occur when executors try to fetch from restarted worker
- Executors automatically retry from replica workers
- No impact on job completion


### Test 2: Decommission API


**Method:** Decommission API + pod delete with 120s delay
**Hypothesis:** Decommission should eliminate "file not found" errors


**Decommission workflow:**
1. POST to `http://worker:9096/api/v1/workers/exit` with `{"type":"DECOMMISSION"}`
2. Worker status changes to "InDecommission"
3. Master stops assigning new writes to this worker
4. Poll master API until worker removed from decommissioningWorkers
5. Delete pod


**Results:**
- Worker-5: 62 "file not found" errors (4-5 minutes after restart)
- Worker-4: 0 errors (job had completed by this point)
- Decommission drain time: 0 seconds (both workers)
- Job impact: Zero failures (same as Test 1)


**Critical finding:** Decommission API did NOT eliminate errors. The API stops accepting new writes but does not migrate existing shuffle data. Errors still occur when executors try to fetch from restarted workers.


**Why decommission drained in 0 seconds:**
- Worker-5 had 66 active slots with 261.2 GiB of data
- Worker-4 had 1 active slot with 193.5 GiB of data
- Decommission only waits for in-flight writes to complete
- Does not migrate existing shuffle files to other workers
- Relies on replication for data availability (same as simple restart)


### Test Conclusions


**What works (validated):**
1. ✅ **Replication** - handles all worker restarts gracefully
2. ✅ **Graceful shutdown** - flushes in-flight data, prevents corruption
3. ✅ **120s delay** - ensures worker re-registration before next restart
4. ✅ **Retry configuration** - 5 retries x 15s handles all transient errors


**What doesn't matter (tested):**
1. ❌ **Decommission API** - does not eliminate errors or migrate data
2. ❌ **Faster restarts** - 60s delay not tested (120s is safe and validated)


**Recommendation:**
- Use simple pod delete with replication + graceful shutdown
- Decommission API is optional (useful for coordination in large clusters)
- Focus on replication, graceful shutdown, and conservative delays


---


## Monitoring


Celeborn exposes metrics via Prometheus format at the `/metrics` endpoint on each master and worker. Configure Prometheus to scrape:
- Masters: `http://<master-pod>:9098/metrics`
- Workers: `http://<worker-pod>:9096/metrics`

For the complete list of available metrics and their descriptions, see the [official Celeborn monitoring documentation](https://celeborn.apache.org/docs/latest/monitoring).

Use the [official Grafana dashboards](https://github.com/apache/celeborn/tree/main/assets/grafana) as a starting point. For clusters with 200+ workers, use aggregated (sum/avg) panels rather than per-worker time series to avoid overwhelming Grafana.

**Key metrics to monitor:**
- Worker availability and health status
- Disk usage per worker and per mount point
- Active shuffle count and shuffle file count
- Push/fetch success and failure rates
- Master slot allocation latency
- Network throughput and connection counts


---


## Troubleshooting


### Workers not registering after restart


| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| Pod IP in registration (not DNS) | `preferIpAddress` not set | `celeborn.network.bind.preferIpAddress: "false"` |
| `port=0` in logs | Dynamic ports in use | Set all 4 fixed ports (9091–9094) |
| `AssertionError` on shutdown | Dynamic ports + graceful shutdown | Same fix as above |
| Pod stuck `Pending` (NVMe) | Local PV node affinity mismatch | Check node affinity, consider `WhenDeleted: Delete` policy |
| `Connection refused` to master | Network policy or DNS | Test from worker: `curl celeborn-master-0.celeborn-master-svc:9097` |


### Disk space exhaustion


```bash
# Check usage across all workers
REPLICAS=$(kubectl get statefulset celeborn-worker -n celeborn -o jsonpath='{.spec.replicas}')
for i in $(seq 0 $((REPLICAS - 1))); do
 echo "Worker $i:"; kubectl exec -n celeborn "celeborn-worker-$i" -- df -h | grep mnt
done


# Check for running applications before any cleanup action
kubectl port-forward -n celeborn svc/celeborn-master-svc 9098:9098 &
curl -s http://localhost:9098/api/v1/applications | \
 jq '[.applications[] | select(.status=="RUNNING")] | length'
```


Celeborn cleanup is application-driven — the master coordinates worker cleanup when applications complete. There is no manual GC trigger API.


**Remediation in order:**
1. Wait for in-flight applications to complete (master will trigger cleanup automatically)
2. [Resize EBS volumes online](#storage-vertical-scaling)
3. Enable `celeborn.worker.graceful.shutdown.enabled: true` (reduces orphaned data accumulation)


:::danger Manual shuffle data deletion — only if confirmed zero running jobs:
```bash
kubectl exec -n celeborn celeborn-worker-0 -- rm -rf /mnt/disk1/celeborn-worker/shuffle_data/*
```
Data loss is permanent. This is a last resort.
:::


### High retry rates (no restarts)


| Cause | Diagnosis | Fix |
|-------|-----------|-----|
| Network saturation | Check per-worker network metrics | Scale out workers, use higher-bandwidth instances |
| Worker overload | High CPU + thread pool queue depth | Increase fetch/push io.threads; scale out |
| Client retry too short | Retries exhausting on slow responses | Increase `maxRetriesForEachReplica`, `retryWait` |


### Master failover not working


```bash
# Verify all 3 endpoints are configured in Spark jobs
kubectl logs <driver-pod> -n <spark-namespace> | grep "master.endpoints"


# Test each master from Spark namespace
for i in {0..2}; do
 kubectl exec -n <spark-namespace> <executor-pod> -- \
   curl -v "celeborn-master-$i.celeborn-master-svc.celeborn.svc.cluster.local:9097"
done
```


---


For reference: [Apache Celeborn docs](https://celeborn.apache.org/docs/latest/) · [Cluster planning guide](https://celeborn.apache.org/docs/latest/deployment/cluster_planning/) · [Community](https://celeborn.apache.org/community/)
