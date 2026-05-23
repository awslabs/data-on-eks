#!/usr/bin/env bash
# install-cluster-mode.sh — install the local Valkey cluster-mode chart.
#
# Optional companion to the default replication-mode deployment. Installs into
# its own namespace (`valkey-cluster` by default) so it runs alongside the
# replication release without conflict. Requires:
#   - kubectl (configured for the target EKS cluster)
#   - helm 3.13+
#
# Common usage:
#
#   ./install-cluster-mode.sh                 # 6 pods, ns=valkey-cluster
#   ./install-cluster-mode.sh --namespace foo # custom namespace
#   ./install-cluster-mode.sh --replicas 9 --replicas-per-primary 2
#                                             # 3 primaries × 2 replicas
#   ./install-cluster-mode.sh --dry-run       # render templates only
#
# To uninstall:
#   ./uninstall-cluster-mode.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${SCRIPT_DIR}/cluster-mode-helm-chart"

# Defaults
RELEASE="valkey-cluster"
NAMESPACE="valkey-cluster"
REPLICAS=""
REPLICAS_PER_PRIMARY=""
EXTRA_VALUES=""
EXTRA_SET=""
DRY_RUN=0

usage() {
  cat <<USAGE
Usage: $0 [options]

Options:
  --release NAME              Helm release name (default: valkey-cluster)
  --namespace NAME            Kubernetes namespace (default: valkey-cluster)
  --replicas N                Total pod count; must equal primaries × (1 + replicas-per-primary). Min 6.
  --replicas-per-primary N    Replicas per primary shard (default from values.yaml: 1)
  --values FILE               Additional helm values file (-f); may be repeated
  --set KEY=VALUE             Additional helm --set; may be repeated
  --dry-run                   Render templates without applying
  -h, --help                  Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release)              RELEASE="$2"; shift 2 ;;
    --namespace)            NAMESPACE="$2"; shift 2 ;;
    --replicas)             REPLICAS="$2"; shift 2 ;;
    --replicas-per-primary) REPLICAS_PER_PRIMARY="$2"; shift 2 ;;
    --values)               EXTRA_VALUES+=" -f $2"; shift 2 ;;
    --set)                  EXTRA_SET+=" --set $2"; shift 2 ;;
    --dry-run)              DRY_RUN=1; shift ;;
    -h|--help)              usage; exit 0 ;;
    *) echo "Unknown flag: $1" >&2; usage >&2; exit 64 ;;
  esac
done

# --- Pre-flight ---
for tool in kubectl helm; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool not found in PATH" >&2; exit 127; }
done

if [[ ! -d "$CHART_DIR" ]]; then
  echo "ERROR: chart directory not found: $CHART_DIR" >&2
  exit 1
fi

# --- Validation (do this before any cluster check so dry-run works offline) ---
if [[ -n "$REPLICAS" && -n "$REPLICAS_PER_PRIMARY" ]]; then
  if (( REPLICAS < 6 )); then
    echo "ERROR: --replicas must be >= 6 (cluster mode requires 3+ primaries for quorum)" >&2
    exit 64
  fi
  if (( REPLICAS % (1 + REPLICAS_PER_PRIMARY) != 0 )); then
    echo "ERROR: --replicas (${REPLICAS}) must equal primaries × (1 + replicas-per-primary)" >&2
    exit 64
  fi
fi

# --- Build helm args ---
HELM_ARGS=()
HELM_ARGS+=(--namespace "$NAMESPACE" --create-namespace)
[[ -n "$REPLICAS" ]]              && HELM_ARGS+=(--set "replicaCount=${REPLICAS}")
[[ -n "$REPLICAS_PER_PRIMARY" ]]  && HELM_ARGS+=(--set "replicasPerPrimary=${REPLICAS_PER_PRIMARY}")
# shellcheck disable=SC2206  # Word splitting is intentional — user may pass multi-flag strings.
[[ -n "$EXTRA_VALUES" ]]          && HELM_ARGS+=($EXTRA_VALUES)
# shellcheck disable=SC2206
[[ -n "$EXTRA_SET" ]]             && HELM_ARGS+=($EXTRA_SET)

if (( DRY_RUN == 1 )); then
  echo "[dry-run] rendering templates locally (no cluster contact)"
  helm template "$RELEASE" "$CHART_DIR" "${HELM_ARGS[@]}"
  exit 0
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "ERROR: kubectl cannot reach the cluster. Set KUBECONFIG or run:" >&2
  echo "  aws eks update-kubeconfig --name <cluster-name> --region <region>" >&2
  exit 1
fi

echo "============================================================"
echo " Installing Valkey cluster-mode chart"
echo "------------------------------------------------------------"
echo " release            : ${RELEASE}"
echo " namespace          : ${NAMESPACE}"
echo " chart              : ${CHART_DIR}"
echo " replicas           : ${REPLICAS:-default}"
echo " replicasPerPrimary : ${REPLICAS_PER_PRIMARY:-default}"
echo "============================================================"

# --- Install or upgrade ---
if helm status "$RELEASE" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "Release ${RELEASE} exists; running helm upgrade"
  helm upgrade "$RELEASE" "$CHART_DIR" "${HELM_ARGS[@]}"
else
  echo "Installing release ${RELEASE}"
  helm install "$RELEASE" "$CHART_DIR" "${HELM_ARGS[@]}"
fi

cat <<DONE

Release applied. Watch the bootstrap with:

  kubectl -n ${NAMESPACE} get pods -l app.kubernetes.io/instance=${RELEASE} -w

Once all pods are Running, verify cluster health:

  PASS=\$(kubectl -n ${NAMESPACE} get secret ${RELEASE}-auth \\
           -o jsonpath='{.data.default}' | base64 -d)
  kubectl -n ${NAMESPACE} exec ${RELEASE}-0 -c valkey -- \\
    valkey-cli -a "\$PASS" --no-auth-warning cluster info

DONE
