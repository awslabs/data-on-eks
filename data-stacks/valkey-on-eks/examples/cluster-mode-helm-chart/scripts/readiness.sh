#!/bin/sh
# readiness.sh — cluster-aware readiness probe.
#
# A pod is Ready when:
#   1. The local Valkey server responds to PING, AND
#   2. Either:
#        a. cluster_slots_assigned:16384 (cluster bootstrapped, this pod sees
#           the full slot map), OR
#        b. cluster_known_nodes:1 AND cluster_slots_assigned:0 (this pod has
#           not yet been joined to the cluster — Ready in bootstrap-pending
#           mode so the post-install Hook Job can reach it via DNS).
#   3. If this node is a replica, master_link_status must be up and the
#      initial RDB load must be finished (loading:0).
#
# The post-install Job is the authoritative bootstrap point — we do not need
# peer-consensus here; each pod only vouches for itself.

set -eu

AUTH_OPT=""
if [ -n "${VALKEY_PASSWORD:-}" ]; then
  AUTH_OPT="-a ${VALKEY_PASSWORD} --no-auth-warning"
fi

# CHECK 1 — local PING
if ! timeout -s 15 5 valkey-cli ${AUTH_OPT} ping >/dev/null 2>&1; then
  echo "Not Ready: local PING failed"
  exit 1
fi

CLUSTER_INFO=$(valkey-cli ${AUTH_OPT} cluster info 2>/dev/null || echo "")
CLUSTER_STATE=$(echo "${CLUSTER_INFO}" | awk -F: '/^cluster_state:/ {gsub(/[\r\n ]/,"",$2); print $2}')
KNOWN_NODES=$(echo "${CLUSTER_INFO}" | awk -F: '/^cluster_known_nodes:/ {gsub(/[^0-9]/,"",$2); print $2}')
SLOTS_ASSIGNED=$(echo "${CLUSTER_INFO}" | awk -F: '/^cluster_slots_assigned:/ {gsub(/[^0-9]/,"",$2); print $2}')
KNOWN_NODES="${KNOWN_NODES:-0}"
SLOTS_ASSIGNED="${SLOTS_ASSIGNED:-0}"

# CHECK 2a — bootstrap-pending: the post-install Job needs to reach this pod
# before the cluster exists. cluster_state==ok at this stage is misleading
# (a cluster-enabled node with zero slots reports ok), so we gate on the
# combination of cluster_known_nodes:1 AND cluster_slots_assigned:0.
if [ "${KNOWN_NODES}" = "1" ] && [ "${SLOTS_ASSIGNED}" = "0" ]; then
  echo "Ready: bootstrap-pending"
  exit 0
fi

# CHECK 2b — steady state requires a fully-formed cluster
if [ "${CLUSTER_STATE}" != "ok" ]; then
  echo "Not Ready: cluster_state=${CLUSTER_STATE:-unknown}"
  exit 1
fi
if [ "${SLOTS_ASSIGNED}" != "16384" ]; then
  echo "Not Ready: cluster_slots_assigned=${SLOTS_ASSIGNED}"
  exit 1
fi

# CHECK 3 — replica health
ROLE=$(valkey-cli ${AUTH_OPT} info replication 2>/dev/null | awk -F: '/^role:/ {gsub(/[\r\n ]/,"",$2); print $2}')
if [ "${ROLE}" = "slave" ]; then
  LINK=$(valkey-cli ${AUTH_OPT} info replication 2>/dev/null | awk -F: '/^master_link_status:/ {gsub(/[\r\n ]/,"",$2); print $2}')
  if [ "${LINK}" != "up" ]; then
    echo "Not Ready: master_link_status=${LINK}"
    exit 1
  fi
  LOADING=$(valkey-cli ${AUTH_OPT} info persistence 2>/dev/null | awk -F: '/^loading:/ {gsub(/[\r\n ]/,"",$2); print $2}')
  if [ "${LOADING}" = "1" ]; then
    echo "Not Ready: loading RDB"
    exit 1
  fi
fi

echo "Ready: cluster_state=ok role=${ROLE}"
exit 0
