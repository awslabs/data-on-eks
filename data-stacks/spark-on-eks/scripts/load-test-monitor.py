# /// script
# requires-python = ">=3.9"
# dependencies = ["kubernetes==29.0.0"]
# ///
"""Load test monitor. Reads the cluster and Prometheus and appends one JSON line per sample.

Usage: uv run load-test-monitor.py <output.jsonl> [<start time, ISO 8601>]
"""
import collections
import json
import re
import sys
import time
from datetime import datetime, timezone

from k8s_api import ACCEPT_METADATA, FROM_CACHE, get

NAMESPACES = ["spark-team-a"]
APP_PREFIX = "tpcds-"
INTERVAL = 15
FINAL = {"COMPLETED", "FAILED", "SUBMISSION_FAILED"}
OUT = sys.argv[1] if len(sys.argv) > 1 else "monitor.jsonl"
# Apps created before this time are not part of the run.
START = datetime.now(timezone.utc) if len(sys.argv) < 3 else datetime.fromisoformat(sys.argv[2])


def ts(s):
    return datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc) if s else None


def pct(values, p):
    if not values:
        return None
    v = sorted(values)
    return round(v[min(len(v) - 1, int(p / 100 * len(v)))], 1)


def metric_lines(text, names):
    out = collections.defaultdict(float)
    for line in text.splitlines():
        if line.startswith("#"):
            continue
        m = re.match(r"^([a-zA-Z_:][a-zA-Z0-9_:]*)(\{[^}]*\})?\s+(\S+)$", line)
        if m and m.group(1) in names:
            out[m.group(1) + (m.group(2) or "")] += float(m.group(3))
    return out


def pod_metrics(namespace, selector, port, names):
    total = collections.defaultdict(float)
    pods = get(f"/api/v1/namespaces/{namespace}/pods", {"labelSelector": selector})["items"]
    for p in pods:
        if p["status"].get("phase") != "Running":
            continue
        try:
            text = get(f"/api/v1/namespaces/{namespace}/pods/{p['metadata']['name']}:{port}/proxy/metrics", raw=True)
        except Exception:
            continue
        for k, v in metric_lines(text, names).items():
            total[k] += v
    return total


# The app TTL deletes final apps, so the run totals are kept here. name -> (state, runtime_min)
final_apps = {}
submit_lag = {}
PROM_QUERY = "/api/v1/namespaces/monitoring/services/prometheus-prometheus:9090/proxy/api/v1/query"
EKS_QUERIES = {
    "api_req_s": 'sum(rate(apiserver_request_total[1m]))',
    "api_429_s": 'sum(rate(apiserver_request_total{code="429"}[1m])) or vector(0)',
    "api_5xx_s": 'sum(rate(apiserver_request_total{code=~"5.."}[1m])) or vector(0)',
    "api_p99_mutating_s": 'histogram_quantile(0.99, sum by (le)(rate(apiserver_request_duration_seconds_bucket{verb=~"POST|PUT|PATCH|DELETE"}[5m])))',
    "api_p99_list_s": 'histogram_quantile(0.99, sum by (le)(rate(apiserver_request_duration_seconds_bucket{verb="LIST"}[5m])))',
    "apf_inqueue": 'sum(apiserver_flowcontrol_current_inqueue_requests)',
    "apf_rejected_s": 'sum(rate(apiserver_flowcontrol_rejected_requests_total[1m])) or vector(0)',
    # Binding POSTs are the scheduler's placements, so this is the scheduling throughput.
    "pod_create_s": 'sum(rate(apiserver_request_total{resource="pods",subresource="",verb="POST"}[1m]))',
    "pod_bind_s": 'sum(rate(apiserver_request_total{resource="pods",subresource="binding",verb="POST"}[1m]))',
    "etcd_mb": 'max(apiserver_storage_size_bytes) / 1e6',
    "coredns_p99_s": 'histogram_quantile(0.99, sum by (le)(rate(coredns_dns_request_duration_seconds_bucket[5m])))',
}


def eks_signals():
    out = {}
    for name, q in EKS_QUERIES.items():
        try:
            res = get(PROM_QUERY, {"query": q})["data"]["result"]
            out[name] = round(float(res[0]["value"][1]), 3) if res else None
        except Exception:
            out[name] = "error"
    return out


