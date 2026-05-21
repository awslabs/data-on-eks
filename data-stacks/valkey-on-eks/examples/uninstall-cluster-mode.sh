#!/usr/bin/env bash
# uninstall-cluster-mode.sh — remove the local Valkey cluster-mode release.
#
# `helm uninstall` deletes the StatefulSet, Services, ConfigMaps, ServiceAccount,
# PDB, and ServiceMonitor. By default it does NOT delete:
#   - the auth Secret (annotated `helm.sh/resource-policy: keep` so passwords
#     survive uninstall/reinstall cycles)
#   - the per-pod PVCs (kept so a reinstall reuses the same on-disk cluster
#     state — the `nodes.conf` file inside each PVC carries each pod's node ID)
#
# Pass --purge to delete the Secret and PVCs too.

set -euo pipefail

RELEASE="valkey-cluster"
NAMESPACE="valkey-cluster"
PURGE=0

usage() {
  cat <<USAGE
Usage: $0 [options]

Options:
  --release NAME    Helm release name (default: valkey-cluster)
  --namespace NAME  Kubernetes namespace (default: valkey-cluster)
  --purge           Also delete PVCs and the auth Secret (irreversible)
  -h, --help        Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release)   RELEASE="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --purge)     PURGE=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "Unknown flag: $1" >&2; usage >&2; exit 64 ;;
  esac
done

for tool in kubectl helm; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool not found in PATH" >&2; exit 127; }
done

if helm status "$RELEASE" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "Uninstalling helm release ${RELEASE} from ${NAMESPACE}"
  helm uninstall "$RELEASE" -n "$NAMESPACE"
else
  echo "No helm release ${RELEASE} found in ${NAMESPACE}; skipping helm uninstall"
fi

if (( PURGE == 1 )); then
  echo "Purging PVCs and auth Secret"
  kubectl -n "$NAMESPACE" delete pvc -l app.kubernetes.io/instance="$RELEASE" --ignore-not-found
  kubectl -n "$NAMESPACE" delete secret "${RELEASE}-auth" --ignore-not-found
  echo "Deleting namespace ${NAMESPACE}"
  kubectl delete namespace "$NAMESPACE" --ignore-not-found
else
  cat <<KEEP

PVCs and auth Secret preserved. To delete them too:

  kubectl -n ${NAMESPACE} delete pvc -l app.kubernetes.io/instance=${RELEASE}
  kubectl -n ${NAMESPACE} delete secret ${RELEASE}-auth
  kubectl delete namespace ${NAMESPACE}

Or re-run with --purge.
KEEP
fi
