"""
Locust load test — EKS PCP benchmark with EMR on EKS (TPC-DS)
==============================================================
Based on: https://github.com/aws-samples/load-test-for-emr-on-eks

Ramps up concurrent TPC-DS Spark jobs via the emr-containers API and
measures whether the EKS 4XL control plane limits are approached.

  Metric                          4XL limit   auto-stop (90 %)
  ─────────────────────────────────────────────────────────────
  API concurrency seats           6800         6120
  Pod scheduling rate (pods/sec)   400          360
  etcd DB size (GB)                  16          14.4

Benchmark JAR (baked into the Docker image):
  local:///usr/lib/spark/examples/jars/eks-spark-benchmark-assembly-1.0.jar
  Main class: com.amazonaws.eks.tpcds.BenchmarkSQL
  tpcds-kit : /opt/tpcds-kit/tools

BenchmarkSQL argument order:
  1. tpcdsDataDir    – S3 path to pre-generated 1TB Parquet TPC-DS data
  2. resultLocation  – unique S3 output path per job run
  3. dsdgenDir       – /opt/tpcds-kit/tools (inside container)
  4. format          – parquet
  5. scaleFactor     – 1000 (= 1 TB)
  6. iterations      – 1
  7. optimizeQueries – false
  8. filterQueries   – comma-separated TPC-DS query IDs (empty = all 99)
  9. onlyWarn        – false

Usage:
  pip install locust boto3 requests

  export EMR_VIRTUAL_CLUSTER_ID=<id>
  export EMR_EXECUTION_ROLE_ARN=arn:aws:iam::...:role/...
  export OUTPUT_BUCKET=s3://<benchmark-bucket>
  export SCRIPTS_S3_PATH=s3://<benchmark-bucket>/pcp-benchmarks/scripts
  export AWS_REGION=<region>
  export EMR_RELEASE_LABEL=<release-label>
  export TPCDS_INPUT=<input-dataset-s3-path>
  export TPCDS_QUERIES=<comma-separated-query-list>
  export PROMETHEUS_URL=http://localhost:9090   # after: kubectl port-forward svc/prometheus 9090
  export CW_LOG_GROUP=<cloudwatch-log-group>

  # Ramp to 50 concurrent jobs at 2 users/sec, run 30 min, write CSV:
  locust -f locustfile.py --headless -u 50 -r 2 --run-time 30m \\
         --csv=results/pcp-4xl-$(date +%Y%m%d-%H%M)

  # Or open the Locust web UI against gamma:
  locust -f locustfile.py --host https://emr-containers-gamma.<aws-region>.amazonaws.com
"""

from __future__ import annotations

import os
import time
import uuid
import logging
import threading
from pathlib import Path

import boto3
import gevent
from botocore.config import Config
from locust import HttpUser, task, events, between
from locust.env import Environment

log = logging.getLogger("pcp-benchmark")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")


def _require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Required environment variable is not set: {name}")
    return value

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
AWS_REGION          = _require_env("AWS_REGION")
EMR_ENDPOINT_URL    = f"https://emr-containers-gamma.{AWS_REGION}.amazonaws.com"
VIRTUAL_CLUSTER_ID  = _require_env("EMR_VIRTUAL_CLUSTER_ID")
EXECUTION_ROLE_ARN  = _require_env("EMR_EXECUTION_ROLE_ARN")
EMR_RELEASE_LABEL   = _require_env("EMR_RELEASE_LABEL")
ECR_IMAGE           = _require_env("ECR_IMAGE")
TPCDS_INPUT         = _require_env("TPCDS_INPUT")
OUTPUT_BUCKET       = _require_env("OUTPUT_BUCKET")
SCRIPTS_S3_PATH     = _require_env("SCRIPTS_S3_PATH")
CW_LOG_GROUP        = _require_env("CW_LOG_GROUP")
PROMETHEUS_URL      = os.environ.get("PROMETHEUS_URL", "")