while True:
    now = datetime.now(timezone.utc)
    sample = {"t": now.strftime("%H:%M:%S")}
    sample["eks"] = eks_signals()
    try:
        apps = []
        for ns in NAMESPACES:
            apps += get(f"/apis/sparkoperator.k8s.io/v1beta2/namespaces/{ns}/sparkapplications", FROM_CACHE)["items"]
        apps = [a for a in apps if a["metadata"]["name"].startswith(APP_PREFIX)
                and ts(a["metadata"]["creationTimestamp"]) >= START]
        states = collections.Counter()
        for a in apps:
            name = a["metadata"]["name"]
            st = a.get("status", {})
            state = st.get("applicationState", {}).get("state") or "NEW"
            created = ts(a["metadata"]["creationTimestamp"])
            sub = ts(st.get("lastSubmissionAttemptTime"))
            if sub and name not in submit_lag:
                submit_lag[name] = (sub - created).total_seconds()
            if state not in FINAL:
                states[state] += 1
                continue
            if name in final_apps:
                continue
            end = ts(st.get("terminationTime"))
            runtime = (end - created).total_seconds() / 60 if end and state == "COMPLETED" else None
            final_apps[name] = (state, runtime)
            if state != "COMPLETED":
                sample.setdefault("new_failures", []).append(
                    {name: (state, st.get("applicationState", {}).get("errorMessage", "")[:300])})
        states.update(state for state, _ in final_apps.values())
        lags = list(submit_lag.values())
        runtimes = [r for _, r in final_apps.values() if r is not None]
        sample["apps"] = dict(states)
        sample["apps_total"] = sum(states.values())
        sample["submit_lag_s_p50_p99_max"] = [pct(lags, 50), pct(lags, 99), max(lags) if lags else None]
        sample["runtime_min_p50_p90_max"] = [pct(runtimes, 50), pct(runtimes, 90), round(max(runtimes), 1) if runtimes else None]

        pod_states = collections.Counter()
        pending = []
        for ns in NAMESPACES:
            path = f"/api/v1/namespaces/{ns}/pods"
            pending += get(path, {**FROM_CACHE, "fieldSelector": "status.phase=Pending"})["items"]
            for phase in ("Running", "Succeeded", "Failed"):
                # A metadata-only list returns "items": null when it is empty.
                for p in get(path, {**FROM_CACHE, "fieldSelector": f"status.phase={phase}"}, accept=ACCEPT_METADATA)["items"] or []:
                    pod_states[(p["metadata"].get("labels", {}).get("spark-role", "?"), phase)] += 1
        for p in pending:
            pod_states[(p["metadata"].get("labels", {}).get("spark-role", "?"), "Pending")] += 1
        sample["pods"] = {f"{r}/{ph}": n for (r, ph), n in sorted(pod_states.items())}
        pending_age = [(now - ts(p["metadata"]["creationTimestamp"])).total_seconds() for p in pending]
        sample["pending_oldest_s"] = round(max(pending_age)) if pending_age else 0
        unsched = collections.Counter()
        for p in pending:
            for c in p["status"].get("conditions", []):
                if c["type"] == "PodScheduled" and c["status"] == "False":
                    unsched[c.get("reason", "")] += 1
        if unsched:
            sample["unschedulable"] = dict(unsched)

        # NodeClaims, because Node objects are large (image lists) at 1,000 nodes.
        claims = get("/apis/karpenter.sh/v1/nodeclaims",
                     {**FROM_CACHE, "labelSelector": "karpenter.sh/nodepool=tpcds-static"})["items"]
        ready = [c for c in claims
                 if any(k["type"] == "Ready" and k["status"] == "True" for k in c.get("status", {}).get("conditions", []))]
        sample["static_nodes_ready"] = len(ready)
        # The pool mixes instance sizes, so the app capacity follows the vCPU total, not the node count.
        sample["static_vcpu_ready"] = sum(int(c["status"]["capacity"]["cpu"]) for c in ready)

        sm = pod_metrics("spark-submitter", "app.kubernetes.io/name=spark-submitter", 8081, {
            "spark_submit_requests_in_flight", "spark_submit_request_success_count",
            "spark_submit_request_failure_count", "spark_submit_request_latency_seconds_sum",
            "spark_submit_request_latency_seconds_count"})
        lat_n = sm.pop("spark_submit_request_latency_seconds_count", 0)
        lat_s = sm.pop("spark_submit_request_latency_seconds_sum", 0)
        sample["submitter"] = {k.replace("spark_submit_request", ""): int(v) for k, v in sm.items()}
        sample["submitter"]["latency_avg_s"] = round(lat_s / lat_n, 2) if lat_n else None

        om = pod_metrics("spark-operator", "app.kubernetes.io/component=controller", 8080, {
            "workqueue_depth", "workqueue_longest_running_processor_seconds",
            "workqueue_queue_duration_seconds_sum", "workqueue_queue_duration_seconds_count",
            "spark_application_success_count", "spark_application_failure_count"})
        short = lambda k: re.sub(r"\{.*?name=\"([^\"]*)\".*\}", r"{\1}", re.sub(r"^(workqueue_|spark_application_)", "", k))
        sample["operator"] = {short(k): round(v, 2) for k, v in om.items() if "queue_duration" not in k}
        for name in {re.sub(r".*name=\"([^\"]*)\".*", r"\1", k) for k in om if "queue_duration_seconds_count" in k}:
            n = sum(v for k, v in om.items() if "queue_duration_seconds_count" in k and f'name="{name}"' in k)
            s = sum(v for k, v in om.items() if "queue_duration_seconds_sum" in k and f'name="{name}"' in k)
            sample["operator"][f"queue_wait_avg_s{{{name}}}"] = round(s / n, 3) if n else None
    except Exception as e:
        sample["error"] = repr(e)[:300]
    with open(OUT, "a") as f:
        f.write(json.dumps(sample) + "\n")
    time.sleep(INTERVAL)
