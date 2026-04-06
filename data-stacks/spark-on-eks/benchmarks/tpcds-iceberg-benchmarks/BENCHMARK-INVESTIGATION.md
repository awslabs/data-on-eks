# TPC-DS 3TB Benchmark on Spark + DataFusion Comet: OOMKill Investigation

**Branch:** `feature/tpcds-iceberg-benchmarks`
**Instance:** r8gd.12xlarge (Graviton4, 48 vCPU, 384 GB RAM, NVMe)
**Benchmark:** TPC-DS v4, 3TB scale, 99 queries, 3 iterations
**Engine:** Apache Spark 3.5.8 + DataFusion Comet 0.14.0
**Test series:**

| # | Config | File |
|---|--------|------|
| 1 | Spark + Parquet (baseline) | `tpcds-benchmark-parquet.yaml` |
| 2 | Spark + Iceberg | `tpcds-benchmark-iceberg.yaml` |
| 3 | Comet + Parquet | `tpcds-benchmark-parquet-comet.yaml` |
| 4 | Comet + Iceberg | `tpcds-benchmark-iceberg-comet.yaml` |

This document covers the OOMKill investigation for **Test 3 (Comet + Parquet)** — and how its findings were applied to Test 4.

---

## The Problem

Every time we ran Test 3 with the "obvious" memory settings, Kubernetes killed executor pods mid-run. The jobs would survive for 45–90 minutes, complete dozens of queries, and then silently die. The symptom:

```
Exit code 137 — kernel SIGKILL (cgroup OOM), not a JVM GC failure
```

The tricky part: exit code 137 doesn't tell you *which* memory component caused it. And Spark's own logs say nothing — the executor just disappears.

---

## Attempt 1 — Default config (68g container limit)

**Config:**
```yaml
executor:
  memory: "20g"
  memoryOverhead: "6g"
instances: 23
sparkConf:
  spark.memory.offHeap.size: "42g"
```

**Container limit (Kubernetes):** `20 + 6 + 42 = 68g`

**What happened:** Executors OOMKilled. Prometheus captured RSS at 67.9g — within 0.1g of the limit — just before they died. The job failed.

**Initial hypothesis (wrong):** We thought `memoryOverhead` needed to be much larger. Without fully understanding the formula, an initial suggestion of `memoryOverhead: "48g"` was made. That was incorrect.

**Correction:** Kubernetes container memory limit = `executor.memory + memoryOverhead + offHeap.size`. All three are additive. The correct diagnosis required understanding what was actually consuming that 68g.

---

## Investigation — What is inside the RSS?

A Spark executor running DataFusion Comet has four distinct memory consumers, each living in a different region:

```
┌─────────────────────────────────────────────────────────┐
│               K8s Container Memory Limit                │
│                                                         │
│  ┌─────────────────┐  JVM Heap (spark.executor.memory)  │
│  │  JVM Heap 20g   │  Spark on-heap execution + storage │
│  └─────────────────┘                                    │
│  ┌─────────────────┐  spark.memory.offHeap.size         │
│  │  OffHeap Exec   │  Arrow / DataFusion native memory  │
│  │      42g        │  (Rust-allocated, via Spark pool)  │
│  └─────────────────┘                                    │
│  ┌─────────────────┐  JVM NIO Direct Buffers ← SURPRISE │
│  │  NIO Direct     │  CometShuffleManager buffers       │
│  │    ~18g peak    │  Netty network I/O                 │
│  └─────────────────┘  NOT tracked by offHeap.size       │
│  ┌─────────────────┐  JVM metadata, thread stacks, etc. │
│  │  JVM non-heap   │                                    │
│  │     ~0.3g       │                                    │
│  └─────────────────┘                                    │
└─────────────────────────────────────────────────────────┘
```

Prometheus metrics used:
- `metrics_executor_ProcessTreeJVMRSSMemory_bytes` → total RSS
- `metrics_executor_JVMHeapMemory_bytes` → JVM heap
- `metrics_executor_OffHeapExecutionMemory_bytes` → Spark-managed offheap
- `metrics_executor_DirectPoolMemory_bytes` → NIO direct buffers
- `metrics_executor_JVMOffHeapMemory_bytes` → JVM non-heap

