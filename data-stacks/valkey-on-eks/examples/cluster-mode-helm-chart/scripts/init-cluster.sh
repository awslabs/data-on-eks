#!/bin/sh
# init-cluster.sh — bootstrap or rejoin a Valkey cluster.
#
# Runs in the same container as the Valkey server (started in the background
# with `&` while the server runs in the foreground). Drives valkey-cli
# against localhost once the local server is up.
#
# Three execution paths:
#   1. Healthy peer found → REJOIN: forget stale self, CLUSTER MEET, find an
#      under-replicated primary, CLUSTER REPLICATE.
#   2. No healthy peer + ordinal 0 → BOOTSTRAP: wait for all peers to PING,
#      run `valkey-cli --cluster create`.
#   3. No healthy peer + ordinal > 0 → WAIT for ordinal 0 to declare ok.
#
# Required env (set by the StatefulSet template):
#   FULLNAME                   # release fullname (also the StatefulSet name)
#   HEADLESS_SVC               # headless Service name
#   NAMESPACE                  # release namespace
#   REPLICAS                   # total pod count (= primaries × (1 + replicasPerPrimary))
#   REPLICAS_PER_PRIMARY       # replicas per primary
#   HOSTNAME                   # this pod's name (e.g., release-valkey-cluster-3)
#   POD_IP                     # this pod's IP
#   VALKEYCLI_AUTH             # default ACL password (optional)
#   PEER_PING_TIMEOUT          # seconds to wait for each peer to PING
#   WAIT_FOR_BOOTSTRAP_TIMEOUT # seconds to wait for ordinal 0 to bootstrap
#   PRE_CREATE_SLEEP           # seconds to sleep before --cluster create

set -eu

log() { printf '[init-cluster] %s\n' "$*"; }
err() { printf '[init-cluster] ERROR: %s\n' "$*" >&2; }

PEER_PING_TIMEOUT="${PEER_PING_TIMEOUT:-120}"
WAIT_FOR_BOOTSTRAP_TIMEOUT="${WAIT_FOR_BOOTSTRAP_TIMEOUT:-600}"
PRE_CREATE_SLEEP="${PRE_CREATE_SLEEP:-10}"

# Single-node degenerate case
if [ "${REPLICAS}" -eq "1" ]; then
  log "REPLICAS=1; not running cluster bootstrap"
  exit 0
fi

ORDINAL=$(echo "${HOSTNAME}" | rev | cut -d'-' -f1 | rev)
PRIMARIES=$(( REPLICAS / (1 + REPLICAS_PER_PRIMARY) ))
DOMAIN="${FULLNAME}-${ORDINAL}.${HEADLESS_SVC}.${NAMESPACE}.svc.cluster.local"

AUTH_OPT=""
if [ -n "${VALKEYCLI_AUTH:-}" ]; then
  AUTH_OPT="-a ${VALKEYCLI_AUTH} --no-auth-warning"
fi

log "ordinal=${ORDINAL} primaries=${PRIMARIES} replicasPerPrimary=${REPLICAS_PER_PRIMARY}"
log "self=${DOMAIN} pod_ip=${POD_IP}"

# ---------------------------------------------------------------------------
# Wait for the local Valkey server to PING
# ---------------------------------------------------------------------------
WAITED=0
until valkey-cli ${AUTH_OPT} -h localhost ping 2>/dev/null | grep -q PONG; do
  if [ "${WAITED}" -ge 60 ]; then
    err "local Valkey did not respond to PING within 60s"
    exit 1
  fi
  log "waiting for local Valkey..."
  sleep 2
  WAITED=$((WAITED + 2))
done
log "local Valkey is responsive"

# ---------------------------------------------------------------------------
# Probe peers for an existing healthy cluster
# ---------------------------------------------------------------------------
HEALTHY_PEER=""
i=0
while [ "${i}" -lt "${REPLICAS}" ]; do
  if [ "${i}" -ne "${ORDINAL}" ]; then
    PEER="${FULLNAME}-${i}.${HEADLESS_SVC}.${NAMESPACE}.svc.cluster.local"
    if valkey-cli ${AUTH_OPT} -h "${PEER}" cluster info 2>/dev/null | grep -q "cluster_state:ok"; then
      HEALTHY_PEER="${PEER}"
      log "found healthy peer: ${HEALTHY_PEER}"
      break
    fi
  fi
  i=$((i + 1))
done

