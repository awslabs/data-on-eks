# TPC-DS Benchmark Analysis: Gluten Velox vs Comet

## Environment

### Versions
| Component | Value |
|-----------|-------|
| Spark | 3.5.8 (`spark-core_2.12-3.5.8.jar`, both apps) |
| Comet | 0.16.0 (`comet-spark-spark3.5_2.12-0.16.0.jar`) |
| Gluten + Velox | 1.6.0 (`gluten-velox-bundle-spark3.5_2.12-linux_aarch64-1.6.0.jar`) |
| Java | 17.0.17 (Eclipse Adoptium, both) |
| Scala | 2.12.18 (both) |
| Architecture | aarch64 |

### Configuration Differences
Filtered to non-infrastructure keys (pod names, app IDs, K8s image tags, host IPs excluded).

| Property | Comet | Gluten Velox |
|----------|-------|--------------|
| `spark.plugins` | `org.apache.spark.CometPlugin` | `org.apache.gluten.GlutenPlugin` |
| `spark.shuffle.manager` | `CometShuffleManager` | `ColumnarShuffleManager` |
| `spark.sql.extensions` | `CometSparkSessionExtensions` | `GlutenSessionExtensions` |
| Executor JVM extras | (none beyond default) | `--add-opens sun.misc=ALL-UNNAMED`, `--add-opens sun.nio.ch=ALL-UNNAMED`, `--add-exports sun.misc=ALL-UNNAMED`, `--add-exports sun.nio.ch=ALL-UNNAMED`, `-Dio.netty.tryReflectionSetAccessible=true` (off-heap native access) |
| GC tuning | `-XX:+UseParallelGC`, `IHOP=70` | `-XX:+UseParallelGC`, `IHOP=70` (matches) |

Comet-only properties: `spark.comet.cast.allowIncompatible=true`, `spark.comet.dppFallback.enabled=true`, `spark.comet.exec.enabled=true`, `spark.comet.exec.shuffle.enabled=true`, `spark.comet.exec.shuffle.mode=auto`, `spark.comet.explainFallback.enabled=true`.

Gluten-only properties (off-heap memory model):
- `spark.gluten.memory.offHeap.size.in.bytes=34,359,738,368` (34 GB executor off-heap)
- `spark.gluten.memory.task.offHeap.size.in.bytes=6,871,947,673` (6.87 GB per-task off-heap)
- `spark.gluten.memory.conservative.task.offHeap.size.in.bytes=3,435,973,836` (3.4 GB)
- `spark.gluten.memoryOverhead.size.in.bytes=6,442,450,944` (6.4 GB)
- `spark.gluten.numTaskSlotsPerExecutor=5`
- `spark.gluten.sql.debug=true`
- `spark.sql.adaptive.customCostEvaluatorClass=org.apache.spark.sql.execution.adaptive.GlutenCostEvaluator`

### App-Level Summary
| Metric | Comet | Gluten Velox | Delta |
|--------|-------|--------------|-------|
| Executors | 23 | 23 | 0 |
| Total Cores | 115 | 115 | 0 |
| Max Memory | 996.5 GB | 996.5 GB | 0 |
| Jobs | 6,192 | 6,139 | -53 |
| Stages | 9,170 | 9,110 | -60 |
| Tasks | 4,846,696 | 4,663,336 | -183,360 |
| Input | 14.4 TB | 15.0 TB | +614.9 GB |
| Shuffle Read | 2.5 TB | 8.7 TB | **+6.2 TB** |
| Shuffle Write | 6.9 TB | 7.0 TB | +95.8 GB |
| Spill (Disk) | 0 B | 19.8 GB | +19.8 GB |
| GC Time | 6m27.129s | 26.885s | **-6m0.244s** (14× less) |

