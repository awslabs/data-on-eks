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
| CPU | 31 vCPU. The pods of one application can run on more than one node |
| Runtime | about 3.5 minutes on r8g.8xlarge, about 5.2 minutes on r6g.4xlarge (TPC-DS SF30, queries `q4`, `q24a`, `q24b`, `q67`, 1 iteration) |

The submission rate sets the load:

```
pod creates/s    = rate (apps/min) x 31 / 60
concurrent pods  = rate (apps/min) x runtime (min) x 31
```

The load generator has these parts. They are not the system under test, but they must stay
healthy, or the load is not what you expect:

| Part | Setting |
| --- | --- |
| Locust (`benchmarks/spark-operator-benchmarks/locustfile.py`) | Creates SparkApplications at a fixed rate. Each application has `timeToLiveSeconds: 300` |
| Spark Operator (chart 2.6.0) | 1 controller, 8 CPU, 16 GiB, 100 workers, API client 2,000 QPS (burst 4,000), work queue rate limiter 1,000 QPS (bucket 10,000), on NodePool `spark-operator`. Feature gate `RestSubmitter` |
| REST submitter (namespace `spark-submitter`) | 3 replicas, 24 submission slots each, on NodePool `spark-operator`. Runs `spark-submit` for the operator |
| Static NodePool `tpcds-static` | r6g, r7g and r8g in 4xlarge, 8xlarge and 12xlarge, and r8gd.8xlarge. On-demand, one zone (`topology.k8s.aws/zone-id`), 40 GiB gp3 root volume |
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
the `cNN/` prefixes, and the logs bucket on the results and log prefixes. Section 6.3 gives the
request rates.

### 2.4 Check the quotas

Each static node has a 40 GiB gp3 root volume, and the gp3 storage quota is for each Region.

| Static nodes | gp3 for the static nodes | vCPU (all 4xlarge to all 12xlarge) |
| --- | --- | --- |
| 1,000 | about 39 TiB | 16,000 to 48,000 |
| 10,000 | about 391 TiB | 160,000 to 480,000 |

Add the volumes and the vCPU of the other nodes of the cluster. If a quota is too low, Karpenter
cannot launch all nodes (section 6.2).

## 3. Run the test

### 3.1 Scale up the static NodePool

`replicas` is 0 in the file, so no static nodes run between tests. Set the node count on the
cluster:

```bash
kubectl patch nodepool tpcds-static --type merge -p '{"spec":{"replicas":1000}}'
kubectl get nodeclaims -l karpenter.sh/nodepool=tpcds-static -L node.kubernetes.io/instance-type
```

The next `terraform apply` of `kubectl_manifest.karpenter_resources` sets `replicas` back to the
value in the file (0).

If some NodeClaims do not become Ready, read the Karpenter log. Set `replicas` to the number of
Ready nodes, so that Karpenter stops the launch attempts (section 6.2).

### 3.2 Calculate the rate

The static NodePool can use 9 instance types. Karpenter usually selects the lowest-price type, so
the capacity of each node is different from run to run. Calculate the rate from the pod slots
after the nodes are up:

```
pod slots for each node = (allocatable CPU - DaemonSet CPU requests), rounded down
application capacity    = (static nodes x pod slots for each node) / 31
rate (apps/min)         = 0.8 x application capacity / runtime (min)
users (-u)              = rate / 5        (with --jobs-per-min 5)
```

The monitor field `static_vcpu_ready` gives the total vCPU of the Ready static nodes.

| Nodes | Instance type | Pod slots | Application capacity | Rate at 80% | Status |
| --- | --- | --- | --- | --- | --- |
| 100 | r8g.8xlarge | 31 for each node | 100 | 25/min | Tested (section 6.1) |
| 746 | r6g.4xlarge | 15 for each node | about 360 | 55/min (65/min was too high) | Tested (section 6.2) |
| 1,000 | r6g.4xlarge | 15 for each node | about 480 | about 75/min | Not tested |

Above the capacity, drivers and executors wait for free slots, and the queue grows with no limit.

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
uv run scripts/load-test-scale-down.py "$START" "$(date -u -d '+75 min' +%Y-%m-%dT%H:%M:%S+00:00)" &
```

The monitor writes one JSON line every 15 seconds. It counts only `tpcds-*` applications in
`spark-team-a` that were created after `START`. The TTL deletes final applications after 300
seconds, so the monitor keeps the final state of each application in memory. Its totals are for
the full run.

The watcher prints one status line every 30 seconds. If no line comes, the watcher cannot reach
the API server.

### 3.4 Start Locust

```bash
cd benchmarks/spark-operator-benchmarks
uv run locust --headless -u 15 -r 0.05 --jobs-per-min 5 --job-limit-per-user 200 \
  --tpcds-iterations 1 --prefix-count 50 --zone-id use1-az6 \
  --results-bucket "$B" --no-spark-cleanup