# ---------------------------------------------------------------------------
# Path 1 — REJOIN
# ---------------------------------------------------------------------------
if [ -n "${HEALTHY_PEER}" ]; then
  log "REJOIN path: cluster already exists"

  # 1. Forget any stale `myIP-as-failed` entry on the healthy peer
  STALE_ID=$(valkey-cli ${AUTH_OPT} -h "${HEALTHY_PEER}" cluster nodes 2>/dev/null \
              | awk -v ip="${POD_IP}:6379" '$2 ~ ip && /fail/ {print $1; exit}')
  if [ -n "${STALE_ID}" ]; then
    log "forgetting stale failed entry ${STALE_ID} for ${POD_IP}:6379"
    valkey-cli ${AUTH_OPT} --cluster call "${HEALTHY_PEER}:6379" cluster forget "${STALE_ID}" >/dev/null 2>&1 || true
    sleep 3
  fi

  # 2. Resolve peer hostname to IP, then CLUSTER MEET
  PEER_IP=$(getent hosts "${HEALTHY_PEER}" | awk '{print $1; exit}')
  if [ -z "${PEER_IP}" ]; then
    err "could not resolve healthy peer ${HEALTHY_PEER}"
    exit 1
  fi
  log "CLUSTER MEET ${HEALTHY_PEER} (${PEER_IP})"
  valkey-cli ${AUTH_OPT} -h localhost cluster meet "${PEER_IP}" 6379 >/dev/null
  sleep 5

  # 3. Find an orphaned/under-replicated primary; become its replica
  MY_NODE_ID=$(valkey-cli ${AUTH_OPT} -h localhost cluster myid)
  log "my node ID: ${MY_NODE_ID}"

  TARGET_MASTER_ID=$(valkey-cli ${AUTH_OPT} -h "${HEALTHY_PEER}" cluster nodes 2>/dev/null \
    | awk -v rep="${REPLICAS_PER_PRIMARY}" -v me="${MY_NODE_ID}" '
        /master/ && !/fail/ { masters[$1] = 1 }
        /slave/  && !/fail/ { slave_count[$4] = (slave_count[$4] ? slave_count[$4] : 0) + 1 }
        END {
          for (m in masters) {
            if (m == me) { continue }
            count = slave_count[m] + 0
            if (count < rep) { print m; exit }
          }
        }
      ')

  if [ -n "${TARGET_MASTER_ID}" ]; then
    log "becoming replica of ${TARGET_MASTER_ID}"
    if valkey-cli ${AUTH_OPT} -h localhost cluster replicate "${TARGET_MASTER_ID}"; then
      log "CLUSTER REPLICATE OK"
      exit 0
    else
      err "CLUSTER REPLICATE failed for target ${TARGET_MASTER_ID}"
      exit 1
    fi
  fi

  log "no under-replicated primary; staying as a master with no slots"
  log "requesting --cluster rebalance --cluster-use-empty-masters"
  valkey-cli ${AUTH_OPT} --cluster rebalance "${HEALTHY_PEER}:6379" \
    --cluster-use-empty-masters --cluster-yes || \
    err "rebalance failed; manual intervention may be needed"
  exit 0
fi

# ---------------------------------------------------------------------------
# Path 2 — BOOTSTRAP (ordinal 0)
# ---------------------------------------------------------------------------
if [ "${ORDINAL}" = "0" ]; then
  log "BOOTSTRAP path: no healthy cluster found; this pod will create it"

  NODES=""
  i=0
  while [ "${i}" -lt "${REPLICAS}" ]; do
    PEER="${FULLNAME}-${i}.${HEADLESS_SVC}.${NAMESPACE}.svc.cluster.local"
    log "waiting for ${PEER} to PING (timeout ${PEER_PING_TIMEOUT}s)"
    WAITED=0
    until valkey-cli ${AUTH_OPT} -h "${PEER}" ping 2>/dev/null | grep -q PONG; do
      if [ "${WAITED}" -ge "${PEER_PING_TIMEOUT}" ]; then
        err "peer ${PEER} did not respond within ${PEER_PING_TIMEOUT}s"
        exit 1
      fi
      sleep 2
      WAITED=$((WAITED + 2))
    done
    NODES="${NODES} ${PEER}:6379"
    i=$((i + 1))
  done

  log "all ${REPLICAS} peers responsive; sleeping ${PRE_CREATE_SLEEP}s for CoreDNS to settle"
  sleep "${PRE_CREATE_SLEEP}"

  log "creating cluster: ${PRIMARIES} primaries × ${REPLICAS_PER_PRIMARY} replicas"
  # shellcheck disable=SC2086  # word splitting is intentional for $NODES
  echo "yes" | valkey-cli ${AUTH_OPT} --cluster create ${NODES} \
    --cluster-replicas "${REPLICAS_PER_PRIMARY}"
  log "cluster bootstrapped"
  exit 0
fi

# ---------------------------------------------------------------------------
# Path 3 — WAIT (ordinal > 0, no healthy cluster yet)
# ---------------------------------------------------------------------------
log "WAIT path: ordinal ${ORDINAL} waits for pod-0 to bootstrap"
PRIMARY="${FULLNAME}-0.${HEADLESS_SVC}.${NAMESPACE}.svc.cluster.local"
WAITED=0
until valkey-cli ${AUTH_OPT} -h "${PRIMARY}" cluster info 2>/dev/null | grep -q "cluster_state:ok"; do
  if [ "${WAITED}" -ge "${WAIT_FOR_BOOTSTRAP_TIMEOUT}" ]; then
    err "pod-0 did not declare cluster_state:ok within ${WAIT_FOR_BOOTSTRAP_TIMEOUT}s"
    exit 1
  fi
  log "waiting for pod-0 to bootstrap..."
  sleep 5
  WAITED=$((WAITED + 5))
done
log "cluster bootstrapped by pod-0; my role assigned by --cluster create"
exit 0
