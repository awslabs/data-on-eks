#!/usr/bin/env bash
# ============================================================
# run-iceberg-benchmark.sh
#
# End-to-end script for running the TPC-DS v4 Iceberg benchmark
# with DataFusion Comet on Amazon EKS (Graviton4 / r8g).
#
# Steps:
#   1. Prerequisites check
#   2. Build & push Docker image  (--skip-build to skip)
#   3. Parquet → Iceberg conversion job  (--skip-conversion to skip)
#   4. Benchmark job
#   5. Collect results
#
# Usage:
#   ./run-iceberg-benchmark.sh --bucket <name> [OPTIONS]
#
# Options:
#   --bucket        <name>   S3 bucket name (required)
#   --scale         <n>      Scale factor: 1, 3, 10 (default: 1)
#   --region        <name>   AWS region (default: us-west-2)
#   --ecr-account   <id>     AWS account ID for private ECR (default: ${AWS_ACCOUNT_ID})
#   --namespace     <ns>     Kubernetes namespace (default: spark-team-a)
#   --skip-build             Skip docker build/push
#   --skip-conversion        Skip Parquet→Iceberg conversion job
#   --dry-run                Print commands without executing
#
# Examples:
#   # Full run from scratch (1TB)
#   ./run-iceberg-benchmark.sh --bucket ${S3_BUCKET}
#
#   # Run 3TB benchmark (data already generated)
#   ./run-iceberg-benchmark.sh --bucket ${S3_BUCKET} \
#       --scale 3 --skip-build
#
#   # Re-run benchmark only (image + tables already exist)
#   ./run-iceberg-benchmark.sh --bucket ${S3_BUCKET} \
#       --skip-build --skip-conversion
# ============================================================

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
S3_BUCKET=""
SCALE="1"
REGION="us-west-2"
ECR_ACCOUNT=""
NAMESPACE="spark-team-a"
SKIP_BUILD=false
SKIP_CONVERSION=false
DRY_RUN=false

IMAGE_NAME="spark-benchmark-native"
IMAGE_TAG="3.5.8-tpcds4"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${BLUE}[info]${RESET}  $*"; }
success() { echo -e "${GREEN}[ok]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[warn]${RESET}  $*"; }
error()   { echo -e "${RED}[error]${RESET} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}${BLUE}══ $* ${RESET}"; }
run()     { if $DRY_RUN; then echo "[dry-run] $*"; else eval "$*"; fi; }

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket)          S3_BUCKET="$2";    shift 2 ;;
    --scale)           SCALE="$2";        shift 2 ;;
    --region)          REGION="$2";       shift 2 ;;
    --ecr-account)     ECR_ACCOUNT="$2";  shift 2 ;;
    --namespace)       NAMESPACE="$2";    shift 2 ;;
    --skip-build)      SKIP_BUILD=true;   shift ;;
    --skip-conversion) SKIP_CONVERSION=true; shift ;;
    --dry-run)         DRY_RUN=true;      shift ;;
    *) error "Unknown argument: $1" ;;
  esac
done

[[ -z "$S3_BUCKET" ]] && error "--bucket is required"

FULL_IMAGE="${ECR_ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${IMAGE_NAME}:${IMAGE_TAG}"
SCALE_TB="${SCALE}TB"
GLUE_DB="tpcds_${SCALE}tb"
export S3_BUCKET REGION NAMESPACE SCALE SCALE_TB GLUE_DB

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 — Prerequisites
# ─────────────────────────────────────────────────────────────────────────────
step "Section 1: Prerequisites"

# kubectl
command -v kubectl  &>/dev/null || error "kubectl not found — install and configure kubeconfig"
command -v aws      &>/dev/null || error "AWS CLI not found — brew install awscli"
command -v docker   &>/dev/null || error "Docker not found"
command -v envsubst &>/dev/null || error "envsubst not found — brew install gettext && brew link gettext --force"

# kubectl context
KUBE_CTX=$(kubectl config current-context 2>/dev/null || echo "none")
info "kubectl context : ${KUBE_CTX}"
[[ "$KUBE_CTX" == "none" ]] && error "No active kubectl context — run: aws eks update-kubeconfig --name <cluster> --region ${REGION}"

