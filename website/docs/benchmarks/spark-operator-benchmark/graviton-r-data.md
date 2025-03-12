---
sidebar_position: 6
sidebar_label: Gravtion R-series Results
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../src/components/CollapsibleContent';
import CodeBlock from '@theme/CodeBlock';

import RSeriesNodeGroup from './_r_series_nodegroup.md'
import RSeriesSparkApp from './_r_series_spark_app.md'
import RSeriesDockerfile from './_r_series_dockerfile.md'

# TPCDS Spark Benchmark Results for Graviton R6g, R7g, and R8g
This page has the results of our benchmarking tests on R-series Graviton instances, demonstrating up to a 1.6x faster runtime on newer generation instances.

These benchmarks were executed using the steps defined in the [Running the Benchmark](./running-the-benchmark.md) section across 1TB of data. We used the same EKS cluster, the same data set, the same number of nodes, and the same addons and configuration for all of these tests. We simply changed the instance types that were used for each run.
The full configuration details are below:

<details>
<summary> To view the Managed Node Group configuration, Click to toggle content!</summary>

<RSeriesNodeGroup />

</details>

<details>
<summary> To view the Spark Application configuration, Click to toggle content!</summary>

<RSeriesSparkApp />

</details>

<details>
<summary> To view the Dockerfile for the Spark container image, Click to toggle content!</summary>

<RSeriesDockerfile />

</details>


## Results
When reviewing the results for the TPCDS benchmark we are interested in the time it takes for the Spark SQL queries to complete, the faster those queries complete the better.
The graph below shows the cumulative runtime in seconds for all of the queries for each instance type we tested:

