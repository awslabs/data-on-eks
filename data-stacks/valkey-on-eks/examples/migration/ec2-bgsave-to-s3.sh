#!/usr/bin/env bash
#
# ec2-bgsave-to-s3.sh
#
# Pre-migration script: snapshots a self-managed Valkey/Redis instance on an
# EC2 source host via BGSAVE and uploads the resulting RDB to S3 so that the
# valkey-on-eks restore initContainer can pick it up.
#
# Run this script ON the source EC2 host (or any host that has network reach
# to the source Valkey, plus `redis-cli` and the AWS CLI installed). It does
# NOT need to run inside Kubernetes.
#
# Usage:
#   ./ec2-bgsave-to-s3.sh \
#       --host valkey.internal.example.com \
#       --port 6379 \
#       --password "$(cat /etc/valkey/auth)" \
#       --s3-bucket my-valkey-migration-bucket \
#       --s3-prefix valkey-migration \
#       --shard 0 \
#       --rdb-path /var/lib/valkey/dump.rdb \
#       --timeout-seconds 1800
#
# After upload, edit infra/terraform/helm-values/valkey.yaml so that:
#     restore:
#       enabled: true
#       s3Bucket: my-valkey-migration-bucket
#       s3Prefix: valkey-migration
#       onMissing: fail
# then re-run ./deploy.sh in the data-stacks/valkey-on-eks/ overlay.
#
# Validates: Requirements 8.2, 8.6

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
HOST=""
PORT="6379"
PASSWORD=""
S3_BUCKET=""
S3_PREFIX="valkey-migration"
SHARD="0"
RDB_PATH="/var/lib/valkey/dump.rdb"
TIMEOUT_SECONDS="1800"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
usage() {
    cat <<'USAGE'
Usage: ec2-bgsave-to-s3.sh [options]

Required:
  --host HOST            Source Valkey/Redis hostname or IP.
  --s3-bucket BUCKET     Destination S3 bucket name (no s3:// prefix).

Optional:
  --port PORT            Source Valkey port. Default: 6379.
  --password PASSWORD    AUTH password. If omitted, REDISCLI_AUTH env var is used.
  --s3-prefix PREFIX     Key prefix under the bucket. Default: valkey-migration.
  --shard ORDINAL        Source shard ordinal (0-based). Default: 0.
  --rdb-path PATH        Local path where BGSAVE writes the RDB.
                         Default: /var/lib/valkey/dump.rdb.
  --timeout-seconds N    Max seconds to wait for LASTSAVE to advance.
                         Default: 1800 (30 minutes).
  -h, --help             Show this message.

The resulting object key is:
  s3://<bucket>/<prefix>/<shard>/dump.rdb

NOTE: The password is NEVER passed on the redis-cli command line. It is
exported as REDISCLI_AUTH so that it does not appear in the host's process
list.
USAGE
}

log() {
    printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

err() {
    printf '[%s] ERROR: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            HOST="${2:-}"
            shift 2
            ;;
        --port)
            PORT="${2:-}"
            shift 2
            ;;
        --password)
            PASSWORD="${2:-}"
            shift 2
            ;;
        --s3-bucket)
            S3_BUCKET="${2:-}"
            shift 2
            ;;
        --s3-prefix)
            S3_PREFIX="${2:-}"
            shift 2
            ;;
        --shard)
            SHARD="${2:-}"
            shift 2
            ;;
        --rdb-path)
            RDB_PATH="${2:-}"
            shift 2
            ;;
        --timeout-seconds)
            TIMEOUT_SECONDS="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            err "Unknown flag: $1"
            usage >&2
            exit 64
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
if [[ -z "$HOST" ]]; then
    err "--host is required"
    usage >&2
    exit 64
fi
if [[ -z "$S3_BUCKET" ]]; then
    err "--s3-bucket is required"
    usage >&2
    exit 64
fi
if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
    err "--port must be an integer, got: $PORT"
    exit 64
fi
if ! [[ "$SHARD" =~ ^[0-9]+$ ]]; then
    err "--shard must be a non-negative integer, got: $SHARD"
    exit 64