# Namespace
kubectl get namespace "${NAMESPACE}" &>/dev/null \
  || error "Namespace '${NAMESPACE}' not found — deploy Spark Operator first"

# S3 bucket reachability
aws s3 ls "s3://${S3_BUCKET}/" --region "${REGION}" &>/dev/null \
  || error "Cannot access s3://${S3_BUCKET}/ — check IAM permissions"

# Confirm source data exists
aws s3 ls "s3://${S3_BUCKET}/TPCDS-TEST-1TB/" --region "${REGION}" &>/dev/null \
  || error "Source data not found at s3://${S3_BUCKET}/TPCDS-TEST-1TB/ — generate it first"

success "All prerequisites met"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 — Build & push Docker image
# ─────────────────────────────────────────────────────────────────────────────
step "Section 2: Build & push Docker image"

if $SKIP_BUILD; then
  warn "Skipping build (--skip-build). Assuming ${FULL_IMAGE} exists."
else
  info "Building ARM64 image for Graviton4 (r8g)..."
  info "Image: ${FULL_IMAGE}"

  # ECR login for private ECR
  aws ecr get-login-password --region "${REGION}" \
    | docker login --username AWS --password-stdin "${ECR_ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

  run "docker buildx build \
    --platform linux/arm64 \
    --file ${SCRIPT_DIR}/Dockerfile-comet-iceberg \
    --tag ${FULL_IMAGE} \
    --push \
    ${SCRIPT_DIR}"

  success "Image pushed: ${FULL_IMAGE}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 — Parquet → Iceberg conversion job
# ─────────────────────────────────────────────────────────────────────────────
step "Section 3: Parquet → Iceberg conversion"

if $SKIP_CONVERSION; then
  warn "Skipping conversion (--skip-conversion). Assuming Glue DB tpcds_${SCALE}tb exists."
else
  CONV_APP="tpcds-parquet-to-iceberg-${SCALE}tb"

  # Clean up any previous run
  kubectl delete sparkapplication "${CONV_APP}" -n "${NAMESPACE}" --ignore-not-found

  info "Submitting conversion job for ${SCALE_TB}..."
  run "envsubst < ${SCRIPT_DIR}/tpcds-parquet-to-iceberg.yaml | kubectl apply -f -"

  info "Waiting for conversion job to complete (can take 10 min for 1TB, 25 min for 3TB)..."
  _poll_spark_app() {
    local app="$1" ns="$2" timeout_min="${3:-120}"
    local elapsed=0 interval=30
    while [[ $elapsed -lt $((timeout_min * 60)) ]]; do
      state=$(kubectl get sparkapplication "${app}" -n "${ns}" \
                -o jsonpath='{.status.applicationState.state}' 2>/dev/null || echo "UNKNOWN")
      echo -e "  [$(date +%H:%M:%S)] ${app} → ${state}"
      case "$state" in
        COMPLETED) return 0 ;;
        FAILED|SUBMISSION_FAILED|INVALIDATING)
          error "SparkApplication ${app} failed with state: ${state}"
          ;;
      esac
      sleep $interval
      elapsed=$((elapsed + interval))
    done
    error "Timed out waiting for ${app} after ${timeout_min} minutes"
  }

  _poll_spark_app "${CONV_APP}" "${NAMESPACE}" 120

  success "Conversion complete"

  # Verify Glue tables
  info "Verifying Glue tables in ${GLUE_DB}..."
  TABLE_COUNT=$(aws glue get-tables \
    --database-name "${GLUE_DB}" \
    --region "${REGION}" \
    --query 'length(TableList)' \
    --output text 2>/dev/null || echo "0")

  info "Glue tables found: ${TABLE_COUNT} (expected 24)"
  if [[ "${TABLE_COUNT}" -lt 24 ]]; then
    warn "Expected 24 tables but found ${TABLE_COUNT} — check conversion job logs:"
    warn "  kubectl logs -n ${NAMESPACE} -l spark-role=driver,spark-app-name=${CONV_APP} --tail=100"
  else
    success "All 24 TPC-DS tables present in Glue DB: ${GLUE_DB}"
  fi

  aws glue get-tables \
    --database-name "${GLUE_DB}" \
    --region "${REGION}" \
    --query 'TableList[].Name' \
    --output table 2>/dev/null || true
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 — Run benchmark
# ─────────────────────────────────────────────────────────────────────────────
step "Section 4: TPC-DS Iceberg benchmark"