# Short query subset — keeps each job ~5-10 min so we can measure throughput.
# Increase to full 99 queries if you want to measure steady-state saturation.
TPCDS_QUERIES       = _require_env("TPCDS_QUERIES")

# PCP 4XL limits and 90 % auto-stop thresholds
PCP_LIMITS = {
    "api_seats":      {"limit": 6800, "threshold": 6120},
    "pod_sched_rate": {"limit": 400,  "threshold": 360},
    "etcd_db_gb":     {"limit": 16,   "threshold": 14.4},
}

POLL_INTERVAL_S = 30   # job-state poll cadence
METRIC_POLL_S   = 15   # PCP metric scrape cadence
ITERATIONS      = _require_env("TPCDS_ITERATIONS")
SCALE_FACTOR    = _require_env("TPCDS_SCALE_FACTOR")
EXECUTOR_INSTANCES = _require_env("SPARK_EXECUTOR_INSTANCES")
EXECUTOR_CORES     = _require_env("SPARK_EXECUTOR_CORES")
EXECUTOR_MEMORY    = _require_env("SPARK_EXECUTOR_MEMORY")
DRIVER_CORES       = _require_env("SPARK_DRIVER_CORES")
DRIVER_MEMORY      = _require_env("SPARK_DRIVER_MEMORY")
EXECUTOR_LIMIT_CORES = _require_env("SPARK_EXECUTOR_LIMIT_CORES")
DRIVER_LIMIT_CORES   = _require_env("SPARK_DRIVER_LIMIT_CORES")
ONLY_WARN         = _require_env("TPCDS_ONLY_WARN")
EMR_MAX_POOL_CONNECTIONS = int(_require_env("EMR_MAX_POOL_CONNECTIONS"))
WAIT_MIN_S         = float(_require_env("LOCUST_WAIT_MIN_S"))
WAIT_MAX_S         = float(_require_env("LOCUST_WAIT_MAX_S"))
MAX_JOBS_TO_SUBMIT = int(_require_env("MAX_JOBS_TO_SUBMIT"))
JOB_NAME_PREFIX    = _require_env("BENCHMARK_JOB_NAME_PREFIX")
SUBMITTED_JOBS_FILE = os.environ.get("BENCHMARK_SUBMITTED_JOBS_FILE", "")
ACTIVE_JOBS_FILE    = os.environ.get("BENCHMARK_ACTIVE_JOBS_FILE", "")

# ---------------------------------------------------------------------------
# Shared state
# ---------------------------------------------------------------------------
_emr_client = boto3.client(
    "emr-containers",
    region_name=AWS_REGION,
    endpoint_url=EMR_ENDPOINT_URL,
    config=Config(max_pool_connections=EMR_MAX_POOL_CONNECTIONS),
)
_stop_event = threading.Event()
_lock       = threading.Lock()
_submitted  = 0
_completed  = 0
_failed_cnt = 0
_active_job_ids: set[str] = set()


def _ensure_parent(path_str: str) -> None:
    if path_str:
        Path(path_str).parent.mkdir(parents=True, exist_ok=True)


def _write_lines(path_str: str, values: list[str]) -> None:
    if not path_str:
        return
    _ensure_parent(path_str)
    payload = "\n".join(values)
    if payload:
        payload += "\n"
    Path(path_str).write_text(payload)


def _append_line(path_str: str, value: str) -> None:
    if not path_str:
        return
    _ensure_parent(path_str)
    with Path(path_str).open("a", encoding="utf-8") as handle:
        handle.write(f"{value}\n")


def _inc(attr: str) -> None:
    global _submitted, _completed, _failed_cnt
    with _lock:
        if attr == "submitted":  _submitted  += 1
        elif attr == "completed": _completed += 1
        elif attr == "failed":   _failed_cnt += 1


def _track_active_job(job_id: str) -> None:
    with _lock:
        _active_job_ids.add(job_id)
        _write_lines(ACTIVE_JOBS_FILE, sorted(_active_job_ids))


def _untrack_active_job(job_id: str) -> None:
    with _lock:
        _active_job_ids.discard(job_id)
        _write_lines(ACTIVE_JOBS_FILE, sorted(_active_job_ids))