### Key finding: NIO Direct Buffers scale with shuffle volume

At **1TB** scale: NIO direct was 5–6g per executor (well within overhead allowance).

At **3TB** scale: NIO direct peaked at **18–19g per executor**. This was the component nobody accounted for.

`CometShuffleManager` (Comet's replacement for Spark's default shuffle manager) allocates large `ByteBuffer.allocateDirect()` regions for shuffle data in-flight. These are:
- Outside the JVM heap — GC never sees them
- Outside `spark.memory.offHeap.size` — Spark's memory manager doesn't track them
- **Purely in native RAM** — counted directly against the cgroup RSS limit

3TB means ~3x the shuffle volume of 1TB → ~3x the concurrent in-flight NIO buffers → **~13g more RSS than expected**.

### Key finding: offHeap fills to its cap during heavy queries

Queries like `q17`, `q23`, `q24` involve large intermediate results with multiple joins and aggregations. During these queries, Comet's Arrow/DataFusion engine fills the entire 42g offheap pool. Prometheus confirmed: `OffHeapExecutionMemory_bytes` at **42.0g** (cap) for the first 113 minutes of a run.

This means:
```
Peak RSS per executor ≈ 19g (heap) + 42g (offheap) + 18.7g (NIO) + 0.3g (non-heap) ≈ 80g
```

Against a 68g limit → immediate OOMKill.

---

## Attempt 2 — Increased memoryOverhead to 12g (74g limit)

**Config:**
```yaml
executor:
  memory: "20g"
  memoryOverhead: "12g"
instances: 23
sparkConf:
  spark.memory.offHeap.size: "42g"
```

**Container limit:** `20 + 12 + 42 = 74g`

**What happened:** Survived longer. Prometheus captured RSS at 72.7g just before 6 executors died (IDs 3, 4, 11, 12, 14, 15). Kubernetes replaced them (executors 24–29). The job *survived* because Spark retried the tasks (316 failed tasks total, none hit the 4-failure limit per task) — but this is fragile.

**True peak RSS** was above 74g — Prometheus only captures a snapshot every scrape interval; executors died between scrapes.

**Additional finding from this run:** JVM heap was at **19g / 20g = 95%** utilization, causing frequent Major GC (11–17 events observed). The JVM was under severe GC pressure even before the OOMKill. This meant we needed to increase `executor.memory` as well.

**Why we didn't just increase `offHeap.size`:**
Raising `offHeap.size` from 42g → 50g increases the K8s limit by 8g (good) but Spark fills the larger pool → RSS grows by ~8g too → headroom stays the same. It's a treadmill. `memoryOverhead` is the only knob that adds to the K8s limit *without* adding to Spark's memory consumption.

---

## Attempt 3 — Bumped memory to 24g, memoryOverhead to 18g (84g limit)

**Config:**
```yaml
executor:
  memory: "24g"
  memoryOverhead: "18g"
instances: 23
sparkConf:
  spark.memory.offHeap.size: "42g"
```

**Container limit:** `24 + 18 + 42 = 84g`

**Expected peak RSS:** ~80g → 4g headroom. Too tight given Prometheus scrape gaps and burst variability.

This attempt was evaluated theoretically before running — the expected headroom of 4g was judged insufficient given we observed RSS spikes above the measured peak (executors die between scrapes). Abandoned before submission.

---

## Attempt 4 — memory 24g, memoryOverhead 24g (90g limit) — CURRENT

**Config:**
```yaml
executor:
  memory: "24g"            # bumped: heap was at 95% (19g/20g), GC under stress
  memoryOverhead: "24g"    # adds pure headroom; K8s limit = 24+24+42 = 90g
instances: 23
sparkConf:
  spark.memory.offHeap.size: "42g"   # fills to cap during q17/q23/q24 — do not change
```

**Container limit:** `24 + 24 + 42 = 90g`

