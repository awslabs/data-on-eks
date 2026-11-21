# EKS scale test with Spark workloads

This document tells you how to run the EKS scale test on the cluster of this stack, what to
monitor during a run, and what the tests have shown so far.

## 1. Goal and method

The test measures how the EKS control plane and the cluster add-ons behave under a high pod
churn rate and a high node count. The target is about 10,000 nodes in one Availability Zone.

Spark applications create the load. Each application is a fixed unit of load:

| Unit | Value |
| --- | --- |
| Pods | 31 (1 driver, 30 executors, 1 core and 4 GiB + 1 GiB each) |
| Nodes | 1 node of the `tpcds-static` NodePool (r8g.8xlarge). One application fills one node |
| Runtime | about 3.5 minutes (TPC-DS SF30, queries `q4`, `q24a`, `q24b`, `q67`, 1 iteration) |

The submission rate sets the load:

```
pod creates/s    = rate (apps/min) x 31 / 60
concurrent pods  = rate (apps/min) x runtime (min) x 31
concurrent nodes = rate (apps/min) x runtime (min)
```

The load generator has these parts. They are not the system under test, but they must stay
healthy, or the load is not what you expect:

| Part | Setting |
| --- | --- |
| Locust (`benchmarks/spark-operator-benchmarks/locustfile.py`) | Creates SparkApplications at a fixed rate |
| Spark Operator (chart 2.6.0) | 1 controller, 8 CPU, 16 GiB, 50 workers, on NodePool `spark-operator`. Feature gate `RestSubmitter` |
| REST submitter (namespace `spark-submitter`) | 3 replicas, 24 submission slots each, on NodePool `spark-operator`. Runs `spark-submit` for the operator |
| Static NodePool `tpcds-static` | r8g.8xlarge, on-demand, one zone (`topology.k8s.aws/zone-id`), 200 GiB gp3 root volume |
| TPC-DS data | S3, prefixes `c01` to `c50` (section 2.3) |
| Monitor scripts | `scripts/load-test-monitor.py`, `scripts/load-test-scale-down.py` |

## 2. One-time preparation

### 2.1 Set the results bucket

The bucket name changes on each deployment. Set it in each shell that you use:

```bash
B=$(terraform -chdir=terraform output -raw s3_bucket_id_spark_history_server); echo "B=$B"
DATA=<tpcds-data-bucket>
```

Locust stops at startup if `--results-bucket` is empty.

### 2.2 Apply the log4j ConfigMap

The application pods mount `spark-log4j2-config`. Apply it in each test namespace:

```bash
kubectl apply -f spark-log4j2-configmap.yaml
```

### 2.3 Prepare the TPC-DS data

The application reads `s3a://$DATA/cNN/tpcds/sf30/`, with `cNN` from `c01` to `c50`. Locust
spreads the applications over these prefixes, so that the S3 request load is spread too.

Turn on S3 request metrics on the data bucket, so that you can see throttling (section 4.4):

```bash
aws s3api put-bucket-metrics-configuration --bucket "$DATA" \
  --id EntireBucket --metrics-configuration '{"Id":"EntireBucket"}'
```

Before a run with thousands of applications, ask AWS Support to pre-partition the data bucket on
the `cNN/` prefixes, and the logs bucket on the results and log prefixes. Section 6.2 gives the
request rates.

## 3. Run the test

### 3.1 Scale up the static NodePool

`replicas` is 0 in the file, so no static nodes run between tests. Set the node count on the
cluster:

```bash
kubectl patch nodepool tpcds-static --type merge -p '{"spec":{"replicas":100}}'
kubectl get nodes -l karpenter.sh/nodepool=tpcds-static -L topology.k8s.aws/zone-id
```

The next `terraform apply` of `kubectl_manifest.karpenter_resources` sets `replicas` back to the
value in the file (0).

### 3.2 Calculate the rate

One application uses one node for its full runtime, so the maximum steady rate is:

```
maximum apps/min = static nodes / runtime (min)
```

With a runtime of 3.4 to 3.7 minutes, 100 nodes take at most about 27 apps/min. Use about 90% of
the maximum. Above the maximum, drivers wait for nodes, and the queue grows with no limit.

| Rate | Nodes | Concurrent pods | Pod creates/s | Status |
| --- | --- | --- | --- | --- |
| 25/min | 100 | about 2,700 | about 13 | Tested (section 6.1) |
| 250/min | 1,000 | about 27,000 | about 130 | Not tested |
| 2,700/min | 10,000 | about 290,000 | about 1,400 | Not possible with 1 iteration (section 6.2) |

Increase the node count in steps (100, 1,000, then more). Before each step, check that the EKS
signals of the step before stayed in their normal range (section 4.1).

### 3.3 Start the monitor and the scale-down watcher

The scripts use the current kubeconfig context. They need `uv`, which installs the Kubernetes
Python client. To send the requests to an API endpoint that does its own authentication, set
`K8S_API_URL`.

```bash
START=$(date -u +%Y-%m-%dT%H:%M:%S+00:00)
uv run scripts/load-test-monitor.py run.jsonl "$START" &
# Sets replicas to 0 when all apps of the run are final, or at the deadline.
uv run scripts/load-test-scale-down.py "$START" "$(date -u -d '+90 min' +%Y-%m-%dT%H:%M:%S+00:00)" &
```