def _record_submitted_job(job_name: str, job_id: str) -> None:
    _append_line(SUBMITTED_JOBS_FILE, f"{job_id}\t{job_name}")
    _track_active_job(job_id)


def _submission_cap_reached() -> bool:
    return MAX_JOBS_TO_SUBMIT > 0 and _submitted >= MAX_JOBS_TO_SUBMIT


def _should_exit_after_cap() -> bool:
    with _lock:
        return _submission_cap_reached() and not _active_job_ids


# ---------------------------------------------------------------------------
# PCP metric helpers
# ---------------------------------------------------------------------------

def _query_prometheus(metric: str) -> float | None:
    if not PROMETHEUS_URL:
        return None
    try:
        import requests
        resp = requests.get(
            f"{PROMETHEUS_URL}/api/v1/query",
            params={"query": metric},
            timeout=10,
        )
        result = resp.json().get("data", {}).get("result", [])
        if result:
            return float(result[0]["value"][1])
    except Exception as exc:
        log.debug("Prometheus query failed (%s): %s", metric, exc)
    return None


def _pcp_watcher(runner) -> None:
    """Background greenlet: scrape PCP metrics and stop the test if thresholds are hit."""
    log.info("PCP metric watcher started (interval=%ss)", METRIC_POLL_S)
    while not _stop_event.is_set():
        gevent.sleep(METRIC_POLL_S)

        seats = _query_prometheus("apiserver_flowcontrol_current_executing_seats")
        if seats is not None:
            pct = seats / PCP_LIMITS["api_seats"]["limit"] * 100
            log.info("[PCP] API seats: %.0f / %d  (%.1f%%)",
                     seats, PCP_LIMITS["api_seats"]["limit"], pct)
            if seats >= PCP_LIMITS["api_seats"]["threshold"]:
                log.warning("[PCP] API seats ≥ 90%% threshold — stopping test")
                _stop_event.set()
                runner.quit()
                return

        sched_rate = _query_prometheus(
            "rate(scheduler_schedule_attempts_total{result='scheduled'}[1m])"
        )
        if sched_rate is not None:
            pct = sched_rate / PCP_LIMITS["pod_sched_rate"]["limit"] * 100
            log.info("[PCP] Pod sched rate: %.1f pods/s  (%.1f%%)", sched_rate, pct)
            if sched_rate >= PCP_LIMITS["pod_sched_rate"]["threshold"]:
                log.warning("[PCP] Pod scheduling rate ≥ 90%% threshold — stopping test")
                _stop_event.set()
                runner.quit()
                return

        etcd_bytes = _query_prometheus("apiserver_storage_size_bytes")
        if etcd_bytes is not None:
            etcd_gb = etcd_bytes / 1e9
            pct     = etcd_gb / PCP_LIMITS["etcd_db_gb"]["limit"] * 100
            log.info("[PCP] etcd DB: %.2f GB  (%.1f%%)", etcd_gb, pct)
            if etcd_gb >= PCP_LIMITS["etcd_db_gb"]["threshold"]:
                log.warning("[PCP] etcd DB ≥ 90%% threshold — stopping test")
                _stop_event.set()
                runner.quit()
                return

        with _lock:
            log.info("[Stats] submitted=%d  completed=%d  failed=%d",
                     _submitted, _completed, _failed_cnt)


# ---------------------------------------------------------------------------
# Locust event hooks
# ---------------------------------------------------------------------------

@events.test_start.add_listener
def on_test_start(environment: Environment, **kwargs) -> None:
    log.info("EKS PCP benchmark starting — cluster: %s  queries: %s",
             VIRTUAL_CLUSTER_ID, TPCDS_QUERIES)
    gevent.spawn(_pcp_watcher, environment.runner)


@events.test_stop.add_listener
def on_test_stop(environment: Environment, **kwargs) -> None:
    _stop_event.set()
    with _lock:
        log.info("Test stopped — submitted=%d  completed=%d  failed=%d",
                 _submitted, _completed, _failed_cnt)
        _write_lines(ACTIVE_JOBS_FILE, sorted(_active_job_ids))