BENCH_APP="tpcds-benchmark-iceberg-comet"

# Clean up any previous run
kubectl delete sparkapplication "${BENCH_APP}" -n "${NAMESPACE}" --ignore-not-found

info "Submitting benchmark job..."
run "kubectl apply -f ${SCRIPT_DIR}/tpcds-benchmark-iceberg-comet.yaml"

info "Waiting for benchmark to complete (typically 2-4 hours for 99 queries × 3 iterations)..."
_poll_spark_app() {
  local app="$1" ns="$2" timeout_min="${3:-300}"
  local elapsed=0 interval=60
  while [[ $elapsed -lt $((timeout_min * 60)) ]]; do
    state=$(kubectl get sparkapplication "${app}" -n "${ns}" \
              -o jsonpath='{.status.applicationState.state}' 2>/dev/null || echo "UNKNOWN")
    echo -e "  [$(date +%H:%M:%S)] ${app} → ${state}"
    case "$state" in
      COMPLETED) return 0 ;;
      FAILED|SUBMISSION_FAILED|INVALIDATING)
        echo ""
        warn "Job failed — fetching driver logs..."
        kubectl logs -n "${ns}" -l "spark-role=driver,spark-app-name=${app}" --tail=100 || true
        error "SparkApplication ${app} failed with state: ${state}"
        ;;
    esac
    sleep $interval
    elapsed=$((elapsed + interval))
  done
  error "Timed out waiting for ${app} after ${timeout_min} minutes"
}

_poll_spark_app "${BENCH_APP}" "${NAMESPACE}" 300
success "Benchmark complete"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5 — Collect results
# ─────────────────────────────────────────────────────────────────────────────
step "Section 5: Collect results"

RESULTS_DIR="${SCRIPT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

RESULTS_S3="s3://${S3_BUCKET}/TPCDS-TEST-${SCALE_TB}-RESULT-COMET-ICEBERG-R8G/"

info "Downloading results from ${RESULTS_S3}..."
run "aws s3 cp ${RESULTS_S3} ${RESULTS_DIR}/ --recursive --include '*.csv' --region ${REGION}"

CSV_COUNT=$(find "${RESULTS_DIR}" -name "*.csv" 2>/dev/null | wc -l | tr -d ' ')
success "Downloaded ${CSV_COUNT} CSV file(s) to ${RESULTS_DIR}/"

# Print summary if csvkit or awk available
if command -v awk &>/dev/null && [[ $CSV_COUNT -gt 0 ]]; then
  info "Quick summary (first result file):"
  FIRST_CSV=$(find "${RESULTS_DIR}" -name "*.csv" | head -1)
  awk -F',' 'NR==1{print "Columns:", NF, "—", $0; next} NR<=6{print}' "${FIRST_CSV}" 2>/dev/null || true
fi

echo ""
echo -e "${BOLD}${GREEN}All done!${RESET}"
echo ""
echo "Results     : ${RESULTS_DIR}/"
echo "S3 results  : ${RESULTS_S3}"
echo "Event logs  : s3://${S3_BUCKET}/spark-event-logs/"
echo ""
echo "Next steps:"
echo "  1. Compare DPP-sensitive queries vs prior Parquet run:"
echo "     q14a, q14b, q23a, q23b, q24a, q24b, q39a, q39b, q47, q57"
echo "  2. Check Comet fallback rate in driver logs:"
echo "     kubectl logs -n ${NAMESPACE} -l spark-role=driver,spark-app-name=${BENCH_APP} | grep 'CometFallback'"
echo "  3. Share per-query CSV with DataFusion team"