The monitor writes one JSON line every 15 seconds. It counts only `tpcds-*` applications in
`spark-team-a` that were created after `START`.

### 3.4 Start Locust

```bash
cd benchmarks/spark-operator-benchmarks
uv run locust --headless -u 5 -r 1 --jobs-per-min 5 --job-limit-per-user 150 \
  --tpcds-iterations 1 --prefix-count 50 --zone-id use1-az6 \
  --results-bucket "$B" --no-spark-cleanup
```

| Option | Meaning |
| --- | --- |
| `-u`, `--jobs-per-min` | Number of users, and rate for each user. Total rate = users x rate. The example gives 25/min |
| `--job-limit-per-user` | Applications for each user. Run time = limit / rate. The example gives 30 minutes |
| `--tpcds-iterations` | Query iterations for each application. More iterations give a longer runtime |
| `--prefix-count` | Number of `cNN` prefixes to use, from `c01`. Use only prefixes that are complete |
| `--zone-id` | Zone ID of the static nodes. Use the zone ID, not the zone name: zone names map to different zones in each AWS account |
| `--results-bucket` | Required. The bucket from section 2.1 |
| `--tpcds-bucket`, `--tpcds-data-path` | Data bucket and path under each prefix. The defaults match section 2.3 |
| `--spark-namespaces` | Comma-separated namespaces. The default is `spark-team-a` |
| `--no-spark-cleanup` | Keeps the applications after Locust stops, so they can complete |

To stop the run, press Ctrl+C. Applications that Locust already created continue to run.

### 3.5 After the run

1. Make sure that `replicas` is 0. The watcher sets it, or set it yourself:

   ```bash
   kubectl patch nodepool tpcds-static --type merge -p '{"spec":{"replicas":0}}'
   ```

2. Delete the applications. This command deletes all SparkApplications in `spark-team-a`:

   ```bash
   kubectl -n spark-team-a delete sparkapplications --all
   ```

## 4. What to monitor

Show the last monitor sample:

```bash
tail -n 1 run.jsonl | python3 -m json.tool
```

### 4.1 EKS signals (field `eks`)

The monitor reads these values from Prometheus (namespace `monitoring`, service
`prometheus-prometheus`, port 9090).

| Field | Prometheus source | Value at 100 nodes (section 6.1) | Problem sign |
| --- | --- | --- | --- |
| `api_req_s` | `apiserver_request_total` | about 590, peak 734 | Grows faster than the pod count |
| `api_429_s`, `api_5xx_s` | `apiserver_request_total` by `code` | 0 | Any value above 0 |
| `apf_inqueue`, `apf_rejected_s` | `apiserver_flowcontrol_*` | 0 | Requests wait or are rejected by API Priority and Fairness |
| `api_p99_mutating_s` | `apiserver_request_duration_seconds` (POST, PUT, PATCH, DELETE) | 0.025 s | Above about 1 s |
| `api_p99_list_s` | Same, verb LIST | 0.65 s | Increases during the run |
| `pod_create_s` | Pod POST requests | about 13 | Lower than rate x 31 / 60: the load generator is behind |
| `pod_bind_s` | Pod `binding` POST requests (scheduler placements) | about 13 | Lower than `pod_create_s` for a long time: the scheduler is behind |
| `etcd_mb` | `apiserver_storage_size_bytes` | about 1,900 MB | Near the etcd limit of the control plane tier |
| `coredns_p99_s` | `coredns_dns_request_duration_seconds` | 0.008 s | Above about 0.1 s |

The scheduler metrics (`scheduler_*`) may not be available. Use `pod_bind_s` for the scheduling
throughput and `pending_oldest_s` (section 4.2) for the scheduling delay.

### 4.2 Pods and nodes

| Field | Normal | Problem sign |
| --- | --- | --- |
| `pods` | Executor and driver Running counts stay flat | Pending counts increase |
| `pending_oldest_s` | Below about 60 | Increases from sample to sample |
| `unschedulable` | Not present, or small for a short time | Increases: no free nodes, or a scheduling problem |
| `static_nodes_ready` | The `replicas` value | Lower: nodes are not Ready or did not launch. Look at the Karpenter log |

### 4.3 Load generator health

If one of these values is not normal, the EKS numbers of the run do not show the planned load.

| Field | Normal | Problem sign, and what to do |
| --- | --- | --- |
| `apps` | `RUNNING` stays flat, `COMPLETED` increases | `SUBMITTED` increases: drivers wait for nodes. Stop Locust or lower the rate |
| `runtime_min_p50_p90_max` | p50 3.4 to 3.7 | p50 increases: a shared resource limits the apps, usually S3 (section 4.4) |
| `new_failures` | Not present | Read the driver log of the failed application (see the table below) |
| `submitter` | `failure_count` does not increase | `SUBMITTER_OVERLOADED` (503): all slots are in use. Add replicas or slots |
| `operator` | `depth{sparkapplication}` near 0 | The depth increases: the controller cannot keep up |