fi
if ! [[ "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || [[ "$TIMEOUT_SECONDS" -le 0 ]]; then
    err "--timeout-seconds must be a positive integer, got: $TIMEOUT_SECONDS"
    exit 64
fi

# Password resolution: prefer --password flag; fall back to REDISCLI_AUTH env var.
if [[ -n "$PASSWORD" ]]; then
    export REDISCLI_AUTH="$PASSWORD"
elif [[ -n "${REDISCLI_AUTH:-}" ]]; then
    : # already exported by the caller
else
    err "No password provided. Pass --password or set REDISCLI_AUTH."
    exit 64
fi

# Tool availability.
for tool in redis-cli aws stat; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        err "Required tool '$tool' is not on PATH"
        exit 127
    fi
done

# Strip trailing slash from prefix so we never produce a double slash in the key.
S3_PREFIX="${S3_PREFIX%/}"
S3_KEY="${S3_PREFIX}/${SHARD}/dump.rdb"
S3_URI="s3://${S3_BUCKET}/${S3_KEY}"

# ---------------------------------------------------------------------------
# Pre-flight: downtime guidance
# ---------------------------------------------------------------------------
cat <<BANNER
==============================================================================
 Valkey/Redis EC2 -> S3 pre-migration snapshot
------------------------------------------------------------------------------
 Source host         : ${HOST}:${PORT}
 Shard ordinal       : ${SHARD}
 Local RDB path      : ${RDB_PATH}
 Destination         : ${S3_URI}
 BGSAVE timeout      : ${TIMEOUT_SECONDS}s
==============================================================================

DOWNTIME GUIDANCE
  BGSAVE produces a point-in-time snapshot. Any writes that arrive AFTER
  BGSAVE starts will NOT be in the resulting dump.rdb and will be LOST when
  you cut over to the EKS-hosted cluster.

  Recommended: stop write traffic to the source (firewall, application
  config, or readonly mode) BEFORE running this script. Reads can continue.

BANNER

# ---------------------------------------------------------------------------
# 1. Capture LASTSAVE
# ---------------------------------------------------------------------------
log "Capturing LASTSAVE before BGSAVE..."
if ! BEFORE="$(redis-cli -h "$HOST" -p "$PORT" LASTSAVE)"; then
    err "redis-cli LASTSAVE failed against ${HOST}:${PORT}"
    exit 1
fi
if ! [[ "$BEFORE" =~ ^[0-9]+$ ]]; then
    err "Unexpected LASTSAVE response: '$BEFORE'"
    exit 1
fi
log "LASTSAVE before BGSAVE = ${BEFORE}"

# ---------------------------------------------------------------------------
# 2. Trigger BGSAVE
# ---------------------------------------------------------------------------
log "Issuing BGSAVE..."
if ! BGSAVE_REPLY="$(redis-cli -h "$HOST" -p "$PORT" BGSAVE)"; then
    err "redis-cli BGSAVE failed"
    exit 1
fi
if [[ "$BGSAVE_REPLY" != "Background saving started" ]]; then
    err "Unexpected BGSAVE reply: '${BGSAVE_REPLY}'"
    exit 1
fi
log "BGSAVE accepted: ${BGSAVE_REPLY}"

# ---------------------------------------------------------------------------
# 3. Poll LASTSAVE until it advances or we time out
# ---------------------------------------------------------------------------
log "Polling LASTSAVE every 5s (timeout ${TIMEOUT_SECONDS}s)..."
DEADLINE=$((SECONDS + TIMEOUT_SECONDS))
NOW="$BEFORE"
while (( SECONDS < DEADLINE )); do
    if ! NOW="$(redis-cli -h "$HOST" -p "$PORT" LASTSAVE)"; then
        err "redis-cli LASTSAVE failed during poll"
        exit 1
    fi
    if [[ "$NOW" =~ ^[0-9]+$ ]] && (( NOW > BEFORE )); then
        log "LASTSAVE advanced: ${BEFORE} -> ${NOW}"
        break
    fi
    sleep 5
done

if ! [[ "$NOW" =~ ^[0-9]+$ ]] || (( NOW <= BEFORE )); then
    err "BGSAVE timeout - LASTSAVE did not advance within ${TIMEOUT_SECONDS}s"
    exit 1
fi

# ---------------------------------------------------------------------------
# 4. Verify local RDB exists and is non-empty
# ---------------------------------------------------------------------------
if [[ ! -f "$RDB_PATH" ]]; then
    err "RDB file not found at ${RDB_PATH} after BGSAVE completed"
    exit 1
fi

# Linux: stat -c %s; macOS: stat -f %z. Try GNU first, fall back to BSD.
if LOCAL_SIZE="$(stat -c %s "$RDB_PATH" 2>/dev/null)"; then
    :
elif LOCAL_SIZE="$(stat -f %z "$RDB_PATH" 2>/dev/null)"; then
    :
else
    err "Unable to stat ${RDB_PATH}"
    exit 1
fi
if ! [[ "$LOCAL_SIZE" =~ ^[0-9]+$ ]] || (( LOCAL_SIZE == 0 )); then
    err "RDB file at ${RDB_PATH} is empty (size=${LOCAL_SIZE})"
    exit 1
fi
log "Local RDB size: ${LOCAL_SIZE} bytes"

# ---------------------------------------------------------------------------
# 5. Upload to S3
# ---------------------------------------------------------------------------
log "Uploading ${RDB_PATH} -> ${S3_URI}"
if ! aws s3 cp "$RDB_PATH" "$S3_URI" --no-progress; then
    err "aws s3 cp failed"
    exit 2
fi

# ---------------------------------------------------------------------------
# 6. Verify upload via HEAD
# ---------------------------------------------------------------------------
log "Verifying upload via HEAD..."
if ! REMOTE_SIZE="$(aws s3api head-object --bucket "$S3_BUCKET" --key "$S3_KEY" --query 'ContentLength' --output text)"; then
    err "aws s3api head-object failed for ${S3_URI}"
    exit 2
fi
if [[ "$REMOTE_SIZE" != "$LOCAL_SIZE" ]]; then
    err "Size mismatch: local=${LOCAL_SIZE} remote=${REMOTE_SIZE}"
    exit 2
fi
log "Remote ContentLength matches local size (${REMOTE_SIZE} bytes)"

# ---------------------------------------------------------------------------
# 7. Final summary
# ---------------------------------------------------------------------------
cat <<SUMMARY
==============================================================================
 SUCCESS
------------------------------------------------------------------------------
 Source host         : ${HOST}:${PORT}
 Shard ordinal       : ${SHARD}
 Uploaded object     : ${S3_URI}
 Object size         : ${REMOTE_SIZE} bytes

 NEXT STEP
   Edit infra/terraform/helm-values/valkey.yaml in your data stack:

       restore:
         enabled: true
         s3Bucket: ${S3_BUCKET}
         s3Prefix: ${S3_PREFIX}
         onMissing: fail

   Then apply the EKS deploy:

       cd data-stacks/valkey-on-eks && ./deploy.sh

   Pods will run the restore initContainer on first boot, downloading
   dump.rdb from the matching s3://${S3_BUCKET}/${S3_PREFIX}/<ordinal>/dump.rdb
   key for each shard.
==============================================================================
SUMMARY