[![Total runtimes for the benchmarks per instance type](./img/r-series-total-runtime.png)](https://github.com/awslabs/data-on-eks/blob/main/website/docs/benchmarks/spark-operator-benchmark/img/r-series-total-runtime.png)

We can similarly display the time for each query per instance, you can see the improvements in runtime for the newer generations.:

[![Total runtimes for the benchmarks per instance type](./img/r-series-per-query.png)](https://github.com/awslabs/data-on-eks/blob/main/website/docs/benchmarks/spark-operator-benchmark/img/r-series-per-query.png)

In the table below we have taken the Median times from the output for each instance type from a benchmark with 3 iterations of the queries and calculated the performance gained. You can view the [raw output data in the `raw_data` folder here](https://github.com/awslabs/data-on-eks/blob/main/website/docs/benchmarks/spark-operator-benchmark/raw_data).

To calculate the performance increase we are calculating a ratio of the query times. For example, to determine how much faster the r8g instances were compared to the r6g instances:
- Find the times corresponding to each query, using `q20-v2.4` as an example the r6g.12xlarge took `2.81s` and the r8g.12xlarge took `1.69s`.
- We then divide r5g.12xlarge/r8g.12xlarge, for q20-v2.4 that's `2.81s/1.69s = 1.66`. So for this query the r8g.12xlarge was able to complete the queries 1.66 times faster (or a ~66% percent improvement)

The data has been sorted by the last column, showing the performance increase r8g.12xlarge has over the r6g.12xlarge.
<div class="benchmark-results">
| Query | r6g.12xlarge | r7g.12xlarge | r8g.12xlarge |  | r7g times faster than r6g  | r8g times faster than r7g | r8g times faster than r6g |
| :---  | :----------- | :----------- | :----------- | :-- | :--------- | :--------- | :--------- |
| q20-v2.4 | 2.81 | 1.94 | 1.69 |  | 1.45 | 1.14 | 1.66 |
| q39b-v2.4 | 5.75 | 4.26 | 3.56 |  | 1.35 | 1.20 | 1.61 |
| q45-v2.4 | 7.66 | 5.69 | 4.92 |  | 1.35 | 1.15 | 1.56 |
| q8-v2.4 | 6.77 | 5.19 | 4.37 |  | 1.31 | 1.19 | 1.55 |
| q73-v2.4 | 5.08 | 3.96 | 3.31 |  | 1.28 | 1.20 | 1.54 |
| q39a-v2.4 | 6.60 | 4.84 | 4.36 |  | 1.36 | 1.11 | 1.51 |
| q81-v2.4 | 22.41 | 20.14 | 14.93 |  | 1.11 | 1.35 | 1.50 |
| q69-v2.4 | 7.81 | 5.74 | 5.26 |  | 1.36 | 1.09 | 1.48 |
| q34-v2.4 | 5.80 | 4.76 | 3.96 |  | 1.22 | 1.20 | 1.47 |
| q97-v2.4 | 19.76 | 15.13 | 13.60 |  | 1.31 | 1.11 | 1.45 |
| q95-v2.4 | 48.14 | 38.24 | 33.14 |  | 1.26 | 1.15 | 1.45 |
| q22-v2.4 | 9.79 | 7.57 | 6.81 |  | 1.29 | 1.11 | 1.44 |
| q24b-v2.4 | 71.09 | 59.12 | 49.64 |  | 1.20 | 1.19 | 1.43 |
| q15-v2.4 | 7.62 | 6.30 | 5.34 |  | 1.21 | 1.18 | 1.43 |
| q58-v2.4 | 5.05 | 4.12 | 3.57 |  | 1.22 | 1.16 | 1.41 |
| q18-v2.4 | 10.43 | 8.45 | 7.44 |  | 1.23 | 1.14 | 1.40 |
| q14b-v2.4 | 53.73 | 40.88 | 38.33 |  | 1.31 | 1.07 | 1.40 |
| q72-v2.4 | 22.29 | 17.19 | 16.08 |  | 1.30 | 1.07 | 1.39 |
| q98-v2.4 | 3.78 | 3.26 | 2.73 |  | 1.16 | 1.20 | 1.39 |
| q46-v2.4 | 13.37 | 11.00 | 9.65 |  | 1.21 | 1.14 | 1.39 |
| q83-v2.4 | 2.39 | 1.95 | 1.73 |  | 1.22 | 1.12 | 1.38 |
| q6-v2.4 | 11.11 | 8.83 | 8.08 |  | 1.26 | 1.09 | 1.37 |
| q31-v2.4 | 12.19 | 11.12 | 8.87 |  | 1.10 | 1.25 | 1.37 |
| q11-v2.4 | 23.95 | 19.30 | 17.72 |  | 1.24 | 1.09 | 1.35 |
| q29-v2.4 | 18.91 | 15.29 | 14.00 |  | 1.24 | 1.09 | 1.35 |
| q61-v2.4 | 5.26 | 4.62 | 3.92 |  | 1.14 | 1.18 | 1.34 |
| q91-v2.4 | 3.63 | 3.05 | 2.71 |  | 1.19 | 1.12 | 1.34 |
| q5-v2.4 | 20.57 | 16.72 | 15.42 |  | 1.23 | 1.08 | 1.33 |
| q54-v2.4 | 6.61 | 5.61 | 4.99 |  | 1.18 | 1.12 | 1.32 |
| q23b-v2.4 | 152.46 | 130.94 | 115.37 |  | 1.16 | 1.14 | 1.32 |
| q51-v2.4 | 11.90 | 9.90 | 9.06 |  | 1.20 | 1.09 | 1.31 |
| q57-v2.4 | 7.62 | 6.19 | 5.81 |  | 1.23 | 1.06 | 1.31 |
| q10-v2.4 | 8.38 | 6.70 | 6.41 |  | 1.25 | 1.05 | 1.31 |
| q24a-v2.4 | 75.07 | 63.24 | 57.78 |  | 1.19 | 1.09 | 1.30 |
| q64-v2.4 | 64.48 | 53.92 | 49.69 |  | 1.20 | 1.09 | 1.30 |
| q3-v2.4 | 3.39 | 2.44 | 2.62 |  | 1.39 | 0.93 | 1.29 |
| q14a-v2.4 | 61.18 | 50.12 | 47.37 |  | 1.22 | 1.06 | 1.29 |
| q65-v2.4 | 17.30 | 14.65 | 13.49 |  | 1.18 | 1.09 | 1.28 |
| q17-v2.4 | 6.95 | 5.54 | 5.44 |  | 1.25 | 1.02 | 1.28 |
| q79-v2.4 | 5.12 | 4.14 | 4.01 |  | 1.24 | 1.03 | 1.28 |
| q47-v2.4 | 8.45 | 7.56 | 6.62 |  | 1.12 | 1.14 | 1.28 |
| q60-v2.4 | 4.30 | 3.72 | 3.38 |  | 1.16 | 1.10 | 1.27 |
| ss_max-v2.4 | 10.48 | 9.13 | 8.29 |  | 1.15 | 1.10 | 1.26 |
| q35-v2.4 | 15.90 | 13.96 | 12.65 |  | 1.14 | 1.10 | 1.26 |
| q68-v2.4 | 7.93 | 6.64 | 6.32 |  | 1.19 | 1.05 | 1.25 |
| q77-v2.4 | 2.39 | 1.95 | 1.92 |  | 1.23 | 1.02 | 1.25 |
| q75-v2.4 | 38.27 | 32.63 | 30.71 |  | 1.17 | 1.06 | 1.25 |
| q42-v2.4 | 2.19 | 1.96 | 1.76 |  | 1.11 | 1.11 | 1.24 |
| q25-v2.4 | 5.64 | 4.84 | 4.55 |  | 1.17 | 1.06 | 1.24 |
| q93-v2.4 | 160.84 | 142.63 | 130.45 |  | 1.13 | 1.09 | 1.23 |
| q38-v2.4 | 16.80 | 14.77 | 13.66 |  | 1.14 | 1.08 | 1.23 |
| q74-v2.4 | 19.57 | 16.73 | 15.97 |  | 1.17 | 1.05 | 1.23 |
| q82-v2.4 | 14.10 | 12.66 | 11.55 |  | 1.11 | 1.10 | 1.22 |
| q4-v2.4 | 55.36 | 49.70 | 45.47 |  | 1.11 | 1.09 | 1.22 |
| q23a-v2.4 | 116.74 | 101.45 | 95.94 |  | 1.15 | 1.06 | 1.22 |
| q30-v2.4 | 15.69 | 15.56 | 12.91 |  | 1.01 | 1.21 | 1.22 |
| q94-v2.4 | 20.87 | 17.87 | 17.18 |  | 1.17 | 1.04 | 1.21 |
| q71-v2.4 | 3.83 | 3.08 | 3.16 |  | 1.24 | 0.98 | 1.21 |
| q86-v2.4 | 3.19 | 2.89 | 2.64 |  | 1.10 | 1.10 | 1.21 |
| q26-v2.4 | 5.94 | 5.67 | 4.91 |  | 1.05 | 1.15 | 1.21 |
| q59-v2.4 | 15.73 | 14.35 | 13.03 |  | 1.10 | 1.10 | 1.21 |
| q27-v2.4 | 7.15 | 6.26 | 5.93 |  | 1.14 | 1.06 | 1.21 |
| q41-v2.4 | 1.24 | 1.09 | 1.03 |  | 1.14 | 1.06 | 1.20 |
| q36-v2.4 | 6.15 | 5.27 | 5.11 |  | 1.17 | 1.03 | 1.20 |
| q56-v2.4 | 4.00 | 3.46 | 3.32 |  | 1.15 | 1.04 | 1.20 |
| q87-v2.4 | 15.46 | 14.13 | 12.96 |  | 1.09 | 1.09 | 1.19 |
| q21-v2.4 | 2.31 | 2.11 | 1.94 |  | 1.09 | 1.08 | 1.19 |
| q32-v2.4 | 2.04 | 1.83 | 1.73 |  | 1.11 | 1.06 | 1.18 |
| q78-v2.4 | 82.43 | 75.70 | 70.26 |  | 1.09 | 1.08 | 1.17 |
| q88-v2.4 | 40.39 | 36.38 | 34.44 |  | 1.11 | 1.06 | 1.17 |
| q48-v2.4 | 7.89 | 7.24 | 6.74 |  | 1.09 | 1.07 | 1.17 |
| q33-v2.4 | 4.06 | 3.67 | 3.47 |  | 1.11 | 1.06 | 1.17 |
| q99-v2.4 | 9.36 | 8.36 | 8.02 |  | 1.12 | 1.04 | 1.17 |
| q16-v2.4 | 28.35 | 24.72 | 24.41 |  | 1.15 | 1.01 | 1.16 |
| q12-v2.4 | 2.60 | 2.64 | 2.24 |  | 0.98 | 1.18 | 1.16 |
| q28-v2.4 | 41.47 | 37.51 | 35.84 |  | 1.11 | 1.05 | 1.16 |
| q76-v2.4 | 23.72 | 21.55 | 20.66 |  | 1.10 | 1.04 | 1.15 |
| q1-v2.4 | 6.24 | 5.33 | 5.43 |  | 1.17 | 0.98 | 1.15 |
| q37-v2.4 | 7.81 | 7.18 | 6.85 |  | 1.09 | 1.05 | 1.14 |
| q90-v2.4 | 9.91 | 8.97 | 8.77 |  | 1.10 | 1.02 | 1.13 |
| q80-v2.4 | 22.63 | 20.72 | 20.13 |  | 1.09 | 1.03 | 1.12 |
| q66-v2.4 | 8.09 | 7.54 | 7.23 |  | 1.07 | 1.04 | 1.12 |
| q67-v2.4 | 145.51 | 140.91 | 130.01 |  | 1.03 | 1.08 | 1.12 |
| q7-v2.4 | 7.82 | 6.61 | 7.00 |  | 1.18 | 0.94 | 1.12 |
| q50-v2.4 | 71.71 | 70.06 | 64.46 |  | 1.02 | 1.09 | 1.11 |
| q19-v2.4 | 4.61 | 3.98 | 4.16 |  | 1.16 | 0.96 | 1.11 |
| q89-v2.4 | 4.71 | 4.53 | 4.27 |  | 1.04 | 1.06 | 1.10 |
| q13-v2.4 | 8.75 | 8.30 | 7.98 |  | 1.05 | 1.04 | 1.10 |
| q63-v2.4 | 4.51 | 4.36 | 4.12 |  | 1.03 | 1.06 | 1.10 |
| q85-v2.4 | 14.98 | 13.86 | 13.72 |  | 1.08 | 1.01 | 1.09 |
| q70-v2.4 | 8.20 | 8.28 | 7.55 |  | 0.99 | 1.10 | 1.09 |
| q62-v2.4 | 8.97 | 8.60 | 8.28 |  | 1.04 | 1.04 | 1.08 |
| q44-v2.4 | 19.24 | 18.94 | 17.78 |  | 1.02 | 1.07 | 1.08 |
| q84-v2.4 | 9.72 | 9.51 | 9.01 |  | 1.02 | 1.05 | 1.08 |
| q96-v2.4 | 8.92 | 8.26 | 8.29 |  | 1.08 | 1.00 | 1.08 |
| q9-v2.4 | 34.46 | 32.49 | 32.07 |  | 1.06 | 1.01 | 1.07 |
| q2-v2.4 | 14.12 | 13.05 | 13.21 |  | 1.08 | 0.99 | 1.07 |
| q52-v2.4 | 2.00 | 1.97 | 1.87 |  | 1.01 | 1.05 | 1.07 |
| q43-v2.4 | 4.39 | 4.14 | 4.13 |  | 1.06 | 1.00 | 1.06 |
| q92-v2.4 | 1.53 | 1.56 | 1.46 |  | 0.98 | 1.07 | 1.05 |
| q40-v2.4 | 12.33 | 11.43 | 11.82 |  | 1.08 | 0.97 | 1.04 |
| q49-v2.4 | 26.01 | 26.02 | 25.04 |  | 1.00 | 1.04 | 1.04 |
| q53-v2.4 | 4.53 | 4.64 | 4.42 |  | 0.98 | 1.05 | 1.03 |
| q55-v2.4 | 2.36 | 2.15 | 2.50 |  | 1.10 | 0.86 | 0.94 |

</div>
