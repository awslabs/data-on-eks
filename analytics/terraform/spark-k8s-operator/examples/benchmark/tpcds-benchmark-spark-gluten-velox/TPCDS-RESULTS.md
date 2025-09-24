 # TPC-DS 1 TB Benchmark – Native Spark vs. Spark + Gluten + Velox

## Quick Summary

- Gluten+Velox finished the 1 TB run in **≈20.9 min** versus **≈33.5 min** for native Spark (1.60× faster overall).
- Per-query medians: Gluten beat native on **90/104** queries; average speedup **1.74×**, median **1.61×**.
- Largest wins: q93 (5.46× faster), q50 (3.70×), q62 (3.64×); biggest regressions: q22 (0.35×), q72 (0.44×), q67 (0.46×).
- Results stored in S3 under `TPCDS-TEST-1TB-RESULT-GLUTEN` and `...-RESULT-NATIVE`; comparison CSV committed to `examples/tpcds-benchmark-spark-gluten-velox/results/`.
- Spark History Server must point at `s3://spark-benchmarks-tpcds-data-1tb-us-west-2/spark-event-logs/` to replay both applications (`spark-3b17e3488d79404995ab0bb3cf9f6190` Gluten, `spark-b8c4002052844b628e76b04647fc2eee` native).

---

This document captures the complete outcome of the 1 TB TPC-DS benchmark runs that were executed on 24 September 2025. Both jobs scanned the same data set and wrote results to distinct S3 prefixes so the outputs can be compared reproducibly.

## Test Configuration

- **Dataset**: `s3a://spark-benchmarks-tpcds-data-1tb-us-west-2/TPCDS-TEST-1TB`
- **Scale factor**: 1000 (1 TB)
- **Iterations**: 1
- **Cluster capacity**: 8 × c5d.12xlarge nodes labelled `NodeGroupType=spark_benchmark_ssd1`
- **Executors**
  - Gluten + Velox: 23 executors, 5 cores, 20 Gi heap, 6 Gi overhead, 2 Gi off-heap
  - Native Spark: 24 executors, 5 cores, 20 Gi heap, 6 Gi overhead
- **Images**
  - Gluten: `<dockerhubuser>/spark-tpcds-gluten-velox:v1.0.0`
  - Native: `public.ecr.aws/data-on-eks/spark3.5.3-scala2.12-java17-python3-ubuntu-tpcds:v2`
- **Spark event logs**: `s3://spark-benchmarks-tpcds-data-1tb-us-west-2/spark-event-logs/`
- **Result prefixes**
  - Gluten: `s3://spark-benchmarks-tpcds-data-1tb-us-west-2/TPCDS-TEST-1TB-RESULT-GLUTEN/`
  - Native: `s3://spark-benchmarks-tpcds-data-1tb-us-west-2/TPCDS-TEST-1TB-RESULT-NATIVE/`

The raw query summaries copied from S3 are committed under `examples/tpcds-benchmark-spark-gluten-velox/results/`:

- `tpcds-1tb-gluten-summary.csv`
- `tpcds-1tb-native-summary.csv`
- `tpcds-1tb-comparison.csv`

Each CSV contains per-query median/min/max runtimes in seconds. The comparison file adds the native/gluten ratio (`>1` means Gluten was faster).

## High-Level Findings

- **Total median runtime**: Gluten 1 256 s (≈20.9 min) vs. Native 2 012 s (≈33.5 min)
- **Overall improvement**: native/gluten ratio 1.60× (Gluten finished ~37 % faster)
- **Per-query breakdown**: Gluten beat native on 90 of 104 queries, native won 14
- **Average per-query speedup**: 1.74×
- **Median per-query speedup**: 1.61×

## Top 10 Speedups (Native vs. Gluten)

> Native/Gluten greater than 1.0 indicates Gluten was faster. Delta is `native − gluten`.

| Query | Gluten Median (s) | Native Median (s) | Native / Gluten | Delta (Native-Gluten, s) |
|-------|-------------------|-------------------|-----------------|--------------------------|
| q93-v2.4 | 14.54 | 79.35 | 5.46x | 64.81 |
| q50-v2.4 | 10.57 | 39.13 | 3.70x | 28.57 |
| q62-v2.4 | 2.85 | 10.36 | 3.64x | 7.51 |
| q59-v2.4 | 4.94 | 17.58 | 3.56x | 12.64 |
| q97-v2.4 | 5.93 | 19.12 | 3.23x | 13.20 |
| q99-v2.4 | 3.62 | 11.23 | 3.10x | 7.61 |
| q5-v2.4 | 6.76 | 20.91 | 3.10x | 14.15 |
| q96-v2.4 | 3.13 | 8.92 | 2.85x | 5.80 |
| q23b-v2.4 | 53.93 | 146.11 | 2.71x | 92.18 |
| q84-v2.4 | 2.98 | 8.07 | 2.71x | 5.09 |

## Queries Where Native Stayed Ahead

Even with Gluten enabled, 14 queries trailed native Spark. The five largest regressions are listed below.

| Query | Gluten Median (s) | Native Median (s) | Native / Gluten | Delta (Native-Gluten, s) |
|-------|-------------------|-------------------|-----------------|--------------------------|
| q22-v2.4 | 23.25 | 8.12 | 0.35x | -15.13 |
| q72-v2.4 | 49.06 | 21.50 | 0.44x | -27.57 |
| q67-v2.4 | 158.25 | 72.69 | 0.46x | -85.57 |
| q54-v2.4 | 9.13 | 6.36 | 0.70x | -2.77 |
| q91-v2.4 | 3.92 | 2.95 | 0.75x | -0.96 |

## Reproducing the Comparison

1. Download the summary outputs from S3 (adjust the timestamp if a new run is produced):
   ```bash
   aws s3 cp s3://spark-benchmarks-tpcds-data-1tb-us-west-2/TPCDS-TEST-1TB-RESULT-GLUTEN/timestamp=1758686194100/summary.csv/part-00000-*.csv gluten-summary.csv
   aws s3 cp s3://spark-benchmarks-tpcds-data-1tb-us-west-2/TPCDS-TEST-1TB-RESULT-NATIVE/timestamp=1758686697081/summary.csv/part-00000-*.csv native-summary.csv
   ```
2. Combine them in a notebook or shell script. The committed `tpcds-1tb-comparison.csv` was generated with a small Python script that computes per-query ratios and overall statistics.
3. Review event logs in the Spark History Server by pointing it at `s3://spark-benchmarks-tpcds-data-1tb-us-west-2/spark-event-logs/` and replaying application `spark-3b17e3488d79404995ab0bb3cf9f6190` (Gluten) and `spark-b8c4002052844b628e76b04647fc2eee` (Native).

## Key Takeaways

- Gluten + Velox trimmed **~13 minutes** off the total benchmark time on the same hardware.
- Columnar/query-vectorized workloads (e.g., q93, q50, q62) benefit the most, with ≥3× speedups.
- A handful of queries (q22, q67, q72) remain slower under Gluten—these are good candidates for deeper plan inspection or falling back to native Spark selectively.
- The S3 outputs and local CSVs provide a reproducible artifact trail for future comparison runs.