```

| Option | Meaning |
| --- | --- |
| `-u`, `--jobs-per-min` | Number of users, and rate for each user. Total rate = users x rate. The example gives 75/min |
| `-r` | Users added each second. `0.05` adds 1 user every 20 seconds, so the rate increases slowly |
| `--job-limit-per-user` | Applications for each user. Run time for each user = limit / rate. The example gives 40 minutes |
| `--tpcds-iterations` | Query iterations for each application. More iterations give a longer runtime |
| `--prefix-count` | Number of `cNN` prefixes to use, from `c01`. Use only prefixes that are complete |
| `--zone-id` | Zone ID of the static nodes. Use the zone ID, not the zone name: zone names map to different zones in each AWS account |
| `--results-bucket` | Required. The bucket from section 2.1 |
| `--tpcds-bucket`, `--tpcds-data-path` | Data bucket and path under each prefix. The defaults match section 2.3 |
| `--spark-namespaces` | Comma-separated namespaces. The default is `spark-team-a` |
| `--no-spark-cleanup` | Keeps the applications after Locust stops, so they can complete. Without it, Locust deletes all applications when it stops, also the running ones |

To stop the run, press Ctrl+C. Applications that Locust already created continue to run.

### 3.5 After the run

1. Make sure that `replicas` is 0. The watcher sets it, or set it yourself:

   ```bash
   kubectl patch nodepool tpcds-static --type merge -p '{"spec":{"replicas":0}}'
   ```

2. The TTL deletes each application 300 seconds after it ends. To delete the applications at
   once, use this command. It deletes all SparkApplications in `spark-team-a`:

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

| Field | Prometheus source | 100 nodes (section 6.1) | 746 nodes (section 6.2) | Problem sign |
| --- | --- | --- | --- | --- |
| `api_req_s` | `apiserver_request_total` | about 590, peak 734 | about 1,200, peak 3,663 | Grows faster than the pod count |
| `api_429_s`, `api_5xx_s` | `apiserver_request_total` by `code` | 0 | 0, and one 504 in the run | Any value above 0 |
| `apf_inqueue`, `apf_rejected_s` | `apiserver_flowcontrol_*` | 0 | 0 rejected, at most 1 in queue | Requests wait or are rejected by API Priority and Fairness |
| `api_p99_mutating_s` | `apiserver_request_duration_seconds` (POST, PUT, PATCH, DELETE) | 0.025 s | at most 0.04 s | Above about 1 s |
| `api_p99_list_s` | Same, verb LIST | 0.65 s | at most 0.89 s | Increases during the run |
| `pod_create_s` | Pod POST requests | about 13 | about 28, peak 159 | Lower than rate x 31 / 60: the load generator is behind |
| `pod_bind_s` | Pod `binding` POST requests (scheduler placements) | about 13 | about 28, peak 115 | Lower than `pod_create_s` for a long time: the scheduler is behind |
| `etcd_mb` | `apiserver_storage_size_bytes` | about 1,900 MB | about 1,400 MB | Near the etcd limit of the control plane tier. This value may not show the real etcd size |
| `coredns_p99_s` | `coredns_dns_request_duration_seconds` | 0.008 s | at most 0.031 s | Above about 0.1 s |

The scheduler metrics (`scheduler_*`) may not be available. Use `pod_bind_s` for the scheduling
throughput and `pending_oldest_s` (section 4.2) for the scheduling delay.

### 4.2 Pods and nodes

| Field | Normal | Problem sign |
| --- | --- | --- |
| `pods` | Executor and driver Running counts stay flat | Pending counts increase |
| `pending_oldest_s` | Below about 60 | Increases from sample to sample |
| `unschedulable` | Not present, or small for a short time | Increases: no free pod slots, or a scheduling problem |
| `static_nodes_ready` | The `replicas` value | Lower: NodeClaims are not Ready or did not launch. Look at the Karpenter log |
| `static_vcpu_ready` | Constant during the run | Use it to calculate the rate (section 3.2) |

### 4.3 Load generator health

If one of these values is not normal, the EKS numbers of the run do not show the planned load.

| Field | Normal | Problem sign, and what to do |
| --- | --- | --- |
| `apps` | `RUNNING` stays flat, `COMPLETED` increases. `NEW`, `SUBMITTED` and `SUCCEEDING` stay small | `NEW` or `SUCCEEDING` increases: the operator is behind (see below). `SUBMITTED` increases with Pending drivers: no free pod slots. Stop Locust or lower the rate |
| `submit_lag_s_p50_p99_max` | p99 below about 10 s | Increases: the operator submits late |
| `runtime_min_p50_p90_max` | Constant during the run | p50 increases: a shared resource limits the apps, usually S3 (section 4.4). The value is from creation to end, so an operator backlog also increases it |
| `new_failures` | Not present | Read the driver log of the failed application (see the table below) |
| `submitter` | `failure_count` does not increase | `SUBMITTER_OVERLOADED` (503): all slots are in use. Add replicas or slots |
| `operator` | `depth{sparkapplication}` near 0 | The depth increases: the controller cannot keep up |

The operator queue depth does not show items that wait in the work queue rate limiter. If `NEW`
and `SUCCEEDING` increase while the depth is 0 and the workers are idle, compare
`workqueue_retries_total` (calls to the rate limiter) with the rate limiter QPS. Each Spark pod
event causes one call. Section 6.2 shows this problem.

```bash
kubectl -n spark-team-a get sparkapplications | grep -v COMPLETED
kubectl -n spark-team-a logs <app>-driver | grep -E 'Exception|Caused by|Status Code' | head
```

| Message | Cause |
| --- | --- |
| `Status Code: 503`, "Please reduce your request rate" in the driver log | S3 throttling. See section 4.4 |
| `bucket is null/empty` in the driver log | `--results-bucket` was empty |
| `SUBMITTER_OVERLOADED` in the application status | All submitter slots were in use |

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

### 4.5 Prometheus

Prometheus runs as 1 replica on a core node (CPU request 16, memory limit 96 GiB). Per-node and
per-pod series grow with the cluster, so the configuration limits them:

| Rule | Reason |
| --- | --- |
| No series from the Spark namespaces (cAdvisor and kube-state-metrics) | Per-pod series of the load generator: 11.6 million head series at 100 nodes |
| No series for the host side of pod interfaces (`eni*`, `veth*`) in node-exporter and cAdvisor | One set of series for each pod interface: about 12 million series at 746 nodes |
| Only 1 of every 20 `tpcds-static` nodes has full kubelet, cAdvisor, node-exporter and kube-proxy series (scrape class `sample-static-nodes`, `hashmod` on the node name) | All series from all static nodes need about 180 GB of memory at 10,000 nodes |
| The other static nodes have about 20 health series each, every 2 minutes (jobs `kubelet-static-light`, `node-exporter-static-light`, `kube-proxy-static-light`) | Each node still shows its health: running pods, pod start latency, PLEG, free disk, load, memory, ENA allowance counters, kube-proxy sync time |
| cAdvisor every 30 seconds (chart default 10 seconds) | cAdvisor was 77% of the parse work for each node |

To query all static nodes, include both jobs, for example
`job=~"kubelet|kubelet-static-light"`. Totals from the full jobs are for the sample only. For the
2-minute jobs, use a `rate()` window of 5 minutes or more.

| Signal | Value at 746 nodes (before these rules) | Estimate at 10,000 nodes (with these rules) |
| --- | --- | --- |
| Head series | 22.8 million (peak) | about 5 million |
| Memory | 58.7 GB (peak) | about 16 GB |
| CPU | 4.65 cores (peak) | about 6 to 8 cores |

## 5. Logs and results

| Item | Location |
| --- | --- |
| Query results | `s3://$B/cNN/tpcds-results/<app name>/` |
| Spark pod logs | `s3://$B/spark-on-eks/spark-application-logs/<shard>/<namespace>/<pod>/` |
| Kubernetes events | ClickHouse event store (namespace `logging`), table `k8s_events.events` |
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
| Node disk | about 2 GiB for each application at peak |