The 6.2 TB shuffle-read delta against an essentially identical 95.8 GB shuffle-write delta is partly a metric-reporting artifact: `CometShuffleManager` does not always increment Spark's standard shuffle-read counters for native columnar shuffle (visible in q93 stage 2704 and q72 stage 9922, where Comet writes are correctly recorded but reads register as 0 B). The 14× GC reduction in Gluten reflects its off-heap Velox pipeline: when the main work is offloaded to native code, JVM allocations during query execution drop sharply, and Gluten reports 0 ms GC inside the dominant stages of every query investigated except q72 (where the gap is mostly removed Comet GC, not added Gluten GC).

---

## Query Summary

| Query | Faster Engine | Comet | Gluten Velox | Shuffle Read Δ | GC Time Δ | Root Cause Category |
|-------|---------------|-------|--------------|----------------|-----------|---------------------|
| q93-v4.0 | **Gluten Velox 3.30×** | 2m35.572s | 47.151s | +134.5 GB | -63 ms | SMJ → SHJ on 8.6B-row join |
| q50-v4.0 | **Gluten Velox 3.24×** | 1m44.815s | 31.790s | +97.1 GB | -105 ms | SMJ → SHJ on probe-side join |
| q59-v4.0 | **Gluten Velox 2.48×** | 21.253s | 8.893s | -28.3 MB | -127 ms | Scan-side input reduction (4.6×) + SMJ → SHJ |
| q39b-v4.0 | **Gluten Velox 2.40×** | 5.989s | 2.650s | -112.1 MB | 0 | Per-task compute throughput on BHJ chain |
| q23b-v4.0 | **Gluten Velox 2.13×** | 3m47.175s | 1m49.464s | +258.0 GB | -530 ms | 15 SMJs+26 sorts → 15 SHJs |
| q72-v4.0 | **Comet 5.95×** | 31.374s | 3m11.403s | +9.8 GB | -5.399 s | SHJ slower than SMJ on 1B-row pipeline |
| q27-v4.0 | **Comet 1.78×** | 5.195s | 9.256s | +25.7 MB | -65 ms | Per-task slowdown on scan+4×BHJ+expand+agg |
| q76-v4.0 | **Comet 1.69×** | 33.452s | 1m0.115s | +1.5 GB | -366 ms | Per-task scan+agg slowdown + AQE coalesce skew |
| q13-v4.0 | **Comet 1.61×** | 7.141s | 11.481s | +84.3 MB | 0 | Per-task scan+agg slowdown (+ small SMJ → SHJ tail) |
| q77-v4.0 | **Comet 1.61×** | 2.002s | 3.188s | -11.6 MB | -46 ms | Per-task scan+agg slowdown across 3 feeder stages |

---

## Queries where Gluten Velox is faster

### q93-v4.0 — Gluten Velox 3.30× faster (Comet 2m35.572s → Gluten Velox 47.151s)  →  [detailed analysis](./findings/q93-v4.0.md)
- The single shuffled-join stage drops from **2m0.986s → 12.855s** (Comet stage 2704 vs Gluten 10414, both 200 tasks); per-task p50 collapses from **58.336s to 6.523s** (~9× faster).
- All upstream/downstream stages are within ~5% between engines (store_sales scan: 29.150s vs 30.365s; store_returns scan: 6.723s vs 4.967s). No spill, no GC, no skew (p25/p75 ratio ≈1.09).
- Plan diff: `CometSortMergeJoin` + 2× `CometSort` (Comet) → `ShuffledHashJoinExecTransformer` (Gluten); the 8.64B-row store_sales side and 12.4M-row store_returns side feed a sorted-merge join in Comet vs a hash-build/probe in Gluten.
- **Root cause:** Comet must fully sort the 293 GiB / 8.64B-row shuffled store_sales partitions before merging, while Gluten builds a small ~240 MB hash table on the store_returns side and streams the larger side through it.

