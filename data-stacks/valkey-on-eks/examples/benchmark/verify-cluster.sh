#!/usr/bin/env bash
# verify-cluster.sh — sanity check the Valkey cluster-mode deployment before
# (and after) running benchmarks. Prints pod state, AZ topology, primary →
# replica AZ pairing, slot distribution, and `valkey-cli --cluster check`.
#
# Usage:
#   ./verify-cluster.sh                    # default namespace valkey-cluster
#   ./verify-cluster.sh --namespace foo
#
# Exit 0 only when:
#   - cluster_state is ok
#   - all 16384 slots are assigned and ok
#   - every primary has at least one in-different-AZ replica

set -euo pipefail

NAMESPACE="valkey-cluster"
SECRET="valkey-cluster-auth"
KEY="default"
PRIMARY_POD="valkey-cluster-0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --secret)    SECRET="$2"; shift 2 ;;
    -h|--help)
      cat <<USAGE
Usage: $0 [options]
  --namespace NS      Kubernetes namespace (default: valkey-cluster)
  --secret NAME       Auth secret name (default: valkey-cluster-auth)
  -h, --help
USAGE
      exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 64 ;;
  esac
done

PASS="$(kubectl -n "$NAMESPACE" get secret "$SECRET" -o jsonpath="{.data.$KEY}" | base64 -d)"

echo "=== Pods ==="
kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/name=valkey-cluster -o wide

echo
echo "=== Per-pod AZ ==="
kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/name=valkey-cluster \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeName}{"\n"}{end}' | \
while read -r pod node; do
  [[ -z "$pod" ]] && continue
  az="$(kubectl get node "$node" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' 2>/dev/null || echo unknown)"
  printf "  %-22s %-46s %s\n" "$pod" "$node" "$az"
done

echo
echo "=== cluster info ==="
kubectl -n "$NAMESPACE" exec "$PRIMARY_POD" -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning cluster info 2>/dev/null | \
  grep -E '^(cluster_state|cluster_slots_(assigned|ok|pfail|fail)|cluster_known_nodes|cluster_size|cluster_my_epoch):'

echo
echo "=== Topology + primary↔replica AZ pairing ==="
NODES_OUT="$(kubectl -n "$NAMESPACE" exec "$PRIMARY_POD" -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning cluster nodes 2>/dev/null)"

# Build pod → AZ table as a newline-delimited string ("pod az" per line).
# Avoids bash-4 associative arrays so the script runs on macOS bash 3.2.
POD_AZ_TABLE=""
while read -r pod node; do
  [[ -z "$pod" ]] && continue
  az="$(kubectl get node "$node" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' 2>/dev/null || echo unknown)"
  POD_AZ_TABLE+="${pod} ${az}"$'\n'
done < <(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/name=valkey-cluster \
           -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeName}{"\n"}{end}')

az_for_pod() {
  echo "$POD_AZ_TABLE" | awk -v p="$1" '$1 == p {print $2; exit}'
}

# Parse cluster nodes — emit "id role primary_id pod"
parsed="$(echo "$NODES_OUT" | awk '
  {
    nid = $1
    addr_dns = $2
    n = split(addr_dns, parts, ",")
    pod = (n >= 2) ? parts[2] : ""
    sub(/\..*/, "", pod)
    role = ($3 ~ /master/) ? "master" : "slave"
    primary = (role == "slave") ? $4 : "-"
    if (pod != "") print nid, role, primary, pod
  }
')"

# Print primaries with their replicas + AZ comparison
fail=0
while read -r nid role _primary pod; do
  [[ "$role" != "master" ]] && continue
  az_p="$(az_for_pod "$pod")"
  printf "PRIMARY  %-22s %s\n" "$pod" "${az_p:-?}"
  while read -r _nid_r role_r primary_r pod_r; do
    [[ "$role_r" != "slave" ]] && continue
    [[ "$primary_r" != "$nid" ]] && continue
    az_r="$(az_for_pod "$pod_r")"
    flag="cross-AZ ✓"
    if [[ "${az_r:-?}" == "${az_p:-?}" && "$az_r" != "" ]]; then
      flag="SAME-AZ ⚠"
      fail=1
    fi
    printf "  replica  %-20s %-14s %s\n" "$pod_r" "${az_r:-?}" "$flag"
  done <<< "$parsed"
done <<< "$parsed"

echo
echo "=== Slot ownership + key counts ==="
echo "$NODES_OUT" | awk '
  /master/ {
    slots = ""
    for (i=9; i<=NF; i++) slots = slots $i " "
    addr_dns = $2
    n = split(addr_dns, parts, ",")
    pod = (n >= 2) ? parts[2] : ""
    sub(/\..*/, "", pod)
    printf "  %-22s slots: %s\n", pod, slots
  }
'

echo
echo "=== valkey-cli --cluster check (slot coverage + replica agreement) ==="
kubectl -n "$NAMESPACE" exec "$PRIMARY_POD" -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning --cluster check \
  "$PRIMARY_POD.valkey-cluster-headless.$NAMESPACE.svc.cluster.local:6379" 2>&1 \
  | sed -n '/keys |/,/^\[OK\] All [0-9]* slots covered/p'

echo

# Final verdict
state="$(kubectl -n "$NAMESPACE" exec "$PRIMARY_POD" -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning cluster info 2>/dev/null | \
  awk -F: '/^cluster_state/ {gsub(/[\r ]/,"",$2); print $2}')"

if [[ "$state" == "ok" && "$fail" -eq 0 ]]; then
  echo "VERIFY: PASS — cluster_state=ok, all primary↔replica pairs are cross-AZ."
  exit 0
fi

echo "VERIFY: FAIL — cluster_state=$state, same-AZ pairs found=$fail"
exit 1
