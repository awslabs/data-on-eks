#!/bin/sh
# prestop.sh — graceful primary failover at shutdown.
#
# Runs when Kubernetes signals pod termination (drain, rolling update, scale
# down). If this pod is currently a primary, we issue CLUSTER FAILOVER against
# one of its replicas to hand off the role before the server exits. Without
# this, primary-pod restarts cause a 10-15 second write outage per shard while
# the cluster's failure detector takes effect.
#
# Steps:
#   1. If primary: pick a healthy replica, issue CLUSTER FAILOVER, wait for
#      the role swap.
#   2. SHUTDOWN — Valkey persists then exits.
#
# CLUSTER FORGET is intentionally NOT broadcast here. The pod is coming back
# (StatefulSet) and forgetting + meeting again loses gossip state for no
# benefit. The cluster's own failure detector handles the transient absence.
#
# terminationGracePeriodSeconds must cover step 1 + 2 — 30s default is safe.

set -eu

log() { printf '[prestop] %s\n' "$*"; }

AUTH_OPT=""
if [ -n "${VALKEY_PASSWORD:-}" ]; then
  AUTH_OPT="-a ${VALKEY_PASSWORD} --no-auth-warning"
fi

VALKEY_CLI="valkey-cli ${AUTH_OPT}"

NODE_ID=$(${VALKEY_CLI} cluster nodes 2>/dev/null | awk '/myself/ {print $1; exit}' || echo "")
if [ -z "${NODE_ID}" ]; then
  log "could not retrieve node ID; exiting cleanly so K8s terminates the pod"
  exit 0
fi

ROLE=$(${VALKEY_CLI} info replication 2>/dev/null | awk -F: '/^role:/ {gsub(/[\r\n ]/,"",$2); print $2}')
log "node_id=${NODE_ID} role=${ROLE}"

if [ "${ROLE}" = "master" ]; then
  log "primary role detected; initiating failover"

  REPLICA_ADDR=$(${VALKEY_CLI} cluster nodes 2>/dev/null \
                  | awk -v me="${NODE_ID}" '$4 == me && /slave/ && !/fail/ {print $2; exit}' \
                  | cut -d'@' -f1)

  if [ -z "${REPLICA_ADDR}" ]; then
    log "no healthy replica found; skipping failover"
  else
    REPLICA_HOST="${REPLICA_ADDR%:*}"
    REPLICA_PORT="${REPLICA_ADDR##*:}"
    log "issuing CLUSTER FAILOVER to ${REPLICA_HOST}:${REPLICA_PORT}"
    ${VALKEY_CLI} -h "${REPLICA_HOST}" -p "${REPLICA_PORT}" cluster failover || \
      log "CLUSTER FAILOVER returned non-zero; continuing"

    i=0
    while [ "${i}" -lt 10 ]; do
      sleep 1
      NEW_ROLE=$(${VALKEY_CLI} -h "${REPLICA_HOST}" -p "${REPLICA_PORT}" \
                  info replication 2>/dev/null \
                  | awk -F: '/^role:/ {gsub(/[\r\n ]/,"",$2); print $2}')
      if [ "${NEW_ROLE}" = "master" ]; then
        log "replica ${REPLICA_HOST}:${REPLICA_PORT} promoted to primary"
        break
      fi
      i=$((i + 1))
    done
  fi
fi

log "issuing SHUTDOWN"
${VALKEY_CLI} shutdown nosave || log "SHUTDOWN returned non-zero (server may have already exited)"
exit 0