# ---------------------------------------------------------------------------
# EMR job helpers
# ---------------------------------------------------------------------------

def _submit_job(job_name: str, output_path: str) -> str:
    """Submit one TPC-DS EMR job; return the job run ID."""
    resp = _emr_client.start_job_run(
        virtualClusterId=VIRTUAL_CLUSTER_ID,
        name=job_name,
        executionRoleArn=EXECUTION_ROLE_ARN,
        releaseLabel=EMR_RELEASE_LABEL,
        jobDriver={
            "sparkSubmitJobDriver": {
                # JAR is baked into the image at build time
                "entryPoint": "local:///usr/lib/spark/examples/jars/eks-spark-benchmark-assembly-1.0.jar",
                # BenchmarkSQL args (positional):
                "entryPointArguments": [
                    TPCDS_INPUT,          # 1. tpcdsDataDir
                    output_path,          # 2. resultLocation
                    "/opt/tpcds-kit/tools",  # 3. dsdgenDir
                    "parquet",            # 4. format
                    SCALE_FACTOR,        # 5. scaleFactor
                    ITERATIONS,          # 6. iterations
                    "false",             # 7. optimizeQueries
                    TPCDS_QUERIES,       # 8. filterQueries
                    ONLY_WARN,           # 9. onlyWarn
                ],
                "sparkSubmitParameters": (
                    "--class com.amazonaws.eks.tpcds.BenchmarkSQL"
                    f" --conf spark.driver.cores={DRIVER_CORES}"
                    f" --conf spark.driver.memory={DRIVER_MEMORY}"
                    f" --conf spark.executor.cores={EXECUTOR_CORES}"
                    f" --conf spark.executor.memory={EXECUTOR_MEMORY}"
                    f" --conf spark.executor.instances={EXECUTOR_INSTANCES}"
                ),
            }
        },
        configurationOverrides={
            "applicationConfiguration": [
                {
                    "classification": "spark-defaults",
                    "properties": {
                        "spark.kubernetes.container.image.pullPolicy": "IfNotPresent",
                        "spark.kubernetes.container.image": ECR_IMAGE,

                        "spark.kubernetes.driver.podTemplateFile":
                            f"{SCRIPTS_S3_PATH}/driver-pod-template.yaml",
                        "spark.kubernetes.executor.podTemplateFile":
                            f"{SCRIPTS_S3_PATH}/executor-pod-template.yaml",

                        "spark.local.dir": "/var/data/spark-local",

                        "spark.sql.adaptive.enabled":                    "true",
                        "spark.sql.adaptive.coalescePartitions.enabled": "true",
                        "spark.sql.adaptive.skewJoin.enabled":           "true",

                        "spark.kubernetes.executor.limit.cores": EXECUTOR_LIMIT_CORES,
                        "spark.kubernetes.driver.limit.cores":   DRIVER_LIMIT_CORES,
                        "spark.driver.memoryOverhead":           "2G",
                        "spark.executor.memoryOverhead":         "2G",
                        "spark.network.timeout":                 "3600s",
                        "spark.executor.heartbeatInterval":      "1800s",
                        "spark.shuffle.io.retryWait":            "60s",
                        "spark.shuffle.io.maxRetries":           "5",
                        "spark.hadoop.fs.s3.maxConnections":     "200",
                        "spark.hadoop.fs.s3.maxRetries":         "30",
                        "spark.scheduler.minRegisteredResourcesRatio":      "0.6",
                        "spark.scheduler.maxRegisteredResourcesWaitingTime": "1800s",

                        "spark.kubernetes.executor.podNamePrefix":            job_name,
                        "spark.kubernetes.node.selector.NodeGroupType":       "EMRPCPBenchmark",
                        "spark.kubernetes.node.selector.emr-eks-benchmarks":  "true",

                        "spark.ui.prometheus.enabled":                              "true",
                        "spark.executor.processTreeMetrics.enabled":               "true",
                        "spark.kubernetes.driver.annotation.prometheus.io/scrape": "true",
                        "spark.kubernetes.driver.annotation.prometheus.io/path":   "/metrics/executors/prometheus/",
                        "spark.kubernetes.driver.annotation.prometheus.io/port":   "4040",

                        "spark.executor.defaultJavaOptions":
                            "-verbose:gc -XX:+UseParallelGC -XX:InitiatingHeapOccupancyPercent=70",
                    },
                }
                ,
                {
                    "classification": "emr-containers-defaults",
                    "properties": {
                        "job-start-timeout": "4800",
                        "executor.logging": "DISABLED",
                    },
                }
            ],
            "monitoringConfiguration": {
                "persistentAppUI": "ENABLED",
                "cloudWatchMonitoringConfiguration": {
                    "logGroupName":        CW_LOG_GROUP,
                    "logStreamNamePrefix": job_name,
                },
                "s3MonitoringConfiguration": {
                    "logUri": f"{OUTPUT_BUCKET}/pcp-benchmarks/logs/",
                },
            },
        },
    )
    return resp["id"]