At this size, the control plane had no errors and low latency. The load was about 3% of the pod
scheduling rate of the control plane tier (400 pods/s for 8XL).

### 6.2 EKS at 746 nodes, 65 apps/min

The NodePool asked for 1,000 nodes, but only 746 launched, because the gp3 storage quota was
full. All 746 nodes were r6g.4xlarge (15 pod slots each, about 11,900 vCPU). The run lasted 50
minutes: 2,581 applications, at most 455 concurrent applications and 10,812 running executors
(97% of the pod slots). Values are averages over the run, unless the table gives a peak.

| Area | Result |
| --- | --- |
| API requests | 1,204 req/s average, 3,663 req/s peak, 6 API server instances |
| Mutating requests | 803/s average, 2,695/s peak |
| Writes by resource | events 203 POST/s and 46 PATCH/s, pods/status 178/s, sparkapplications/status 80/s, leases 80/s, serviceaccounts/token 58/s, pods 28 POST/s and 28 DELETE/s |
| Reads | GET 327/s, LIST 13/s, WATCH 59/s. At most 16,885 open watches |
| Errors | 0 responses with code 429, 0 with code 500, one 504. API Priority and Fairness: 0 rejected, at most 1 in queue |
| APF seats in use (peak) | system 86, workload-low 44, workload-high 22, global-default 11 |
| API latency (p99, worst 5 minutes) | mutating 40 ms, GET 20 ms, LIST 0.89 s. LIST of events reached 29.8 s (client not known) |
| Pods | 28 creates/s and 28 bindings/s average, 159 creates/s and 115 bindings/s peak. 83,400 pods created |
| CoreDNS | 649 req/s, p99 31 ms or less, 0 SERVFAIL |
| Load generator | 2,569 applications completed, 12 failed. 1 failure was `SUBMITTER_OVERLOADED`. The other 11 were not caused by the load. Runtime from submission to end: p50 5.2 min, p90 5.8 min |