### q50-v4.0 — Gluten Velox 3.24× faster (Comet 1m44.815s → Gluten Velox 31.790s)  →  [detailed analysis](./findings/q50-v4.0.md)
- Probe-side join stage drops from **1m22.2s → 9.764s** (Comet 4250 vs Gluten 11959, 200 tasks each); per-task p50 **40.306s → 4.967s** (8.1× faster), with no spill and only 10–30 ms GC.
- Build-side scans are within 1 second of each other (store_sales 22.211s vs 21.591s; store_returns 21.221s vs 21.284s); the +6,791 task delta is almost entirely from added `WholeStageCodegenTransformer` / `InputIteratorTransformer` / `VeloxResizeBatches` wrappers around the same 200-partition shuffles.
- **Root cause:** same SMJ → SHJ swap as q93. Comet's plan emits `CometSortMergeJoin` with 2× `CometSort`; Gluten emits `ShuffledHashJoinExecTransformer` with no sort.

### q59-v4.0 — Gluten Velox 2.48× faster (Comet 21.253s → Gluten Velox 8.893s)  →  [detailed analysis](./findings/q59-v4.0.md)
- Two store_sales scan stages dominate: combined wall time **31.85s → 12.57s**; per-stage input drops from **18.9 GB / 8.25B records → 4.1 GB / 1.69B records** (4.6× fewer bytes, 4.9× fewer records) at p50 task 299–344 ms vs 40–56 ms.
- Same 16 stages, same 3193-task partitioning, same shuffle volume (~150 MB) on both engines — the divergence is upstream at the Parquet readers, not in the shuffle pipeline.
- Secondary contributor: Comet's single non-broadcast join is `CometSortMergeJoin` + 2× `CometSort`; Gluten swaps to `ShuffledHashJoinExecTransformer` (no sort).
- **Root cause:** Velox's Parquet scan returns 4.6× less data for the same logical output (likely tighter filter/predicate pushdown or vectorized pruning), and the SMJ → SHJ swap removes the post-shuffle sort step.

### q39b-v4.0 — Gluten Velox 2.40× faster (Comet 5.989s → Gluten Velox 2.650s)  →  [detailed analysis](./findings/q39b-v4.0.md)
- Two inventory scan stages each finish ~2.9–3.0s faster (Comet stage 1444: 4.521s → Gluten 11748: 1.596s; Comet 1445: 4.617s → Gluten 11749: 1.589s); the straggler-task delta of -2.93s/-3.03s maps 1:1 onto the -3.339s wall-clock speedup.
- No plan-shape change in the join graph (7 BHJs, 1 sort, partial+final agg are operator-1:1); zero spill, zero GC, identical input bytes (181.7 vs 183.5 MB).
- Secondary: Gluten emits **24% less shuffle write** per scan stage (45.6 MB vs 59.9 MB peak), reducing downstream shuffle work.
- **Root cause:** pure per-task compute throughput on the broadcast-join + partial-aggregate chain executed by the single non-empty inventory partition; Velox's vectorized pipeline runs the scan → 4× BHJ → partial agg → shuffle-write at ~2.85× higher throughput.

### q23b-v4.0 — Gluten Velox 2.13× faster (Comet 3m47.175s → Gluten Velox 1m49.464s)  →  [detailed analysis](./findings/q23b-v4.0.md)
- Total stage time: **6m49.561s → 3m54.443s** (-2m55.118s). Dominant 200-task reducer pair: Comet stage 798 ingests 50.9 GB / 8.09B records at p50 **17.7s/task**; Gluten 11114 ingests 118.6 GB / 16.63B records at p50 **8.6s/task** — 2.3× the bytes, 2.1× the rows, in 0.49× the run time (~4.7× per-byte throughput).
- Operator counts: **15 `CometSortMergeJoin` + 26 `CometSort` → 15 `ShuffledHashJoinExecTransformer` + 0 sort transformers** (Gluten has no sort operators in the entire plan).
- 0 B spill in both runs; GC ≤ 649 ms total — the 2× speedup is pure compute despite Gluten executing 48 stages / 32,137 tasks vs Comet's 19 / 10,545.
- **Root cause:** Comet's optimizer picks SMJ for all 15 large fact-fact and fact-dim joins, forcing 26 explicit sorts on the shuffled inputs; Gluten replaces all 15 with SHJ inside Velox vectorized pipelines, at substantially higher per-task throughput on the dominant reducers.