def _poll_job(job_id: str, timeout_s: int = 7200) -> str:
    """Poll until terminal state; return final state string."""
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        state = _emr_client.describe_job_run(
            virtualClusterId=VIRTUAL_CLUSTER_ID,
            id=job_id,
        )["jobRun"]["state"]
        if state in ("COMPLETED", "FAILED", "CANCELLED", "CANCEL_PENDING"):
            return state
        gevent.sleep(POLL_INTERVAL_S)
    return "TIMEOUT"


# ---------------------------------------------------------------------------
# Locust User
# ---------------------------------------------------------------------------

class SparkJobUser(HttpUser):
    """
    Each virtual user submits one TPC-DS Spark job and waits for it to finish,
    then immediately submits the next one (after the wait_time delay).

    The Locust HTTP client is not used — all calls go to the EMR API via boto3.
    We use environment.events.request.fire() so Locust records the timings.
    """

    host = EMR_ENDPOINT_URL
    wait_time = between(WAIT_MIN_S, WAIT_MAX_S)

    @task
    def submit_and_poll_job(self) -> None:
        if _stop_event.is_set():
            self.environment.runner.stop()
            return

        if _submission_cap_reached():
            if _should_exit_after_cap():
                self.environment.runner.quit()
            gevent.sleep(1)
            return

        job_name    = f"{JOB_NAME_PREFIX}-{uuid.uuid4().hex[:10]}"
        output_path = f"{OUTPUT_BUCKET}/pcp-benchmarks/output/{job_name}"

        # ── Submit ──────────────────────────────────────────────────────────
        t0 = time.time()
        try:
            job_id = _submit_job(job_name, output_path)
            _inc("submitted")
            _record_submitted_job(job_name, job_id)
            self.environment.events.request.fire(
                request_type="EMR", name="start_job_run",
                response_time=int((time.time() - t0) * 1000),
                response_length=0, exception=None,
            )
            log.info("[submit] %s → %s", job_name, job_id)
        except Exception as exc:
            _inc("failed")
            self.environment.events.request.fire(
                request_type="EMR", name="start_job_run",
                response_time=int((time.time() - t0) * 1000),
                response_length=0, exception=exc,
            )
            log.error("[submit] FAILED %s: %s", job_name, exc)
            return

        # ── Poll ────────────────────────────────────────────────────────────
        t1    = time.time()
        state = _poll_job(job_id)
        elapsed_ms = int((time.time() - t1) * 1000)

        if state == "COMPLETED":
            _inc("completed")
        else:
            _inc("failed")
        _untrack_active_job(job_id)

        self.environment.events.request.fire(
            request_type="EMR", name="job_run_duration",
            response_time=elapsed_ms, response_length=0,
            exception=None if state == "COMPLETED" else Exception(f"state={state}"),
        )
        log.info("[poll] %s → %s  (%.0f s)", job_name, state, elapsed_ms / 1000)