The control plane had no throttling and low latency at about 4 times the load of section 6.1.
These problems were outside the control plane:

- **Spark Operator rate limiter.** Each Spark pod event makes the operator add its application to
  the work queue through the rate limiter. With about 8,000 running pods, there were 118 calls/s.
  The limit was 100 QPS, so the delay before each reconcile grew by about 0.18 s every second.
  After 25 minutes, 160 applications waited in `NEW`, 145 in `SUCCEEDING`, and the submit lag p99
  was 143 s. The operator did only 5.8 reconciles/s, and its 100 workers were idle. The queue
  depth stayed 0. With the limit at 1,000 QPS (bucket 10,000), the backlog was gone in 2 minutes.
  When the operator released the backlog, the submitter rejected 1 application
  (`SUBMITTER_OVERLOADED`).
- **Rate too high.** At 65 apps/min the cluster used 97% of the pod slots, and about 2,000
  executors waited. On r6g.4xlarge, the capacity is about 69 apps/min at 100%. Use about 55
  apps/min (section 3.2).
- **gp3 quota.** Karpenter could not launch 254 nodes (`VolumeLimitExceeded`). It tried again and
  again: about 2,000 failed launches in 30 minutes. EC2 then throttled the account
  (`RequestLimitExceeded` on `CreateFleet`, `CreateTags` and `DescribeSubnets`). To stop this, set
  `replicas` to the number of Ready nodes.
- **Prometheus.** Head series reached 22.8 million and memory 58.7 GB (limit 96 GiB). Most series
  came from the host side of pod interfaces. Section 4.5 gives the rules that are now in place.
- **Event store.** Karpenter consolidation moved the ClickHouse pod twice. Each move stopped the
  event ingest for about 1 minute (EBS detach and attach). The NodePool of the event store now
  uses `consolidationPolicy: WhenEmpty` and on-demand capacity only.

### 6.3 Projection for 10,000 nodes (not tested)

These values assume that the load grows linearly with the number of concurrent applications.

**Pod scheduling limits the rate.** With 1 iteration (3.5 minutes on r8g.8xlarge), 10,000
r8g.8xlarge nodes need about 2,700 apps/min, which is about 1,400 pod creates/s. The 8XL tier
schedules about 400 pods/s. At 400 pods/s, the maximum rate is about 770 apps/min. To fill
10,000 nodes at that rate, each application must run at least about 13 minutes. Use more
iterations (`--tpcds-iterations`), and measure the runtime first. On smaller instance types,
fewer applications fill the same node count.

**API load.** Requests for each concurrent application:

| Run | Concurrent applications | API req/s | req/s for each application |
| --- | --- | --- | --- |
| 100 nodes | about 84 | about 590 | about 7 |
| 746 nodes | about 300 to 455 | about 1,200 | about 2.6 to 4 |

The node leases add 1 write every 10 seconds for each node (1,000/s at 10,000 nodes). A longer
runtime lowers the creates and the events for each second, but not the status writes for running
applications.

**Operator.** The operator rate limiter gets about 1 call for each pod event. At 10,000 nodes,
calculate the pod event rate and keep it below the rate limiter QPS (now 1,000).

**S3.** With about 12 GET/s for each running application, and 10,000 running applications:

| | Total GET/s | GET/s for each of 50 prefixes | Share of 5,500 GET/s per prefix |
| --- | --- | --- | --- |
| Average | about 124,000 | about 2,500 | about 45% |
| All applications in their busiest phase | about 230,000 | about 4,600 | about 84% |

S3 gives 5,500 GET/s for each prefix only after it has partitioned the bucket. A new or lightly
used bucket throttles at a much lower rate. Ask for pre-partitioning before the
run, and increase the rate in steps.

**Prometheus.** See section 4.5.

## 7. Known items

- Static nodes do not follow the pod zone. The zone is set in
  `terraform/manifests/karpenter/nodepool-tpcds-static.yaml`. The Locust `--zone-id` value must
  be the same zone ID.
- The static NodePool needs the Karpenter feature gate `StaticCapacity=true`.
- Karpenter selects the lowest-price instance type for the static nodes. To get the same
  capacity in each run, limit the instance types in the NodePool.