```bash
kubectl -n spark-team-a get sparkapplications | grep -v COMPLETED
kubectl -n spark-team-a logs <app>-driver | grep -E 'Exception|Caused by|Status Code' | head
```

| Message | Cause |
| --- | --- |
| `Status Code: 503`, "Please reduce your request rate" in the driver log | S3 throttling. See section 4.4 |
| `bucket is null/empty` in the driver log | `--results-bucket` was empty |

### 4.4 S3 metrics

The metrics arrive in CloudWatch a few minutes late. Set the run window, then read them:

```bash
FROM=2026-01-01T00:00:00Z; TO=2026-01-01T00:30:00Z
for m in 5xxErrors GetRequests ListRequests; do echo "== $m"
  aws cloudwatch get-metric-statistics --region us-east-1 --namespace AWS/S3 --metric-name $m \
    --dimensions Name=BucketName,Value=$DATA Name=FilterId,Value=EntireBucket \
    --start-time $FROM --end-time $TO --period 300 --statistics Sum \
    --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Sum]' --output text
done
```

`5xxErrors` must stay near 0. In the run of section 6.1, `GetRequests` divided by the completed
applications was about 2,520.

## 5. Logs and results

| Item | Location |
| --- | --- |
| Query results | `s3://$B/cNN/tpcds-results/<app name>/` |
| Spark pod logs | `s3://$B/spark-on-eks/spark-application-logs/<shard>/<namespace>/<pod>/` |
| Monitor samples | The file that you gave to `load-test-monitor.py` |

`<shard>` is the last character of the application name. It spreads the log uploads over up to 36
S3 prefixes. Fluent Bit uploads a pod log about 5 minutes after the last line, or when its buffer
is full.

Executors of all applications have the same `spark-app-name` label (from `spark.app.name`). To
group pods or metrics by application, use the `spark-app-selector` label.

## 6. Findings so far

### 6.1 EKS at 100 nodes, 25 apps/min

The run lasted 30 minutes: 750 applications, about 84 concurrent applications, about 2,600
concurrent Spark pods. Values are averages over 25 minutes of steady state, unless the table
gives a peak.

| Area | Result |
| --- | --- |
| API requests | 590 req/s average, 734 req/s peak (1-minute rate), 6 API server instances |
| Mutating requests by resource | events 172/s, pods 121/s, sparkapplications 78/s, serviceaccounts 26/s (pod tokens), leases 19/s |
| Errors | 0 responses with code 429, 0 with code 5xx. API Priority and Fairness: 0 queued, 0 rejected |
| API latency (p99) | mutating 25 ms (33 ms in the worst 5 minutes), GET 24 ms, LIST 651 ms |
| Pods | 13.0 creates/s and 13.2 bindings/s, binding p99 21 ms. Oldest Pending pod: 29 s or less |
| etcd | about 1.9 GB |
| CoreDNS | 256 req/s, p99 8 ms |
| Load generator | 750 of 750 applications completed. Runtime p50 3.4 min, p90 3.7 min. 0 submitter failures. Operator queue depth 0 |
| S3 data bucket | about 1,050 GET/s, about 2,520 GETs for each application, 1 error of type 5xx in about 1.9 million GETs |
| Node disk | about 2 GiB for each application at peak. A 200 GiB root volume is enough |

At this size, the control plane had no errors and low latency. The load was about 3% of the pod
scheduling rate of the control plane tier (400 pods/s for 8XL).

### 6.2 Projection for 10,000 nodes (not tested)

These values assume that the load grows linearly with the number of concurrent applications.

**Pod scheduling limits the rate.** With 1 iteration (3.5 minutes), 10,000 nodes need about
2,700 apps/min, which is about 1,400 pod creates/s. The 8XL tier schedules about 400 pods/s.
At 400 pods/s, the maximum rate is about 770 apps/min. To fill 10,000 nodes at that rate, each
application must run at least about 13 minutes. Use more iterations (`--tpcds-iterations`), and
measure the runtime first.

**API load.** At 100 nodes, each concurrent application caused about 7 API requests/s. At
10,000 concurrent applications that gives about 70,000 req/s. The largest parts are events
(about 20,000/s) and SparkApplication writes (about 9,000/s). A longer runtime lowers the
creates and the events for each second, but not the status writes for running applications.

**S3.** With about 12 GET/s for each running application:

| | Total GET/s | GET/s for each of 50 prefixes | Share of 5,500 GET/s per prefix |
| --- | --- | --- | --- |
| Average | about 124,000 | about 2,500 | about 45% |
| All applications in their busiest phase | about 230,000 | about 4,600 | about 84% |

S3 gives 5,500 GET/s for each prefix only after it has partitioned the bucket. A new or lightly
used bucket throttles at a much lower rate. Ask for pre-partitioning before the
run, and increase the rate in steps.

## 7. Known items

- Static nodes do not follow the pod zone. The zone is set in
  `terraform/manifests/karpenter/nodepool-tpcds-static.yaml`. The Locust `--zone-id` value must
  be the same zone ID.
- The static NodePool needs the Karpenter feature gate `StaticCapacity=true`.