---

## Queries where Comet is faster

### q72-v4.0 — Comet 5.95× faster (Comet 31.374s → Gluten Velox 3m11.403s)  →  [detailed analysis](./findings/q72-v4.0.md)
- **One stage explains 98% of the gap.** Comet stage 9922 = 21.16s; Gluten stage 9881 = 3m3.4s, both 200 uniform tasks producing identical output (1.4 GB / 28,523,265 records). Per-task p50: **7.635s → 1m25.332s** (11.2× slower in Gluten Velox), no skew (p75/p25 = 1.06×, max/p50 = 1.11×).
- Per-record throughput at p50: Gluten ~59,300 records/s/task vs Comet ~666,000 records/s/task. No spill (0 B disk, 0 B memory), Gluten 0 ms GC in this stage, peak exec memory uniform 248–264 MB (well below 6.87 GB task budget).
- Plan diff: 2× `SortMergeJoin` + 1× `CometSortMergeJoin` (Comet) → 3× `ShuffledHashJoinExecTransformer` (Gluten, **zero sort operators in the plan**). Sum of all other stages: Comet ≈ 32s, Gluten ≈ 26s — Gluten is faster everywhere except this one stage.
- Secondary: Gluten reads +5.5 GB more raw Parquet (catalog_sales 657.9 MB → 3.6 GB and inventory 2.6 GB → 5.1 GB for identical record counts), adding ~3s.
- **Root cause:** the inverse of q93/q50/q23b — for this 1B-row pipeline carrying through the join chain, Comet's SortMergeJoin path is dramatically faster than Velox's ShuffledHashJoin pipeline within a fully columnar Velox stage (18 `WholeStageCodegenTransformer` blocks). Same logical work, ~11× per-task slowdown in Gluten Velox.

### q27-v4.0 — Comet 1.78× faster (Comet 5.195s → Gluten Velox 9.256s)  →  [detailed analysis](./findings/q27-v4.0.md)
- **One probe-side stage owns the gap.** Comet stage 11435 = 4.682s (631 tasks, p50 712 ms), Gluten stage 11396 = 8.695s (631 tasks, p50 1.398s). Per-task p50 +686 ms (1.96× slower in Gluten Velox) on **identical 1,632,143,161 input records**. Stage delta +4.013s ≈ entire query delta of +4.061s.
- Same 1,388 tasks, same scan/join graph; +664 MB input and +25.7 MB shuffle deltas (3% / 16%) far too small to explain a 1.96× per-task slowdown.
- Plan rewrite: single `CometHashAggregate` → `Flushable + Regular HashAggregateExecTransformer` split (+1 stage, 10 vs 9). Gluten reports 224 MB peak exec memory per task that Comet does not surface.
- **Root cause:** Velox's columnar pipeline for scan + 4× BroadcastHashJoin + Expand + partial-aggregate is ~2× slower per task than Comet's fused `CometHashAggregate` over the same data; the partial/final aggregate split, +4 extra `ProjectExecTransformer` nodes, and `VeloxResizeBatches`/`InputIteratorTransformer` glue accompany the slowdown.