**Reasoning:**
- Heap bump 20g→24g: relieves GC pressure (was at 95%), keeps Spark execution pool healthy
- Overhead bump 12g→24g: adds 12g of pure K8s headroom for NIO direct + Arrow native burst
- Expected peak RSS: ~84g → **6g headroom** (conservative)
- If NIO stays at 18.7g and offheap at 42g: `24 + 42 + 18.7 + 0.3 = 85g` → **5g headroom**

**Status:** RUNNING. Monitor collecting metrics every 10 minutes.

---

## Memory Config Progression Summary

| Attempt | memory | overhead | offHeap | Limit | Peak RSS | Result |
|---------|--------|----------|---------|-------|----------|--------|
| 1 | 20g | 6g | 42g | **68g** | 67.9g | OOMKill — 0.1g headroom |
| 2 | 20g | 12g | 42g | **74g** | >74g | OOMKill — 6 executors, job survived via retries |
| 3 | 24g | 18g | 42g | **84g** | ~80g est. | Skipped — 4g headroom too tight |
| 4 | 24g | 24g | 42g | **90g** | TBD | **RUNNING** |

---

## Key Lessons

### 1. K8s container limit = memory + memoryOverhead + offHeap.size
All three fields in the SparkApplication spec are additive from Kubernetes' perspective. Many people assume `memoryOverhead` covers everything beyond the heap — it doesn't. `offHeap.size` is a separate additive component.

### 2. DataFusion Comet's NIO Direct usage scales with shuffle volume
`CometShuffleManager` uses `ByteBuffer.allocateDirect()` for shuffle I/O. This memory is:
- Not tracked by Spark's memory manager
- Not covered by `spark.memory.offHeap.size`
- Proportional to concurrent shuffle data in-flight

At 3TB, this was 3x larger than at 1TB — the single biggest surprise.

### 3. Increasing `offHeap.size` doesn't buy headroom
Spark fills the offheap pool to its configured cap during heavy queries. Increasing the cap → Spark uses more → RSS grows → K8s limit grows by the same amount → net headroom = 0. The correct lever is `memoryOverhead`.

### 4. Exit code 137 = kernel OOMKill, not JVM GC
Exit code 137 means the Linux kernel sent SIGKILL via the cgroup memory controller. The JVM had no chance to log anything. You must diagnose this from Prometheus process RSS metrics, not Spark logs.

### 5. Prometheus scrape gaps understate true peak RSS
If an executor is killed between scrapes, the last captured RSS will be below the actual peak. Trust RSS trends (rate of growth) over point-in-time maximums when setting headroom.

### 6. JVM heap at 95% → GC stress
With `memory=20g`, JVM heap reached 19g/20g = 95%. This triggered frequent Major GC (11–17 events) which stops-the-world and starves tasks of CPU. Increasing heap to 24g gives the JVM breathing room without affecting the offheap or NIO budget.

---

## Monitoring Setup

Prometheus metrics collected every 10 minutes:
- Script: `/tmp/benchmark_metrics/collect.py`
- Analysis: `/tmp/benchmark_metrics/analyze.py`
- Autonomous monitor: `/tmp/benchmark_metrics/autonomous_monitor.sh`
- Storage: `/tmp/benchmark_metrics/tpcds-parquet-comet-3tb_metrics.jsonl`

Grafana dashboard (importable JSON):
- `grafana-spark-comet-memory-dashboard.json` in this directory
- UID: `spark-comet-memory-v1`
- Template variable: `application_id` auto-populated from Prometheus labels
- 12 panels: RSS vs limit, memory component breakdown (heap/offheap/NIO/Arrow), GC pressure, shuffle throughput, per-executor heatmap

---

## What Comes Next

Once Test 3 (Comet + Parquet) completes successfully:

1. Auto-submit Test 4 (Comet + Iceberg) — same 90g config already applied to `tpcds-benchmark-iceberg-comet.yaml`
2. Compare all four test results:
   - Test 1 vs Test 3: pure Comet acceleration on Parquet
   - Test 2 vs Test 4: Comet acceleration on Iceberg
   - Test 1 vs Test 2: Iceberg overhead without Comet
   - Test 3 vs Test 4: Iceberg overhead with Comet
3. Publish results and memory config guidance for Comet at 3TB+ scale
