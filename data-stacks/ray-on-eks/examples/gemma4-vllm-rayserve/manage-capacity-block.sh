#!/bin/bash
# Render, apply, inspect, or delete the benchmark-only P5 Capacity Block pool.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
TEMPLATE="$ROOT/karpenter-capacity-block.template.yaml"
RENDERED="$ROOT/benchmarks/results/infra/gpu-capacity-block.yaml"

usage() {
  echo "usage: $0 render|apply <cr-ID> <us-west-2a|us-west-2b>" >&2
  echo "       $0 status|delete" >&2
  exit 2
}

render() {
  local reservation_id="${1:-}" zone="${2:-}"
  [[ "$reservation_id" =~ ^cr-[0-9a-f]+$ ]] || {
    echo "invalid Capacity Reservation ID: $reservation_id" >&2
    exit 2
  }
  [[ "$zone" == "us-west-2a" || "$zone" == "us-west-2b" ]] || {
    echo "Capacity Block AZ must be us-west-2a or us-west-2b: $zone" >&2
    exit 2
  }
  mkdir -p "$(dirname "$RENDERED")"
  sed -e "s/__CAPACITY_RESERVATION_ID__/$reservation_id/g" \
      -e "s/__CAPACITY_RESERVATION_AZ__/$zone/g" \
      "$TEMPLATE" > "$RENDERED"
  echo "$RENDERED"
}

case "${1:-}" in
  render)
    render "${2:-}" "${3:-}"
    ;;
  apply)
    manifest=$(render "${2:-}" "${3:-}")
    kubectl apply -f "$manifest"
    ;;
  status)
    kubectl get ec2nodeclass gpu-capacity-block -o wide
    kubectl get nodepool gpu-capacity-block -o wide
    kubectl get nodeclaims -l karpenter.sh/nodepool=gpu-capacity-block -o wide
    ;;
  delete)
    # Deleting the NodePool first terminates only its NodeClaims. The shared
    # normal GPU NodePool and EC2NodeClass are never targeted by this helper.
    kubectl delete nodepool gpu-capacity-block --ignore-not-found
    kubectl delete ec2nodeclass gpu-capacity-block --ignore-not-found
    ;;
  *) usage ;;
esac