### q76-v4.0 — Comet 1.69× faster (Comet 33.452s → Gluten Velox 1m0.115s)  →  [detailed analysis](./findings/q76-v4.0.md)
- Per-task slowdown across the 3 large scan + partial-agg + shuffle-write stages: p50 **496 → 758 ms (+53%)** on store_sales (3193 tasks), **521 → 725 ms (+39%)** on web_sales (1380 tasks), **413 → 541 ms (+31%)** on catalog_sales (2898 tasks). Combined +29.6s of stage time on identical input bytes.
- **Final-agg stage straggler:** Comet stage 7471 runs 600 AQE-coalesced tasks in **1.202s**; Gluten stage 7444 coalesces to only **157 tasks** and is dominated by a single straggler — task quantiles p25/p50/p75/**max = 660/747/771/13,906 ms** (max is 18× p75). Adds +13.4s.
- Total stage time **1m41.7s → 2m37.5s (+55.82s)**, reconciles with the +26.663s wall clock once stage parallelism is accounted for. Spill 0 / 0; GC 391 ms vs 25 ms — not the cost.
- Plan grew from 40 to 73 nodes (+33). `CometHashAggregate` → split partial/final with `ColumnarExchange` + `VeloxResizeBatches` + `AQEShuffleRead` boundaries.
- **Root cause:** two compounding factors — (1) per-task slowdown on the heavier columnar partial-aggregation pipeline, and (2) AQE under-coalescing of the union-shuffle for the final aggregate, producing a single 13.9s straggler.

### q13-v4.0 — Comet 1.61× faster (Comet 7.141s → Gluten Velox 11.481s)  →  [detailed analysis](./findings/q13-v4.0.md)
- Dominant stage 516 (Comet) vs 8245 (Gluten) over store_sales: 635 tasks, identical 1,641,110,765 records, 50.2 vs 50.7 MB at p50 input, p50 task **894 ms → 1.458 s (+63%)**. Per-task throughput drops from ~56 MB/s to ~35 MB/s. Stage delta +3.383s ≈ **78% of the +4.340s gap**.
- Remaining ~0.8s comes from a small SMJ → SHJ flip on the `store_sales × customer_demographics` join, which adds an extra shuffle cluster (Gluten stages 8246/8247/8248 = 1.949s vs Comet's post-shuffle finish at 1.133s).
- Plan grew from 66 to 85 nodes; +7 stages, +1447 tasks (817 → 2264) for the same query — driven by aggregate split, +5 `VeloxResizeBatches`, +9 `InputIteratorTransformer`. Total shuffle read is only 84.6 MB so data movement is not the cost.
- **Root cause:** per-task scan + filter + partial-aggregate over store_sales is ~1.6× slower in Velox even with 152–160 MB peak exec memory in use; small structural plan overhead (SMJ → SHJ tail) adds ~20% on top.

### q77-v4.0 — Comet 1.61× faster (Comet 2.002s → Gluten Velox 3.188s)  →  [detailed analysis](./findings/q77-v4.0.md)
- The 3 dominant scan-side feeder stages are each ~1.5–2.05× slower in Gluten: store_sales p50 **443 → 921 ms (+108%)** at 184M rows; catalog_sales p50 188 → 259 ms; web_sales p50 112 → 96 ms but max 603 → 1028 ms. The store_sales stage delta alone (+0.730s) explains most of the +1.186s query gap.
- Gluten's total executor run time across all 14 stages is **125.8s → 194.8s (+69s of CPU, +55%)** on the same 2.8 GB input and ~3× *less* shuffle (17.8 MB → 6.2 MB).
- Plan grew from 104 to 154 nodes (+48%): 13 → 28 `ProjectExecTransformer` nodes, single `CometHashAggregate` → `Flushable + Regular` split, +21 `InputIteratorTransformer`, +7 `VeloxResizeBatches`, +17 `WholeStageCodegenTransformer` blocks.
- **Root cause:** CPU-bound scan/agg pipeline with negligible shuffle and zero spill — the additional per-batch operator overhead in Velox's WSCG transformer chain produces a ~2× per-task slowdown that cannot be amortized over data movement.

---

## Root Cause Categories

### 1. Sort-Merge Join → Shuffled Hash Join (large fact ⋈ moderate side) — Gluten Velox wins
Queries: **q93, q50, q23b** (and partially q59 for the single non-broadcast join).
Comet's optimizer plans the largest non-broadcast joins as `CometSortMergeJoin` + `CometSort` operators on the shuffled inputs. Gluten's optimizer plans the same joins as `ShuffledHashJoinExecTransformer` with no sort step. When the build side is small enough to hash but the probe side is in the billions of rows, eliminating the explicit sort of the shuffled probe input collapses one stage from ~17–60s/task to ~5–9s/task (5–9× per-task speedup). Across q93, q50, q23b this single algorithmic difference accounts for essentially the entire Gluten Velox lead.

### 2. Velox per-task scan-side input reduction — Gluten Velox wins
Queries: **q59**.
For the same logical store_sales scan, Velox's `FileSourceScanExecTransformer` returns **4.6× fewer bytes (4.1 GB vs 18.9 GB) and 4.9× fewer records (1.69B vs 8.25B)** per stage with identical 3193-task partitioning. Same shuffle volume downstream, same plan shape. The cause is upstream in Parquet read; the data needed to confirm the precise mechanism (predicate/runtime-filter pushdown depth, late materialization) is not surfaced in the metrics available, but the bytes-out delta is unambiguous.

### 3. Velox per-task throughput on broadcast-join + partial-aggregate chain — Gluten Velox wins
Queries: **q39b**.
With operator-equivalent plans (no SMJ → SHJ flip, same 7 BHJs), Velox runs the scan → 4× BHJ → partial-agg → shuffle-write pipeline at ~2.85× higher throughput on the single straggler task. No GC, no spill, identical input bytes — pure vectorized compute.

### 4. Shuffled Hash Join → Sort-Merge Join inverse (single 1B-row pre-aggregation) — Comet wins
Queries: **q72**.
This is the mirror image of category 1. Comet plans the three non-broadcast joins as `SortMergeJoin` (2 plain Spark + 1 `CometSortMergeJoin`); Gluten plans them as `ShuffledHashJoinExecTransformer`. Within Velox's fully columnar pipeline (18 `WholeStageCodegenTransformer`, 8 `VeloxResizeBatches`), the SHJ chain processes records at ~59K records/s/task while Comet's SMJ pipeline runs at ~666K records/s/task — an 11× per-task slowdown that materializes uniformly across all 200 tasks and accounts for ~98% of the Comet lead on this query. **The same algorithmic choice that helps q93/q50/q23b hurts q72 catastrophically.**

### 5. Velox per-task scan + aggregate slowdown vs Comet — Comet wins
Queries: **q27, q13, q77, q76** (component 1 of q76).
A consistent pattern across four Comet-faster queries: identical input data per task (same record counts, ±3% bytes), but Velox's per-task wall time on `FileSourceScanExecTransformer` + `FilterExecTransformer` + `BroadcastHashJoinExecTransformer` chain + `FlushableHashAggregateExecTransformer` is **1.5–2.0× slower per task** than Comet's fused `CometNativeScan` + `CometFilter` + `CometBroadcastHashJoin` + `CometHashAggregate`. Common accompanying plan changes:
- Single `CometHashAggregate` → split `Flushable + Regular HashAggregate` across an extra shuffle (+1 stage)
- 4–15 extra `ProjectExecTransformer` nodes
- `VeloxResizeBatches`, `InputIteratorTransformer`, `WholeStageCodegenTransformer` glue (typically +20–50 plan nodes for the same query)
- `AQEShuffleRead` boundaries (q76)

These are not data-movement deficits — q13, q27, q77 each move <100 MB of total shuffle, and q76 actually writes *less* shuffle in Gluten (1.6 GB vs 2.4 GB). They are CPU costs in the columnar transformer chain.

### 6. AQE coalesce under-partitioning + skew — Comet wins (component)
Queries: **q76** (component 2).
Gluten's final-aggregation stage coalesces to 157 tasks (Comet's equivalent runs 600 AQE-coalesced tasks). The full 1.6 GB of shuffle is read with task-quantile distribution **p25/p50/p75/max = 660/747/771/13,906 ms** — a single straggler runs 18× p75 and dominates the 14.6s stage. Comet pipelines the same union into the post-shuffle aggregate without registering a shuffle read at all (writes 2.4 GB upstream → reads 0 B at the consuming stage), avoiding the coalesce path entirely. Adds +13.4s of the +26.7s q76 gap.

---

## Cross-Query Patterns

**Join-strategy choice is the single biggest plan-level driver.** In every one of the top 5 queries where Gluten Velox won, Gluten replaced a Comet `(Comet)SortMergeJoin` + sort feeders with a `ShuffledHashJoinExecTransformer`, and that replacement is the primary cause of the speedup (q93, q50, q23b, q59-secondary). In the worst-case query for Gluten Velox (q72), the *same* strategy choice is catastrophic: Comet's SMJ runs the 1B-row pipeline at 11× higher per-task throughput than Gluten's SHJ inside a fully columnar Velox stage. The two engines disagree on a fundamental optimizer choice — Comet's SMJ-first preference and Gluten's SHJ-first preference — and the win/loss outcome depends on whether the SHJ build-side fits comfortably and whether the per-record SHJ-probe rate is competitive with the SMJ merge rate for that specific plan shape. In q23b's plan diff this manifests directly as **0 sort transformers in the entire Gluten plan** vs 26 in Comet's.

**Aggregate split across an extra shuffle is structural overhead in Gluten Velox.** In every Gluten plan inspected, a single `CometHashAggregate` is replaced by a `FlushableHashAggregateExecTransformer` (partial) + `RegularHashAggregateExecTransformer` (final) split across an additional `ColumnarExchange`/`AQEShuffleRead` boundary. This consistently adds +1 stage and contributes a small fixed cost. It compounds with the per-task scan/aggregate slowdown in q27, q76, q77 to put Comet ahead.

**Comet's GC time is concentrated in the JVM-heavy stages that Velox bypasses.** Comet spent 6m27s of total GC; Gluten spent 26.9s. Per-query, GC reductions are most visible where Comet had heavy stage-level GC: q72 stage 9922 burned 5.339 s GC (= 97% of Comet's per-query GC for q72) while Gluten's equivalent stage 9881 burned 0 ms — yet Comet still won that query by 6× because the per-record cost differential dwarfs the GC savings. This pattern (Velox eliminates JVM GC but pays for it in per-record cost in some pipelines) is the central trade-off across the queries Comet wins.

**Shuffle-volume metric divergence is partly artifactual.** The app-level +6.2 TB shuffle-read delta against +95.8 GB shuffle-write delta is dominated by `CometShuffleManager`'s native shuffle path not registering reads in Spark's standard counters when AQE-reuse or local pipelining is engaged. This is visible in:
- q93 stage 2704: writes 156.7 GB upstream, registers 28 GB read in the consuming stage
- q72 stage 9922: registers 0 B / 0 records read but is processing the full upstream output
- q76 stage 7471: registers 0 B input but writes 54.3 MB downstream
On the Gluten side, `ColumnarShuffleManager` records the actual byte volumes, so per-query Gluten shuffle-read totals are accurate and Comet's are systematically under-counted. This means the +6.2 TB app-level shuffle-read delta should not be interpreted as Gluten moving 3× more shuffle data than Comet.

**Spill is concentrated outside the investigated 10 queries.** Total app-level spill of 19.8 GB occurred entirely on Gluten, but **none of the 10 investigated queries spilled** (0 B in both engines for all 10). The 19.8 GB lives in queries outside the top-5/bottom-5 set.

**Per-task off-heap memory is reported asymmetrically.** Gluten consistently reports 80–264 MB peak exec memory per task in the dominant stages (q93 80–88 MB, q72 248–264 MB, q27 224 MB, q13 152–160 MB, q39b 208 MB). Comet reports 0 B in the same metric because its native-side allocations are not surfaced through Spark's `peakExecutionMemory` counter. This makes direct memory comparison impossible from the SHS metrics alone, and means apparent "Comet uses 0 memory" readings in the data above should be read as "Comet's memory is invisible to this metric," not as a literal zero.
