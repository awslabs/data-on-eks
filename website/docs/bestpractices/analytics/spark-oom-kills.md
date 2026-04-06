---
sidebar_position: 4
sidebar_label: Preventing OOM Kills in Spark on EKS
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

# Preventing OOM Kills in Spark on EKS
# Preventing OOM Kills in Spark on Kubernetes
Every organization running large scale Spark workloads on Kubernetes has dealt with this: a job runs for hours, processes terabytes of data, completes 80% of its work, and then executors start disappearing. No JVM exception. No heap dump. No warning in Spark UI. Just `exit code 137` and hours of compute burned. The standard response is to throw more memory at it, bump `memoryOverhead` by another 10 GB, and hope for the best. That works until the next data spike.

The root cause is not insufficient memory. It is a design flaw in how **cgroupsv1** handles the Linux page cache. When a Spark executor reads shuffle data from local NVMe, the kernel caches those file pages in RAM. Under cgroupsv1, this page cache counts against the container's memory limit with no mechanism to reclaim it before the OOM killer fires. The kernel kills your executor to free memory it could have simply evicted.

**cgroupsv2** fixes this with `memory.high`, a throttling boundary that forces page cache eviction before reaching the hard kill limit. Kubernetes exposes this through the **MemoryQoS** feature gate ([KEP-2570](https://github.com/kubernetes/enhancements/issues/2570)). This guide covers the kernel internals behind the problem, the cgroupsv2 solution, and the exact EKS configuration to deploy it.

```
                          What actually happens during a Spark OOM kill
  ┌─────────────────────────────────────────────────────────────────────────────────────┐
  │                                                                                     │
  │   Spark Executor (JVM)              Linux Kernel (cgroup memory controller)         │
  │   ════════════════════              ═══════════════════════════════════════          │
  │                                                                                     │
  │   1. Writes shuffle data    ──►     Dirty pages land in page cache                  │
  │      to local NVMe                  Writeback flushes to disk                       │
  │                                                                                     │
  │   2. Reads shuffle data     ──►     read() loads file blocks into page cache        │
  │      during reduce phase            Kernel retains pages for future reads            │
  │                                                                                     │
  │   3. Spark UI shows 60%     ──►     cgroup tracks: anon (JVM) + file (page cache)   │
  │      heap utilization               usage_in_bytes climbing toward limit             │
  │      "plenty of room"                                                               │
  │                                                                                     │
  │   4. More shuffle reads     ──►     usage_in_bytes == limit_in_bytes                │
  │                                                                                     │
  │                                     ┌─────────────────────────────────────────┐      │
  │                             cgv1:   │  OOM killer fires. SIGKILL. exit 137.  │      │
  │                                     │  Page cache COULD have been evicted.   │      │
  │                                     │  Kernel didn't try. Executor is dead.  │      │
  │                                     └─────────────────────────────────────────┘      │
  │                                                                                     │
  │                                     ┌─────────────────────────────────────────┐      │
  │                             cgv2:   │  memory.high hit. Throttle allocs.     │      │
  │                                     │  Evict page cache. Usage drops.        │      │
  │                                     │  Executor survives. Job completes.     │      │
  │                                     └─────────────────────────────────────────┘      │
  │                                                                                     │
  └─────────────────────────────────────────────────────────────────────────────────────┘
```

:::info Who is this guide for?
Platform engineers running Spark on EKS and data engineers debugging unexplained executor failures. Assumes familiarity with Spark memory configuration, Kubernetes resource management, and basic Linux concepts.
:::

---

## Exit Code 137: Kernel Kill, Not JVM Kill

When Kubernetes reports exit code 137, a process was terminated by SIGKILL (signal 9). The exit code formula is `128 + signal_number = 128 + 9 = 137`. This is the Linux kernel's cgroup OOM killer, not a JVM `OutOfMemoryError`. The JVM never got a chance to throw an exception, write a heap dump, or run a shutdown hook. It was killed externally.

This distinction matters because most debugging guides focus on JVM heap analysis. But the kernel killed the container because **total RSS** exceeded the cgroup limit, and RSS includes memory the JVM knows nothing about:

```
  JVM OutOfMemoryError                        Kernel OOM Kill (exit 137)
  ════════════════════                        ══════════════════════════
  JVM detects heap exhaustion                 Kernel detects cgroup limit breach
  Exception thrown, stack trace available      SIGKILL sent, no log, no trace
  Heap dump can be captured                   Process terminated before any handler runs
  Only covers JVM heap memory                 Covers ALL memory: heap + off-heap + page cache
```

:::danger
If you are debugging OOM kills by analyzing JVM heap dumps or GC logs, you are looking in the wrong place. The kernel killed your container because total RSS exceeded the cgroup limit, and much of that RSS is page cache that neither Spark nor the JVM is aware of.
:::

---

## Linux Memory Management: The Pieces That Matter

### Anonymous Memory vs. File-Backed Memory

The Linux kernel splits process memory into two categories, and this split is the entire reason cgroupsv2 can fix OOM kills.

**Anonymous memory** (`anon`) is memory not backed by any file on disk: JVM heap (allocated via `mmap` with `MAP_ANONYMOUS`), thread stacks, `malloc` allocations, NIO direct buffers. The kernel can only reclaim anonymous pages by writing them to swap. On Kubernetes, swap is typically disabled, which makes anonymous memory **non-reclaimable**. If it is allocated, it stays resident until the process frees it.

**File-backed memory** (`file`) maps to files on disk. The dominant category here is the **page cache**: when any process calls `read()` on a file, the kernel loads those blocks into RAM and keeps them cached for future reads. Writes go through page cache too, landing as "dirty pages" that get flushed to disk asynchronously. File-backed memory is **reclaimable** because the kernel can drop clean pages instantly (the data is on disk) or flush dirty pages and then drop them.

```
Linux Process Memory
│
├── Anonymous Memory (non-reclaimable without swap)
│   ├── JVM Heap                      — managed by GC
│   ├── JVM Metaspace                 — class metadata
│   ├── Thread Stacks                 — one per thread (~1MB each)
│   ├── NIO Direct Buffers            — ByteBuffer.allocateDirect()
│   ├── Spark Off-Heap Pool           — Arrow/DataFusion native memory
│   └── Native malloc allocations     — JNI, compression codecs, etc.
│
└── File-Backed Memory (reclaimable)
    ├── Page Cache (clean)            — can be dropped instantly
    ├── Page Cache (dirty)            — must flush to disk first, then drop
    ├── Memory-mapped files           — mmap'd JARs, shared libraries
    └── tmpfs/shmem                   — backed by swap or RAM
```

:::tip
In a Spark executor, anonymous memory is bounded and predictable (JVM flags and Spark configs control it). Page cache is unbounded and invisible to Spark. It grows silently as the executor reads shuffle files, S3 buffers, and temp data. This invisible growth is what pushes containers over their cgroup limit.
:::

### How Page Cache Grows During Spark Execution

The page cache is the kernel's read/write buffer for all file I/O. Every `read()` and `write()` syscall goes through it. For Spark, this creates a silent memory consumer that grows across four phases:

**Shuffle Write:** Executors write shuffle data to local NVMe. The `write()` syscall places data into page cache as dirty pages. The kernel's writeback daemon (`kworker/flush`) flushes dirty pages to disk asynchronously, governed by `vm.dirty_background_ratio` (default 10%) and `vm.dirty_ratio` (default 20%).

**Shuffle Read:** During the reduce stage, executors read shuffle files back from NVMe. The `read()` syscall loads file blocks into page cache. The kernel retains these pages for potential future reads. Spark reads each shuffle block once and never touches it again, but the kernel does not know that. This read-ahead caching behavior works well for general purpose workloads but is toxic for Spark's sequential scan once access pattern.

**Spill to Disk:** When Spark's execution pool runs out of memory, it spills intermediate data to local disk. Reading those spill files back generates even more page cache.

**Accumulation:** Over the lifetime of a long running executor, page cache grows continuously. On a node with fast NVMe and heavy shuffle, page cache can reach **10 to 30 GB per executor**, none of which Spark or the JVM tracks.

```
Timeline of a Spark Executor's Memory Usage
────────────────────────────────────────────

     Memory
       ▲
limits ┤─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ 💀 OOM Kill!
       │                                            ╱
       │                                     Page  ╱
       │                                    Cache ╱
       │                              ┌──────────╱──── Page cache grows
       │                             ╱│         ╱      as shuffle reads
       │                    ┌───────╱─┤        ╱       accumulate
       │                   ╱│      ╱  │       ╱
       │              ┌───╱─┤     ╱   │      ╱
       │             ╱│  ╱  │    ╱    │     ╱
       │   JVM Heap ╱ │ ╱   │   ╱     │    ╱
       │   ┌───────╱──┤╱    │  ╱      │   ╱
       │   │      ╱   │     │ ╱       │  ╱
       │   │     ╱    │     │╱        │ ╱
       │   │    ╱     │     │         │╱
       │───┴───╱──────┴─────┴─────────┤
       │  JVM heap (stable)     Off-heap (stable)
       └──────────────────────────────────────────────► Time
          Task 1     Task 2    Task 3    Task 4
```

### Page Reclamation and the OOM Killer

When a cgroup runs low on memory, the kernel activates page reclamation through `kswapd` (background) or direct reclaim (synchronous, in the allocation path). The kernel scans LRU (Least Recently Used) lists, maintaining separate lists for active/inactive anonymous pages and active/inactive file pages. Clean file pages can be dropped instantly since the data exists on disk. Dirty file pages must be flushed to disk first. Anonymous pages can only be reclaimed by writing to swap, and since swap is disabled on most Kubernetes nodes, anonymous pages are effectively pinned in memory.

If reclamation cannot free enough memory, the OOM killer is invoked. The global OOM killer scores processes by RSS size and `oom_score_adj`, then sends SIGKILL to the highest scoring process. But the **cgroup OOM killer** is more direct: when a cgroup hits `memory.max` (or `memory.limit_in_bytes` in v1), it skips the scoring algorithm entirely and kills a process within that cgroup. For single process containers like Spark executors, that means the executor itself. Always.

---

## Why Spark Executors Get OOM Killed

### The Complete Executor Memory Map

A Spark executor's container RSS has several distinct regions. Some are tracked by Spark, some are not:

```
Container RSS (what the cgroup tracks)
│
├── JVM Heap              spark.executor.memory (e.g., 20g)
│   │                     Managed by GC — predictable, bounded
│   └── GC Working Space  Needs ~10-15% headroom for GC to operate efficiently
│
├── JVM Non-Heap          (~300-500 MB typically)
│   ├── Metaspace         Class metadata, scales with # of loaded classes
│   ├── Code Cache        JIT-compiled code (~240 MB default ReservedCodeCacheSize)
│   ├── Thread Stacks     1 MB × number_of_threads (can be 200+ threads)
│   └── Internal VM       GC data structures, symbol tables, etc.
│
├── Spark Off-Heap Pool   spark.memory.offHeap.size (e.g., 42g)
│   │                     Arrow columnar buffers, DataFusion native memory
│   └── Explicitly capped by Spark's MemoryManager
│
├── NIO Direct Buffers    ⚠️ NOT tracked by Spark's memory manager
│   ├── Netty I/O         Shuffle data transfer between executors
│   ├── Shuffle Client    CometShuffleManager, SortShuffleManager
│   └── Compression       LZ4/Zstd codec native buffers
│       Scales with concurrent shuffle connections (3x data ≈ 3x buffers)
│
└── Linux Page Cache      ⚠️ NOT tracked by Spark OR the JVM
    ├── Shuffle Files      Written to NVMe, cached on read-back
    ├── Spill Files        Execution/storage pool spills to disk
    ├── S3A Disk Buffers   S3 reads cached on local filesystem
    └── JAR/Class Files    Loaded libraries and dependencies
        Grows unbounded — kernel counts this against cgroup limit
```

:::danger
NIO Direct Buffers and Linux Page Cache are invisible to Spark's memory accounting. Spark UI will show comfortable headroom while the container is actually approaching its cgroup limit. This is why OOM kills appear random when looking at Spark metrics alone.
:::

### Why cgroupsv1 Makes This Fatal

cgroupsv1 (the default on Amazon Linux 2) has one memory knob: `memory.limit_in_bytes`. The usage counter tracks the sum of all memory charged to the cgroup:

```
memory.usage_in_bytes = anonymous_memory (RSS) + file_cache (page cache) + kernel memory
```

When usage hits the limit, the cgroup OOM killer fires immediately. No throttling, no preferential page cache reclaim, no second chance.

```
cgroupsv1 Behavior
═══════════════════

Container starts → Allocates JVM heap → Runs tasks → Reads shuffle files
                                                          │
                                                          ▼
                                                    Page cache grows
                                                          │
                                                          ▼
                                         memory.usage_in_bytes approaches
                                         memory.limit_in_bytes
                                                          │
                                                          ▼
                                              ┌───────────────────────┐
                                              │   OOM Killer fires    │
                                              │   SIGKILL → exit 137  │
                                              │   No reclamation      │
                                              │   No warning          │
                                              │   No page cache evict │
                                              └───────────────────────┘
```

cgroupsv1 does have `memory.soft_limit_in_bytes`, but it is advisory only. It influences which cgroup the kernel prefers to reclaim from under global memory pressure, but does not insert a reclamation step before the hard limit within a single cgroup.

:::note
The kernel *could* reclaim the page cache. Those are clean, reclaimable pages backed by files on NVMe. But cgroupsv1's memory controller does not attempt aggressive cgroup-local reclamation before invoking the OOM killer. It treats reclaimable page cache and non-reclaimable anonymous memory identically when evaluating the hard limit. Your executor dies because the kernel cached its own I/O.
:::

---

## The Solution: cgroupsv2 and Memory QoS

cgroupsv2 (Linux kernel 5.2+, enabled by default on Amazon Linux 2023) redesigns the memory controller with graduated memory pressure instead of cgroupsv1's binary kill/no-kill model.

### cgroupsv2 Memory Interfaces

| Interface | Kubernetes Mapping | Purpose |
|---|---|---|
| `memory.min` | `requests.memory` | Hard guarantee. Kernel will not reclaim below this, even under extreme system pressure. |
| `memory.low` | *(not yet mapped)* | Soft protection. Kernel prefers to reclaim from other cgroups first. |
| `memory.high` | Calculated via MemoryQoS | **Throttle + reclaim boundary.** Kernel slows allocations and aggressively reclaims page cache when exceeded. This is the key innovation. |
| `memory.max` | `limits.memory` | Hard limit. OOM kill when exceeded. Same as v1's `memory.limit_in_bytes`. |

### How `memory.high` Saves Spark Executors

When a cgroup's usage crosses `memory.high`, the kernel responds with graduated pressure instead of a kill:

**Throttle new allocations.** The kernel inserts delays into the allocation path for all processes in the cgroup. Any `malloc()`, `mmap()`, or page fault that needs new memory is slowed down. The JVM's allocator and NIO buffer pool experience back-pressure, naturally reducing allocation rate.

**Aggressive page cache reclamation.** The kernel activates direct reclaim targeting the cgroup's file-backed pages. Clean pages are dropped immediately. Dirty pages are flushed to disk and then dropped. For Spark, shuffle file page cache gets evicted, which is exactly the memory that was causing the problem.

**Re-evaluate.** If reclamation brings usage below `memory.high`, throttling stops and the cgroup returns to normal. The executor experienced a brief pause but keeps running.

**OOM kill only as last resort.** If the working set (anonymous memory that cannot be reclaimed) genuinely exceeds `memory.max`, only then does the OOM killer fire. At that point, the container is actually out of memory and no amount of page cache eviction will help.

:::tip
With `memory.high` in place, a Spark executor that has accumulated 15 GB of shuffle file page cache will pause briefly (milliseconds to seconds) while the kernel evicts that cache, then resume normal operation. Without it, that same executor would be killed instantly. The job continues. No re-computation. No wasted hours of compute.
:::

### Kubernetes MemoryQoS (KEP-2570)

Kubernetes exposes cgroupsv2's `memory.high` through the **MemoryQoS** feature gate ([KEP-2570](https://github.com/kubernetes/enhancements/issues/2570)). Introduced as alpha in Kubernetes 1.22, refined through multiple iterations, and currently Alpha v3 in v1.36. The kubelet includes a kernel version check requiring **Linux 5.9+** to avoid a livelock bug in earlier kernels where tasks could get indefinitely throttled at the `memory.high` boundary.

When enabled, the kubelet sets `memory.high` for every Burstable and BestEffort container:

```
memory.high = floor[ (requests.memory + memoryThrottlingFactor × (limits.memory - requests.memory)) / pageSize ] × pageSize
```

With the default `memoryThrottlingFactor: 0.9`:

<Tabs>
  <TabItem value="conservative" label="Conservative (factor: 0.7)" default>

```yaml
# Executor: request=80Gi, limit=96Gi, factor=0.7
memory.high = 80 + 0.7 × (96 - 80) = 91.2 Gi   # ← page cache eviction starts
memory.max  = 96 Gi                              # ← hard kill only here
# Gap: 4.8 Gi buffer between throttling and kill
```

**Best for:** Heavy shuffle workloads with large page cache accumulation. Provides the widest safety margin. Expect occasional throttling during peak shuffle reads.

  </TabItem>
  <TabItem value="balanced" label="Balanced (factor: 0.8)">

```yaml
# Executor: request=80Gi, limit=96Gi, factor=0.8
memory.high = 80 + 0.8 × (96 - 80) = 92.8 Gi   # ← page cache eviction starts
memory.max  = 96 Gi                              # ← hard kill only here
# Gap: 3.2 Gi buffer between throttling and kill
```

**Best for:** Mixed workloads with moderate shuffle. Good balance between protection and performance.

  </TabItem>
  <TabItem value="permissive" label="Permissive (factor: 0.9, default)">

```yaml
# Executor: request=80Gi, limit=96Gi, factor=0.9
memory.high = 80 + 0.9 × (96 - 80) = 94.4 Gi   # ← page cache eviction starts
memory.max  = 96 Gi                              # ← hard kill only here
# Gap: 1.6 Gi buffer between throttling and kill
```

**Best for:** Workloads where page cache is not a major concern. Minimal throttling but also less safety margin.

  </TabItem>
</Tabs>

:::warning Burstable QoS is required
MemoryQoS only activates when `requests.memory < limits.memory` (Burstable QoS class). With Guaranteed QoS (request == limit), the formula yields `memory.high == memory.max`, which provides zero benefit. You must intentionally create a gap between requests and limits.

For Guaranteed pods, the KEP states: *"Memory QoS feature is disabled on those pods by not setting memory.high."*
:::

### What About `memory.min`?

KEP-2570 also maps `requests.memory` to `memory.min`, providing a hard memory guarantee. The kernel will not reclaim memory from a cgroup below its `memory.min` value, even under extreme system-wide pressure. This protects your executor's working set (JVM heap, off-heap pool) from being evicted by noisy neighbors on the same node.

---

## Prerequisites

Before implementing MemoryQoS, ensure your infrastructure meets these requirements:

| Requirement | Details |
|---|---|
| **Node OS** | Amazon Linux 2023 (cgroupsv2 enabled by default). AL2 uses cgroupsv1 and **cannot** use this feature. |
| **Kernel Version** | Linux 5.9+ required. AL2023 ships with 6.1+ kernels. Kernels before 5.9 have a livelock bug at `memory.high` boundaries. |
| **Kubernetes** | 1.22+ (MemoryQoS feature gate available). **EKS 1.29+** recommended for stable cgroupsv2 support. |
| **Karpenter** | v0.32+ recommended for AL2023 `EC2NodeClass` support with `NodeConfig` userData. |

**Verify cgroupsv2 is active on your nodes:**

```bash
# Check cgroup version
kubectl exec -n <namespace> <any-pod> -- stat -fc %T /sys/fs/cgroup/
# Expected output: cgroup2fs

# Alternative: check mount type
kubectl exec -n <namespace> <any-pod> -- cat /proc/mounts | grep cgroup
# Should show: cgroup2 /sys/fs/cgroup cgroup2 rw,nosuid,nodev,noexec,relatime 0 0

# Verify kernel version (must be ≥ 5.9)
kubectl exec -n <namespace> <any-pod> -- uname -r
# Expected: 6.1.x or higher on AL2023
```

:::note Checking from the node directly
If you have SSH or SSM access to a node, you can also verify:
```bash
# Check if memory.high interface exists in a cgroup
ls /sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/*/memory.high
# If this file exists, cgroupsv2 memory controller is active
```
:::

---

## Configuration

### Step 1: Enable MemoryQoS in the Karpenter EC2NodeClass

Add a `NodeConfig` block to the `EC2NodeClass` userData. The multi-part MIME format is required for AL2023 to process both the NodeConfig and any shell script initialization:

```yaml
# infra/terraform/manifests/karpenter/ec2nodeclass.yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: ephemeral-nvme-local-provisioner
spec:
  amiFamily: AL2023
  amiSelectorTerms:
    - alias: al2023@latest
  # ... other spec fields ...
  userData: |
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="//"

    --//
    Content-Type: application/node.eks.aws

    apiVersion: node.eks.aws/v1alpha1
    kind: NodeConfig
    spec:
      kubelet:
        config:
          featureGates:
            MemoryQoS: true
          # memory.high = request + factor × (limit - request)
          #
          # Lower values (0.6-0.7) = more aggressive throttling, wider safety margin
          # Higher values (0.8-0.9) = less throttling, narrower safety margin
          #
          # Kubernetes default is 0.9. For heavy shuffle workloads, 0.7 is recommended.
          memoryThrottlingFactor: 0.7

    --//
    Content-Type: text/x-shellscript; charset="us-ascii"

    #!/bin/bash
    # Your existing node initialization script (NVMe setup, etc.)
    --//--
```

:::tip
This applies to all pods on nodes provisioned from this `EC2NodeClass`. Pods that never approach their limit are unaffected. `memory.high` only activates when usage actually crosses the threshold. Zero overhead for well-sized containers.
:::

### Step 2: Configure Node Eviction Threshold

Without an eviction threshold, Karpenter can schedule pods until a node is nearly exhausted. If multiple Spark executors burst simultaneously (common during the shuffle phase of a large job), the **node itself** can OOM:

```yaml
# infra/terraform/manifests/karpenter/nodepool-local-provisioner.yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: ephemeral-nvme-local-provisioner
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: ephemeral-nvme-local-provisioner
      kubelet:
        evictionHard:
          memory.available: "10Gi"  # Kubelet evicts pods when < 10Gi free on node
      requirements:
        # ... your instance family requirements ...
```

:::warning
`evictionHard` protects against **node-level** OOM (total demand from all pods exceeds node capacity). MemoryQoS protects against **cgroup-level** OOM (individual container page cache buildup). You need both.
:::

### Step 3: Set Burstable QoS on Executor Pods

MemoryQoS requires `requests < limits` to create the gap where `memory.high` sits. Configure the executor pod template with explicit resource overrides:

```yaml
# spark-application.yaml (SparkApplication CRD or spark-submit pod template)
spec:
  executor:
    memory: "24g"          # JVM heap (spark.executor.memory)
    memoryOverhead: "30g"  # Covers JVM non-heap + NIO direct buffers
    instances: 23
    template:
      spec:
        containers:
          - name: spark-kubernetes-executor
            resources:
              requests:
                memory: "80Gi"   # ← lower than limit → Burstable QoS
              limits:
                memory: "96Gi"   # ← hard limit = memory + memoryOverhead + offHeap
  sparkConf:
    "spark.memory.offHeap.enabled": "true"
    "spark.memory.offHeap.size": "42g"
```

**Resulting cgroup configuration:**

```
memory.min  = 80 Gi          ← hard guarantee (kernel won't reclaim below this)
memory.high = 91.2 Gi        ← throttle + reclaim page cache (with factor 0.7)
memory.max  = 96 Gi          ← hard kill (only genuine OOM)

┌────────────────────────────────────────────────────────────────────────────┐
│ 0 Gi          80 Gi          91.2 Gi              96 Gi                   │
│ ├──────────────┼───────────────┼────────────────────┤                     │
│ │  Protected   │   Burstable   │  Throttle + Reclaim│                     │
│ │  (memory.min)│   headroom    │  zone (memory.high │                     │
│ │              │               │  to memory.max)    │                     │
│ └──────────────┴───────────────┴────────────────────┘                     │
│ Kernel will    Normal          Page cache evicted    OOM kill only if     │
│ not reclaim    operation       Allocations throttled non-reclaimable      │
│ below here                                          memory exceeds this  │
└────────────────────────────────────────────────────────────────────────────┘
```

**Scheduling safety:** Size requests so that `executors_per_node × requests.memory < node_allocatable_memory`. For `r8gd.12xlarge` (384 GiB): `4 executors × 80 Gi = 320 Gi`, leaving 64 GiB for system daemons, kubelet, and the eviction threshold.

---

## Sizing the Memory Budget

The Kubernetes container limit for a Spark executor is the sum of three independent components:

```
K8s limit = spark.executor.memory + spark.executor.memoryOverhead + spark.memory.offHeap.size
```

:::danger
`memoryOverhead` does not cover `offHeap.size`. These are additive. Setting `executor.memory=24g`, `memoryOverhead=30g`, and `offHeap.size=42g` produces a Kubernetes limit of **96 Gi**, not 54 Gi.
:::

### Measuring Actual Memory Usage

Before finalizing memory settings, measure the true RSS breakdown during a representative run using Prometheus:

```promql
# Peak RSS across all executors for a given application
max(metrics_executor_ProcessTreeJVMRSSMemory_bytes{application_id="<app_id>"})

# JVM heap usage
max(metrics_executor_JVMHeapMemory_bytes{application_id="<app_id>"})

# Spark off-heap execution pool
max(metrics_executor_OffHeapExecutionMemory_bytes{application_id="<app_id>"})

# NIO direct buffers (Netty + Shuffle)
max(metrics_executor_DirectPoolMemory_bytes{application_id="<app_id>"})
```

You can also inspect the cgroup memory breakdown directly from within a running executor pod:

```bash
# Connect to a running executor
kubectl exec -it <executor-pod> -n <namespace> -- bash

# Current total memory usage
cat /sys/fs/cgroup/memory.current

# Detailed breakdown
cat /sys/fs/cgroup/memory.stat
# Key fields:
#   anon      — anonymous memory (JVM heap + native allocations)
#   file      — page cache charged to this cgroup
#   sock      — network buffer memory
#   shmem     — shared memory / tmpfs

# Check memory.high and memory.max values set by kubelet
cat /sys/fs/cgroup/memory.high
cat /sys/fs/cgroup/memory.max

# Memory pressure events (how often reclamation was triggered)
cat /sys/fs/cgroup/memory.pressure
# Shows: some avg10=X.XX avg60=X.XX avg300=X.XX total=XXXXXX
# Non-zero values confirm memory.high is activating
```

### Right-Sizing Formula

Once you have observed peak memory usage across a representative set of runs:

```
spark.executor.memory    = ceil(peak_heap × 1.10)        # 10% headroom for GC
spark.executor.memoryOverhead = ceil(peak_NIO × 1.15)    # Covers NIO direct + JVM non-heap
spark.memory.offHeap.size = ceil(peak_offheap × 1.15)    # Covers Arrow/DataFusion native

K8s_limit                = executor.memory + memoryOverhead + offHeap.size
requests.memory          = floor(K8s_limit × 0.85)       # 15% gap for memory.high zone
```

<Tabs>
  <TabItem value="light" label="Light Shuffle" default>

```yaml
# Jobs with < 100 GB shuffle data per executor
# Page cache accumulation: ~5-10 GB
executor:
  memory: "16g"
  memoryOverhead: "8g"
  resources:
    requests: { memory: "56Gi" }    # 85% of limit
    limits: { memory: "66Gi" }
sparkConf:
  spark.memory.offHeap.size: "42g"
# memory.high gap: ~7 Gi (sufficient for light cache)
```

  </TabItem>
  <TabItem value="heavy" label="Heavy Shuffle">

```yaml
# Jobs with 500 GB+ shuffle data per executor
# Page cache accumulation: ~15-30 GB
executor:
  memory: "24g"
  memoryOverhead: "30g"
  resources:
    requests: { memory: "80Gi" }    # 83% of limit
    limits: { memory: "96Gi" }
sparkConf:
  spark.memory.offHeap.size: "42g"
# memory.high gap: ~4.8 Gi with factor 0.7
# Consider factor 0.6 for extreme cases
```

  </TabItem>
  <TabItem value="extreme" label="Extreme Shuffle (1TB+)">

```yaml
# Jobs with 1 TB+ shuffle data per executor
# Page cache accumulation: 30+ GB
# Consider using external shuffle service (Celeborn) first
executor:
  memory: "32g"
  memoryOverhead: "40g"
  resources:
    requests: { memory: "96Gi" }    # 80% of limit
    limits: { memory: "120Gi" }
sparkConf:
  spark.memory.offHeap.size: "48g"
# memory.high gap: ~7.2 Gi with factor 0.7
# Use r8gd.16xlarge or larger instances
```

  </TabItem>
</Tabs>

---

## Monitoring and Observability

### Key Metrics

**Kubelet metrics (Prometheus):**

```promql
# Number of times memory.high throttling was triggered per executor
sum by (pod) (kubelet_memory_qos_throttle_events_total)

# Current memory.high value set for each container
kubelet_memory_qos_memory_high_bytes{container="spark-kubernetes-executor"}
```

**cgroup pressure metrics (PSI):**

```bash
# Read memory pressure from within a pod
cat /sys/fs/cgroup/memory.pressure
# Output: some avg10=2.50 avg60=1.20 avg300=0.80 total=45230000
#         full avg10=0.00 avg60=0.00 avg300=0.00 total=0
#
# "some" = at least one task stalled on memory
# "full" = ALL tasks stalled (serious pressure)
# avg10/60/300 = percentage over last 10s/60s/300s
```

**Interpreting PSI values:**

| Metric Pattern | Meaning | Action |
|---|---|---|
| `some avg10 < 5`, `full = 0` | Healthy. Light reclamation happening, no impact on throughput. | None needed. |
| `some avg10 = 5-20`, `full = 0` | Moderate pressure. Page cache being reclaimed actively. | Monitor. Consider increasing limit or lowering factor. |
| `some avg10 > 20`, `full > 0` | Heavy pressure. Working set may be too large. | Increase `requests.memory` and `limits.memory`. |
| `full avg10 > 10` | Severe. All threads stalled. Near-OOM conditions. | Increase memory significantly or reduce executor concurrency. |

### Alerting

Set up alerts for containers that are repeatedly hitting `memory.high`:

```yaml
# Prometheus alert rule
- alert: SparkExecutorMemoryThrottling
  expr: rate(kubelet_memory_qos_throttle_events_total{container="spark-kubernetes-executor"}[5m]) > 0.1
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Spark executor {{ $labels.pod }} is being memory-throttled"
    description: >
      Executor has been hitting memory.high for over 10 minutes.
      Page cache is being reclaimed (OOM prevented),
      but sustained throttling may impact job performance.
      Consider increasing limits.memory or lowering memoryThrottlingFactor.
```

---

## What MemoryQoS Does Not Fix

MemoryQoS handles reclaimable memory (page cache) temporarily pushing RSS above the working set. It is not a substitute for correctly sizing memory.

| Cause of High RSS | MemoryQoS Helps? | Correct Fix |
|---|---|---|
| Page cache from NVMe shuffle read-back | ✅ Yes. Kernel evicts cache before killing. | MemoryQoS is the fix |
| S3A / HDFS disk buffer cache | ✅ Yes. Same mechanism. | MemoryQoS is the fix |
| Memory-mapped JAR/class files | ✅ Yes. File-backed, reclaimable. | MemoryQoS is the fix |
| JVM heap full (GC not keeping up) | ❌ No. Heap is anonymous, non-reclaimable. | Increase `spark.executor.memory` or tune GC |
| NIO direct buffers at capacity | ⚠️ Partial. Throttling slows allocation but cannot reclaim live buffers. | Increase `memoryOverhead`; tune `spark.shuffle.io.numConnectionsPerPeer` |
| Spark off-heap pool at cap | ❌ No. Arrow allocations are non-reclaimable. | Increase `spark.memory.offHeap.size` |
| JVM Metaspace growth | ❌ No. Anonymous memory. | Set `-XX:MaxMetaspaceSize` in `spark.executor.extraJavaOptions` |
| Thread stack accumulation | ❌ No. Anonymous memory. | Reduce thread count or set `-Xss512k` |

:::tip
If the memory is backed by a file on disk, MemoryQoS can reclaim it. If it is anonymous (allocated by the application), it cannot be reclaimed and must be sized correctly.
:::

---

## Troubleshooting

### Verifying MemoryQoS is Active

After deploying the configuration, verify that `memory.high` is being set correctly:

```bash
# 1. Find a running Burstable executor pod
kubectl get pods -n <namespace> -l spark-role=executor -o wide

# 2. Check the cgroup settings
kubectl exec -it <executor-pod> -n <namespace> -- cat /sys/fs/cgroup/memory.high
# Should show a value LESS than memory.max (e.g., 97844723712 for ~91.2 Gi)

kubectl exec -it <executor-pod> -n <namespace> -- cat /sys/fs/cgroup/memory.max
# Should show the container limit (e.g., 103079215104 for 96 Gi)

# 3. If memory.high equals memory.max, MemoryQoS is NOT active. Check:
#    - Is the feature gate enabled? (check kubelet config on node)
#    - Is request < limit? (Guaranteed QoS gets no memory.high)
#    - Is the node running AL2023 with cgroupsv2?
```

### Common Issues

<Tabs>
  <TabItem value="not-active" label="MemoryQoS Not Activating" default>

**Symptom:** `memory.high` equals `memory.max` inside the container.

**Diagnosis:**
```bash
# Check kubelet feature gates on the node (via SSM or node shell)
ps aux | grep kubelet | grep -o 'featureGates=[^ ]*'

# Check if cgroupsv2 is active
stat -fc %T /sys/fs/cgroup/
# Must output: cgroup2fs

# Check kernel version
uname -r
# Must be ≥ 5.9
```

**Common causes:**
1. Feature gate not propagated. Verify `EC2NodeClass` userData is applied. Nodes provisioned before the change need to be recycled.
2. Pods are Guaranteed QoS. `requests.memory == limits.memory`. Intentionally set `requests < limits`.
3. Node is still AL2. cgroupsv1 does not support `memory.high`. Migrate to AL2023.

  </TabItem>
  <TabItem value="excessive-throttle" label="Excessive Throttling">

**Symptom:** Jobs complete but are significantly slower. PSI `some avg10 > 20`.

**Diagnosis:**
```bash
# Check how much page cache vs. anonymous memory
cat /sys/fs/cgroup/memory.stat | grep -E '^(anon|file) '
# If 'anon' is close to memory.high, throttling won't help. You need more memory
# If 'file' is large, throttling is working but may be too aggressive
```

**Fixes:**
1. Increase `memoryThrottlingFactor` (e.g., 0.8 → 0.9) to raise `memory.high`.
2. Increase `limits.memory` to give more headroom.
3. If `anon` is the dominant consumer, increase `requests.memory` *and* `limits.memory`.

  </TabItem>
  <TabItem value="still-oom" label="Still Getting OOM Killed">

**Symptom:** Exit code 137 persists even with MemoryQoS enabled.

**Diagnosis:**
```bash
# Check dmesg on the node for OOM details
dmesg | grep -A 20 "oom-kill"
# Look for: oom_memcg (cgroup OOM) vs. global OOM

# Check if the anonymous working set exceeds the limit
kubectl exec <pod> -- cat /sys/fs/cgroup/memory.stat | grep anon
# If anon > memory.max, the working set is genuinely too large
```

**Fixes:**
1. The working set genuinely exceeds the limit. Increase `limits.memory` and `requests.memory`.
2. NIO direct buffer leak. Add `-XX:MaxDirectMemorySize` to `spark.executor.extraJavaOptions`.
3. Native memory leak in a UDF or codec. Profile with `jcmd <pid> VM.native_memory summary`.

  </TabItem>
</Tabs>

---

## Summary

```
Problem:   cgroupsv1 treats page cache and working memory identically.
           When shuffle file page cache pushes container RSS to the cgroup limit,
           the OOM killer fires immediately, killing executors that have plenty
           of reclaimable memory the kernel could have evicted instead.

Solution:  cgroupsv2 memory.high + Kubernetes MemoryQoS (KEP-2570) inserts a
           graduated pressure boundary. The kernel reclaims page cache at
           memory.high and only OOM-kills at memory.max when non-reclaimable
           memory genuinely exceeds the limit.

Required:  ✓ Amazon Linux 2023 nodes (cgroupsv2 enabled by default)
           ✓ Linux kernel ≥ 5.9 (AL2023 ships with 6.1+)
           ✓ MemoryQoS: true in kubelet feature gates (via EC2NodeClass userData)
           ✓ memoryThrottlingFactor: 0.7 (tunable per workload profile)
           ✓ Burstable QoS on executor pods (requests.memory < limits.memory)
           ✓ Node eviction threshold in NodePool to prevent node-level OOM

Formula:   memory.high = request + throttlingFactor × (limit - request)
           memory.max  = limit
           memory.min  = request
```

---

## Further Reading

- [KEP-2570: Memory QoS](https://github.com/kubernetes/enhancements/issues/2570). Full design details and implementation history.
- [Control Group v2: Linux Kernel Documentation](https://docs.kernel.org/admin-guide/cgroup-v2.html). Official kernel docs for the cgroupsv2 memory controller.
- [Quality-of-Service for Memory Resources](https://kubernetes.io/blog/2023/05/05/qos-memory-resources/). Kubernetes blog introduction to MemoryQoS.
- [cgroup v2 and Page Cache](https://biriukov.dev/docs/page-cache/6-cgroup-v2-and-page-cache/). Deep dive into page cache behavior under cgroupsv2.
- [Diagnosing Linux cgroups v2 Memory Throttling](https://www.netdata.cloud/academy/diagnosing-linux-cgroups/). Practical monitoring guide.
- [CPU and Memory Management on Kubernetes with cgroupsv2](https://linuxera.org/cpu-memory-management-kubernetes-cgroupsv2/). Hands-on walkthrough.
