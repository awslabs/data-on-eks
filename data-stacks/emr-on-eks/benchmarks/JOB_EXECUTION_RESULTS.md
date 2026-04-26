# EMR on EKS PCP Job Execution Results

Use this single document to track all benchmark executions across PCP tiers.

## Common Config

| EMR Endpoint | Queries | Iterations | Scale Factor | Executors/Job | Executor Cores/Memory | Driver Cores/Memory |
|---|---|---:|---:|---:|---|---|
| `https://emr-containers-gamma.<aws-region>.amazonaws.com` | `q4-v2.4,q24a-v2.4,q24b-v2.4,q67-v2.4` | `1` | `1000` | `30` | `2 / 5g` | `1 / 2g` |

## PCP Tier Limits

| PCP Tier | API Seat Limit | Pod Scheduling Limit | etcd Limit |
|---|---:|---|---|
| `XL` | `1700` | `167 pods/s` | `16 GB` |
| `2XL` | `3400` | `283 pods/s` | `16 GB` |
| `4XL` | `6800` | `400 pods/s` | `16 GB` |
| `8XL` | `13600` | `400 pods/s` | `16 GB` |

## Job Execution Results

| Run ID | PCP Tier | Start Time (UTC) | End Time (UTC) | Active Jobs At Start | Active Jobs At End | Target Jobs/Min | EMR Jobs Submitted | Jobs Failed During Run | Failure Rate | Locust `start_job_run` Rate | Observed Jobs/Min | Job Success Rate | Max API Seats | Max API Seats % Tier | API Req Duration p99 | Max etcd Size Used (GB) | Max etcd % Tier | etcd Req Duration p99 | etcd Requests/s | Scheduler Queue Depth | Unschedulable Pods/s | Peak Pods Scheduled/Min | Maximum Nodes | Running K8s Jobs | Total Pods | Feedback |
|---|---|---|---|---:|---:|---|---:|---:|---|---|---|---|---:|---|---|---|---|---|---|---|---|---|---:|---:|---:|---|
| `4xl-run-001-100-jpm` | `4XL` |  |  |  |  | `100 jobs/min` |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| `4xl-run-002-200-jpm` | `4XL` |  |  |  |  | `200 jobs/min` |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| `4xl-run-003-300-jpm` | `4XL` |  |  |  |  | `300 jobs/min` |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |

## Metric Capture Reference

