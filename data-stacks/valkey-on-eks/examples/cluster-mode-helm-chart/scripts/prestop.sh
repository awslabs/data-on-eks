#!/bin/sh
# prestop.sh — graceful master failover + CLUSTER FORGET broadcast.
#
# Runs when Kubernetes signals pod termination (drain, rolling update, scale
# down). Without this, master-pod restarts cause a 10-15 second write outage
# per shard while the cluster's failure detector takes effect.
#
# Steps:
#   1. If this pod is a master, find one of its replicas and trigger
#      `CLUSTER FAILOVER TAKEOVER` against the replica. The replica becomes
#      the new master immediately (no consensus wait). Clients see a
#      sub-second blip.
#   2. Tell every other peer to `CLUSTER FORGET` this node. Without this, the
#      peers' gossip tables carry the dead node forward and the next pod
#      rejoin sequence has to clean it up.
#   3. SHUTDOWN SAVE.
#
# The container's terminationGracePeriodSeconds must be large enough to cover
# all three steps — 60 seconds is the chart default.

set -eu

log() { printf '[prestop] %s\n' "$*"; }

AUTH_OPT=""
if [ -n "${VALKEY_PASSWORD:-}" ]; then
  AUTH_OPT="-a ${VALKEY_PASSWORD} --no-auth-warning"
fi

VALKEY_CLI="valkey-cli ${AUTH_OPT}"

NODE_ID=$(${VALKEY_CLI} cluster nodes 2>/dev/null | awk '/myself/ {print $1; exit}')
if [ -z "${NODE_ID}" ]; then
  log "could not retrieve node ID; exiting cleanly so K8s terminates the pod"
  exit 0
fi

ROLE=$(${VALKEY_CLI} info replication 2>/dev/null | awk -F: '/^role:/ {gsub(/[\r\n ]/,"",$2); print $2}')
log "node_id=${NODE_ID} role=${ROLE}"

# ---------------------------------------------------------------------------
# Step 1 — graceful failover if we're a master
# ---------------------------------------------------------------------------
if [ "${ROLE}" = "master" ]; then
  log "master role detected; initiating failover"

  SLAVE_ADDR=$(${VALKEY_CLI} cluster nodes 2>/dev/null \
                | awk -v me="${NODE_ID}" '$4 == me && /slave/ && !/fail/ {print $2; exit}' \
                | cut -d'@' -f1)

  if [ -z "${SLAVE_ADDR}" ]; then
    log "no healthy replica found; skipping failover"
  else
    SLAVE_HOST="${SLAVE_ADDR%:*}"
    SLAVE_PORT="${SLAVE_ADDR##*:}"
    log "issuing CLUSTER FAILOVER TAKEOVER to ${SLAVE_HOST}:${SLAVE_PORT}"
    ${VALKEY_CLI} -h "${SLAVE_HOST}" -p "${SLAVE_PORT}" cluster failover takeover || \
      log "TAKEOVER returned non-zero; continuing"

    # Wait up to 20 seconds for the replica to be promoted
    i=0
    while [ "${i}" -lt 10 ]; do
      sleep 2
      NEW_ROLE=$(${VALKEY_CLI} -h "${SLAVE_HOST}" -p "${SLAVE_PORT}" \
                  info replication 2>/dev/null \
                  | awk -F: '/^role:/ {gsub(/[\r\n ]/,"",$2); print $2}')
      if [ "${NEW_ROLE}" = "master" ]; then
        log "replica ${SLAVE_HOST}:${SLAVE_PORT} promoted to master"
        break
      fi
      i=$((i + 1))
    done
  fi
fi

# ---------------------------------------------------------------------------
# Step 2 — broadcast CLUSTER FORGET to every other peer
# ---------------------------------------------------------------------------
log "broadcasting CLUSTER FORGET ${NODE_ID} to peers"
PEERS=$(${VALKEY_CLI} cluster nodes 2>/dev/null | grep -v "myself" | awk '{print $2}' | cut -d'@' -f1)
for PEER in ${PEERS}; do
  PEER_HOST="${PEER%:*}"
  PEER_PORT="${PEER##*:}"
  ${VALKEY_CLI} -h "${PEER_HOST}" -p "${PEER_PORT}" cluster forget "${NODE_ID}" >/dev/null 2>&1 &
done
wait
sleep 2

# ---------------------------------------------------------------------------
# Step 3 — graceful shutdown with persistence
# ---------------------------------------------------------------------------
log "issuing SHUTDOWN SAVE"
${VALKEY_CLI} shutdown save || log "SHUTDOWN SAVE returned non-zero (server may have already exited)"
exit 0
