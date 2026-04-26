#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$STACK_DIR/terraform/_local"
STATE_DIR="$SCRIPT_DIR/.benchmark-state"
PID_FILE="$STATE_DIR/locust.pid"
ACTIVE_JOBS_FILE="$STATE_DIR/active-job-ids.txt"
SUBMITTED_JOBS_FILE="$STATE_DIR/submitted-job-ids.txt"
RUN_LOG_FILE="$STATE_DIR/locust.log"
RUN_ENV_FILE="$STATE_DIR/run.env"

ACTION="${1:-start}"
EMR_TEAM="${EMR_TEAM:-emr-data-team-a}"
CONFIG_FILE="${BENCHMARK_CONFIG_FILE:-$SCRIPT_DIR/benchmark.env}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: benchmark config file not found: $CONFIG_FILE" >&2
  echo "Create it from $SCRIPT_DIR/benchmark.env.example" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

# User-tunable benchmark knobs. Keep this list intentionally short.
# Number of concurrent Locust users participating in the submission run.
# Each user submits one job and then waits on that job, so sustained submission tests need enough users
# to cover the full run window. For 100 jobs/min over 30 minutes, use 3000 users.
LOCUST_USERS="${LOCUST_USERS:-3000}"
# Submission ramp expressed as users per second.
# `1.67` is roughly `100 jobs/min` for the initial step. Increase this for the `200` and `300 jobs/min` tests.
LOCUST_SPAWN_RATE="${LOCUST_SPAWN_RATE:-1.67}"
# Total time Locust keeps the test running.
# Keep this aligned with the current step design so the requested jobs/min target stays comparable across tiers.
# Use 30 minutes to include Karpenter provisioning lag and sustained control-plane pressure.
LOCUST_RUN_TIME="${LOCUST_RUN_TIME:-30m}"
# Hard cap on how many EMR jobs this benchmark will submit before it stops launching new work.
# For the first step this is `3000`, which is 100 jobs/min for 30 minutes.
MAX_JOBS_TO_SUBMIT="${MAX_JOBS_TO_SUBMIT:-3000}"
# Comma-separated TPC-DS query IDs to run in each submitted Spark job.
# Change this only when you want a different query mix, which can change job duration and cluster pressure.
TPCDS_QUERIES="${TPCDS_QUERIES:-q4-v2.4,q24a-v2.4,q24b-v2.4,q67-v2.4}"

# Opinionated benchmark defaults. Change only when the benchmark definition changes.
BENCHMARK_JOB_NAME_PREFIX="pcp"
LOCUST_WAIT_MIN_S="0"
LOCUST_WAIT_MAX_S="1"
TPCDS_ITERATIONS="1"
TPCDS_SCALE_FACTOR="1000"
TPCDS_ONLY_WARN="false"
SPARK_EXECUTOR_INSTANCES="30"
SPARK_EXECUTOR_CORES="2"
SPARK_EXECUTOR_MEMORY="5g"
SPARK_DRIVER_CORES="1"
SPARK_DRIVER_MEMORY="2g"
SPARK_EXECUTOR_LIMIT_CORES="2.1"
SPARK_DRIVER_LIMIT_CORES="1.1"
EMR_RELEASE_LABEL="emr-7.9.0-latest"
EMR_MAX_POOL_CONNECTIONS="200"
ECR_IMAGE="${ECR_IMAGE:-}"
TPCDS_INPUT="${TPCDS_INPUT:-}"
STOP_WAIT_SECONDS="30"
CANCEL_WAIT_SECONDS="120"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: missing required command: $1" >&2
    exit 1
  fi
}

require_value() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "ERROR: required benchmark config value is missing: $name" >&2
    echo "Check $CONFIG_FILE" >&2
    exit 1
  fi
}

is_terminal_state() {
  case "$1" in
    COMPLETED|FAILED|CANCEL_PENDING|CANCELLED) return 0 ;;
    *) return 1 ;;
  esac
}

process_running() {
  [[ -f "$PID_FILE" ]] || return 1
  local pid
  pid="$(cat "$PID_FILE")"
  kill -0 "$pid" >/dev/null 2>&1
}

load_runtime_context() {
  require_command aws
  require_command locust
  require_value "EMR_VIRTUAL_CLUSTER_ID" "${EMR_VIRTUAL_CLUSTER_ID:-}"
  require_value "EMR_EXECUTION_ROLE_ARN" "${EMR_EXECUTION_ROLE_ARN:-}"
  require_value "CLOUDWATCH_LOG_GROUP" "${CLOUDWATCH_LOG_GROUP:-}"
  require_value "S3_BUCKET" "${S3_BUCKET:-}"
  require_value "AWS_REGION" "${AWS_REGION:-}"
  require_value "ECR_IMAGE" "${ECR_IMAGE:-}"
  require_value "TPCDS_INPUT" "${TPCDS_INPUT:-}"
  EMR_ENDPOINT_URL="https://emr-containers-gamma.${AWS_REGION}.amazonaws.com"
  SCRIPTS_S3_PATH="${S3_BUCKET}/pcp-benchmarks/scripts"
}

