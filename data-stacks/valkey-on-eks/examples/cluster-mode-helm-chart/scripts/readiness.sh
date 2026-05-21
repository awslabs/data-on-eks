#!/bin/sh
# readiness.sh — consensus-based readiness probe.
#
# A pod is Ready only when a majority of its peers see it as healthy. This
# prevents the headless Service from publishing a pod that is locally healthy
# but not yet visible to peers, which causes MOVED-redirect storms when
# clients query the new pod and it hasn't received the slot map yet.
#
# Always allows local PING + bootstrap mode (cluster_known_nodes==1) as a
# baseline. Beyond that, requires (n-1) of n peers to confirm via
# `cluster nodes | grep $my_id | grep connected`.

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
KNOWN_NODES=$(echo "${CLUSTER_INFO}" | awk -F: '/^cluster_known_nodes:/ {gsub(/[^0-9]/,"",$2); print $2}')
KNOWN_NODES="${KNOWN_NODES:-0}"

# CHECK 2 — bootstrap mode (we know about no peers yet)
if [ "${KNOWN_NODES}" = "1" ]; then
  echo "Ready: bootstrap mode (cluster_known_nodes=1)"
  exit 0
fi

# CHECK 3 — replication link health (replicas only)
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

# CHECK 4 — peer consensus
MY_ID=$(valkey-cli ${AUTH_OPT} cluster myid 2>/dev/null || echo "")
if [ -z "${MY_ID}" ]; then
  echo "Not Ready: could not retrieve cluster myid"
  exit 1
fi

NODES_OUTPUT=$(valkey-cli ${AUTH_OPT} cluster nodes 2>/dev/null || echo "")
PEERS=$(echo "${NODES_OUTPUT}" \
  | grep -v "myself" \
  | grep -v "fail" \
  | grep -v "handshake" \
  | awk '{print $2}' \
  | cut -d'@' -f1)

TOTAL_PEERS=$(echo "${PEERS}" | grep -c '.' || true)
if [ "${TOTAL_PEERS}" = "0" ]; then
  EXPECTED=$(( ${REPLICAS:-6} - 1 ))
  if [ "${KNOWN_NODES}" -ge "${EXPECTED}" ]; then
    echo "Ready: no peers reachable but local view has ${KNOWN_NODES}/${EXPECTED} nodes"
    exit 0
  fi
  echo "Not Ready: no peers reachable and local view too small (${KNOWN_NODES})"
  exit 1
fi

SUCCESS=0
for PEER in ${PEERS}; do
  PEER_HOST="${PEER%:*}"
  PEER_PORT="${PEER##*:}"
  REMOTE_OUTPUT=$(timeout -s 9 2 valkey-cli ${AUTH_OPT} -h "${PEER_HOST}" -p "${PEER_PORT}" \
                   cluster nodes 2>/dev/null | grep "${MY_ID}" || echo "")
  if [ -n "${REMOTE_OUTPUT}" ] && \
     echo "${REMOTE_OUTPUT}" | grep -q "connected" && \
     ! echo "${REMOTE_OUTPUT}" | grep -qE "(fail|handshake|noaddr)"; then
    SUCCESS=$((SUCCESS + 1))
  fi
done

# Tolerate one peer disagreement
if [ "${TOTAL_PEERS}" -gt 1 ]; then
  REQUIRED=$(( TOTAL_PEERS - 1 ))
else
  REQUIRED=1
fi

if [ "${SUCCESS}" -ge "${REQUIRED}" ]; then
  echo "Ready: ${SUCCESS}/${TOTAL_PEERS} peers verified me (required ${REQUIRED})"
  exit 0
fi

echo "Not Ready: ${SUCCESS}/${TOTAL_PEERS} peers verified me (required ${REQUIRED})"
exit 1