| Result Column | Source | Prometheus Query or Capture Method | Why It Matters |
|---|---|---|---|
| `Target Jobs/Min` | Benchmark config | From `benchmark.sh` run settings | Planned submission target for the step |
| `EMR Jobs Submitted` | Locust / benchmark logs | Submitted count from Locust summary or benchmark logs | Confirms how much work was actually launched |
| `Jobs Failed During Run` | Locust / EMR API | Failed count from Locust summary and EMR failures | Shows whether the step was clean or breaking |
| `Failure Rate` | Locust | Locust failure rate for `start_job_run` | Fast signal for throttling or API instability |
| `Locust start_job_run Rate` | Locust | Locust summary for `start_job_run` | Measures actual API submission throughput |
| `Observed Jobs/Min` | Prometheus / Grafana | `(sum(clamp_max(changes(kube_pod_status_phase{namespace=~"emr-data-team-.*|spark-team-.*|spark-s3-express",phase="Running",pod=~"spark-.*-driver"}[5m]), 1)) / 5) or vector(0)` | Converts driver starts into cluster-observed jobs/min |
| `Job Success Rate` | Prometheus / Grafana | `((sum(clamp_max(changes(kube_pod_status_phase{namespace=~"emr-data-team-.*|spark-team-.*|spark-s3-express",phase="Succeeded",pod=~"spark-.*-driver"}[5m]), 1))) / ((sum(clamp_max(changes(kube_pod_status_phase{namespace=~"emr-data-team-.*|spark-team-.*|spark-s3-express",phase="Succeeded",pod=~"spark-.*-driver"}[5m]), 1))) + (sum(clamp_max(changes(kube_pod_status_phase{namespace=~"emr-data-team-.*|spark-team-.*|spark-s3-express",phase="Failed",pod=~"spark-.*-driver"}[5m]), 1))) + 0.0001)) or on() vector(0)` | Shows cluster-level success under load |
| `Max API Seats` | Prometheus / Grafana | `sum(apiserver_flowcontrol_current_executing_seats)` | Core PCP control-plane pressure metric |
| `Max API Seats % Tier` | Prometheus / rules | `apiserver_flowcontrol_current_executing_seats / <tier API seat limit> * 100` | Normalizes pressure against the active PCP tier limit |
| `API Req Duration p99` | Prometheus / Grafana | `histogram_quantile(0.99, sum(rate(apiserver_request_duration_seconds_bucket{verb!~"WATCH|CONNECT"}[5m])) by (le))` | Surfaces API latency degradation before outright failure |
| `Max etcd Size Used (GB)` | Prometheus / Grafana | `apiserver_storage_size_bytes / 1e9` | Tracks proximity to the etcd storage ceiling |
| `Max etcd % Tier` | Prometheus / rules | `apiserver_storage_size_bytes / 1.6e10 * 100` | Normalizes etcd pressure against the tier etcd limit, which is currently 16 GB for all tiers |
| `etcd Req Duration p99` | Prometheus / Grafana | `histogram_quantile(0.99, sum(rate(etcd_request_duration_seconds_bucket[5m])) by (le, operation))` | Best available live etcd latency signal in the current dashboard |
| `etcd Requests/s` | Prometheus | `sum(rate(etcd_request_duration_seconds_count[5m]))` | Approximates etcd request pressure during the run |
| `Scheduler Queue Depth` | Prometheus / Grafana | `scheduler_pending_pods{queue="active"}`, `scheduler_pending_pods{queue="backoff"}`, `scheduler_pending_pods{queue="unschedulable"}` | Shows scheduler backlog and pressure directly |
| `Unschedulable Pods/s` | Prometheus / rules | `sum(rate(scheduler_schedule_attempts_total{result="unschedulable"}[1m]))` | Indicates scheduling failure as scale rises |
| `Peak Pods Scheduled/Min` | Prometheus / Grafana | `(sum(rate(scheduler_schedule_attempts_total{result="scheduled"}[1m])) * 60) or vector(0)` | Measures achieved scheduler throughput |
| `Maximum Nodes` | Prometheus / Grafana | `count(kube_node_info) or vector(0)` | Captures scale-out required for the run |
| `Running K8s Jobs` | Prometheus / Grafana | `count(kube_pod_info{namespace=~"emr-data-team-.*|spark-team-.*|spark-s3-express",pod=~"spark-.*-driver"}) or vector(0)` | Best current approximation of concurrently running Spark jobs |
| `Total Pods` | Prometheus / Grafana | `sum(kube_pod_info)` | Tracks overall object pressure on the cluster |
| `Feedback` | Human summary | Fill in manually after each run | Final decision input: what broke first, whether the run is acceptable, and the next step |

## Notes

- Add one row per benchmark run.
- Use the maximum observed value during the run window for the `Max` and `Peak` columns.
- Record `Active Jobs At Start` as `0` before every planned step unless the run is intentionally layered.
- Record `Active Jobs At End` before starting the next run so drain behavior is part of the decision.
- `etcd Slow Apply` is not currently exposed in the existing dashboard or rules. `etcd Req Duration p99` is the best live etcd latency signal currently available.
- `Scheduler Queue Depth` should be recorded as a compact summary such as `active/backoff/unschedulable`.
- Keep `Feedback` as the final summary for throttling, PCP saturation, stability, first bottleneck, and the next-step recommendation.
- If the benchmark definition changes, update the `Common Config` table before recording new runs.