write_run_env() {
  mkdir -p "$STATE_DIR"
  cat >"$RUN_ENV_FILE" <<EOF
EMR_VIRTUAL_CLUSTER_ID=$EMR_VIRTUAL_CLUSTER_ID
EMR_EXECUTION_ROLE_ARN=$EMR_EXECUTION_ROLE_ARN
CLOUDWATCH_LOG_GROUP=$CLOUDWATCH_LOG_GROUP
S3_BUCKET=$S3_BUCKET
AWS_REGION=$AWS_REGION
EMR_ENDPOINT_URL=$EMR_ENDPOINT_URL
SCRIPTS_S3_PATH=$SCRIPTS_S3_PATH
EOF
}

load_run_env() {
  if [[ -f "$RUN_ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$RUN_ENV_FILE"
  else
    load_runtime_context
    write_run_env
  fi
}

upload_pod_templates() {
  echo "Uploading pod templates to $SCRIPTS_S3_PATH ..."
  aws s3 cp "$SCRIPT_DIR/driver-pod-template.yaml" "${SCRIPTS_S3_PATH}/driver-pod-template.yaml"
  aws s3 cp "$SCRIPT_DIR/executor-pod-template.yaml" "${SCRIPTS_S3_PATH}/executor-pod-template.yaml"
}

start_benchmark() {
  if process_running; then
    echo "Benchmark already running with pid $(cat "$PID_FILE")." >&2
    exit 1
  fi

  load_runtime_context
  rm -rf "$STATE_DIR"
  mkdir -p "$STATE_DIR"
  : >"$ACTIVE_JOBS_FILE"
  : >"$SUBMITTED_JOBS_FILE"
  : >"$RUN_LOG_FILE"
  write_run_env
  upload_pod_templates

  echo "Starting benchmark ..."
  echo "  Team                : $EMR_TEAM"
  echo "  Region              : $AWS_REGION"
  echo "  Endpoint            : $EMR_ENDPOINT_URL"
  echo "  PCP tier            : 4XL"
  echo "  Target rate         : ~100 jobs/min default step"
  echo "  Users               : $LOCUST_USERS"
  echo "  Spawn rate          : $LOCUST_SPAWN_RATE"
  echo "  Run time            : $LOCUST_RUN_TIME"
  echo "  Max submitted jobs  : $MAX_JOBS_TO_SUBMIT"
  echo "  Queries             : $TPCDS_QUERIES"
  echo "  Executors/job       : $SPARK_EXECUTOR_INSTANCES"
  echo "  Log file            : $RUN_LOG_FILE"

  (
    export EMR_TEAM
    export AWS_REGION
    export EMR_ENDPOINT_URL
    export EMR_VIRTUAL_CLUSTER_ID
    export EMR_EXECUTION_ROLE_ARN
    export EMR_RELEASE_LABEL
    export ECR_IMAGE
    export TPCDS_INPUT
    export OUTPUT_BUCKET="$S3_BUCKET"
    export SCRIPTS_S3_PATH
    export CW_LOG_GROUP="$CLOUDWATCH_LOG_GROUP"
    export TPCDS_QUERIES
    export TPCDS_ITERATIONS
    export TPCDS_SCALE_FACTOR
    export TPCDS_ONLY_WARN
    export SPARK_EXECUTOR_INSTANCES
    export SPARK_EXECUTOR_CORES
    export SPARK_EXECUTOR_MEMORY
    export SPARK_DRIVER_CORES
    export SPARK_DRIVER_MEMORY
    export SPARK_EXECUTOR_LIMIT_CORES
    export SPARK_DRIVER_LIMIT_CORES
    export EMR_MAX_POOL_CONNECTIONS
    export LOCUST_WAIT_MIN_S
    export LOCUST_WAIT_MAX_S
    export MAX_JOBS_TO_SUBMIT
    export BENCHMARK_JOB_NAME_PREFIX
    export BENCHMARK_SUBMITTED_JOBS_FILE="$SUBMITTED_JOBS_FILE"
    export BENCHMARK_ACTIVE_JOBS_FILE="$ACTIVE_JOBS_FILE"

    nohup locust \
      -f "$SCRIPT_DIR/locustfile.py" \
      --headless \
      -u "$LOCUST_USERS" \
      -r "$LOCUST_SPAWN_RATE" \
      --run-time "$LOCUST_RUN_TIME" \
      >>"$RUN_LOG_FILE" 2>&1 &
    echo $! >"$PID_FILE"
  )

  echo "Benchmark started with pid $(cat "$PID_FILE")."
  echo "Use './benchmark.sh status' to inspect or './benchmark.sh stop' to stop."
}

describe_job_state() {
  local job_id="$1"
  aws emr-containers describe-job-run \
    --virtual-cluster-id "$EMR_VIRTUAL_CLUSTER_ID" \
    --id "$job_id" \
    --region "$AWS_REGION" \
    --endpoint-url "$EMR_ENDPOINT_URL" \
    --query 'jobRun.state' \
    --output text
}

cancel_active_jobs() {
  [[ -f "$ACTIVE_JOBS_FILE" ]] || return 0
  while IFS= read -r job_id; do
    [[ -n "$job_id" ]] || continue
    local state
    state="$(describe_job_state "$job_id" 2>/dev/null || true)"
    if [[ -z "$state" ]]; then
      continue
    fi
    if is_terminal_state "$state"; then
      continue
    fi
    echo "Cancelling job $job_id (state=$state) ..."
    aws emr-containers cancel-job-run \
      --virtual-cluster-id "$EMR_VIRTUAL_CLUSTER_ID" \
      --id "$job_id" \
      --region "$AWS_REGION" \
      --endpoint-url "$EMR_ENDPOINT_URL" >/dev/null
  done <"$ACTIVE_JOBS_FILE"
}

refresh_active_jobs_file() {
  [[ -f "$ACTIVE_JOBS_FILE" ]] || return 0
  local remaining_jobs=()
  while IFS= read -r job_id; do
    [[ -n "$job_id" ]] || continue
    local state
    state="$(describe_job_state "$job_id" 2>/dev/null || true)"
    if [[ -z "$state" ]]; then
      continue
    fi
    if ! is_terminal_state "$state"; then
      remaining_jobs+=("$job_id")
    fi
  done <"$ACTIVE_JOBS_FILE"

  : >"$ACTIVE_JOBS_FILE"
  if (( ${#remaining_jobs[@]} > 0 )); then
    printf '%s\n' "${remaining_jobs[@]}" >"$ACTIVE_JOBS_FILE"
  fi
}

wait_for_active_jobs_terminal() {
  [[ -f "$ACTIVE_JOBS_FILE" ]] || return 0
  local waited=0
  while [[ -s "$ACTIVE_JOBS_FILE" ]]; do
    if (( waited >= CANCEL_WAIT_SECONDS )); then
      echo "Timed out waiting for all active EMR jobs to reach terminal states."
      return 1
    fi
    refresh_active_jobs_file
    [[ -s "$ACTIVE_JOBS_FILE" ]] || return 0
    sleep 5
    waited=$((waited + 5))
  done
  return 0
}

wait_for_locust_exit() {
  local waited=0
  if ! [[ -f "$PID_FILE" ]]; then
    return 0
  fi
  local pid
  pid="$(cat "$PID_FILE")"
  while kill -0 "$pid" >/dev/null 2>&1; do
    if (( waited >= STOP_WAIT_SECONDS )); then
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 0
}

stop_benchmark() {
  load_run_env
  if process_running; then
    local pid
    pid="$(cat "$PID_FILE")"
    echo "Stopping Locust pid $pid ..."
    kill -TERM "$pid"
    if ! wait_for_locust_exit; then
      echo "Locust did not exit within ${STOP_WAIT_SECONDS}s; continuing with EMR job cleanup."
    fi
  else
    echo "No running Locust process found. Proceeding with EMR job cleanup."
  fi

  cancel_active_jobs
  wait_for_active_jobs_terminal || true
  refresh_active_jobs_file
  rm -f "$PID_FILE"
  echo "Stop request complete. Active EMR jobs were cancelled when still non-terminal."
}

status_benchmark() {
  if process_running; then
    echo "Locust process: running (pid $(cat "$PID_FILE"))"
  else
    echo "Locust process: not running"
  fi
  if [[ -f "$ACTIVE_JOBS_FILE" ]]; then
    echo "Active job ids:"
    if [[ -s "$ACTIVE_JOBS_FILE" ]]; then
      cat "$ACTIVE_JOBS_FILE"
    else
      echo "  none"
    fi
  fi
  if [[ -f "$SUBMITTED_JOBS_FILE" ]]; then
    echo "Submitted jobs: $(wc -l <"$SUBMITTED_JOBS_FILE" | tr -d ' ')"
  fi
  if [[ -f "$RUN_LOG_FILE" ]]; then
    echo "Log file: $RUN_LOG_FILE"
  fi
}

case "$ACTION" in
  start) start_benchmark ;;
  stop) stop_benchmark ;;
  status) status_benchmark ;;
  *)
    echo "Usage: $0 {start|stop|status}" >&2
    exit 1
    ;;
esac
