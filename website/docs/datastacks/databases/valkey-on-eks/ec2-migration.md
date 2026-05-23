---
title: EC2 → EKS Migration
sidebar_position: 4
---

# Self-Managed Valkey/Redis on EC2 → EKS Migration

Move a self-managed Valkey or Redis instance running on EC2 (or any other host) onto this stack's EKS **replication-mode** cluster. Two paths are supported:

- **[Approach A — RDB through S3](#approach-a--rdb-through-s3).** Pause writes, BGSAVE, upload to S3, restore via an initContainer. Brief write freeze (5–30 min for ≤ 50 GiB); works across accounts, regions, and restricted networks.
- **[Approach B — Live PSYNC replication](#approach-b--live-psync-replication).** EKS pod becomes a temporary replica of EC2 via `REPLICAOF`, streams writes live, promotes on cutover. Cutover window is **seconds**, but requires direct network reach EKS → EC2 and source RAM headroom.

If your target is cluster mode (sharded), neither approach applies directly — see [Cluster Mode → Migration from Replication Mode](./cluster-mode.md#migration-from-replication-mode), which uses `valkey-cli --cluster import`.

:::warning Production-safety reminder
**Approach A is destructive to the target** — it wipes the target's PVCs before restore. Read the entire runbook once before executing. If the target is already serving production data, use the [Already-serving target](#already-serving-target) flow.

**Approach B is non-destructive** until cutover, but loads the source primary's RAM. Don't run it against a source already > 70% memory-utilized.
:::

## Choose your approach

| Constraint | Approach A: RDB via S3 | Approach B: Live PSYNC |
|---|---|---|
| **Cutover downtime** | 5–30 min for ≤ 50 GiB; scales linearly | Seconds |
| **Network path** | Both sides → S3 | EKS pod → EC2 on TCP `:6379`, low-latency, no firewall between |
| **Cross-account / cross-region** | ✓ | ✗ (needs VPC peering / TGW) |
| **Source RAM headroom** | Not required | **Required** — primary buffers writes in `repl-backlog-size` during sync |
| **Version skew (Redis 6 → Valkey 9)** | ✓ RDB format compat | Strict — PSYNC needs matching major |
| **Cluster-mode target** | ✗ Use [`--cluster import`](./cluster-mode.md#migration-from-replication-mode) | ✗ Same |
| **Network blip mid-migration** | Retry the upload | Source backlog may overflow → full resync restart |
| **Operational complexity** | Higher (S3 + IAM + initContainer) | Lower (one `REPLICAOF` command) — but unforgiving |
| **Best when** | Production data, regulated network, > 50 GiB, source memory-tight, cross-region | Same-VPC, < 50 GiB, source has RAM headroom, comfortable debugging engine state |

**If you can't decide:** start with Approach A. The downtime window is annoying but the failure modes are well-understood and you can rehearse against a copied RDB. Approach B is faster but unforgiving.

For asymmetric networks, key-pattern filtering, or rate-limited migrations, [**RedisShake**](#variant-redisshake) is the hardened-tool variant of Approach B.

## Compatibility matrix

| Source | Target Valkey image | Notes |
|---|---|---|
| Redis 7.2.x | Valkey 9.0.x (default) | Supported. RDB compatible. |
| Redis 7.0.x | Valkey 9.0.x | Supported. RDB v11 → v12 forward-compat. |
| Redis 6.2.x | Valkey 9.0.x | Supported. Test with a copy first. |
| Redis ≤ 6.0 | Valkey 9.0.x | RDB version mismatch likely. Pin matching-major Valkey image first, then upgrade — or use `--cluster import`. |
| Valkey 7.2.x / 8.x → 9.0.x | Valkey 9.0.x | Native, no concerns. |
| Bitnami chart Valkey | Valkey 9.0.x | RDB compatible. Re-issue any chart-specific ACL on the target. |

To check the source's RDB format version:

```bash
xxd -l 9 -c 9 /var/lib/valkey/dump.rdb | head -1
# 00000000: 5245 4449 5330 3031 32  REDIS0012
# Trailing 4 bytes = format version (0012 = v12)
```

## Approach A — RDB through S3

### Architecture

```
┌──────────────────────┐                  ┌─────────── EKS valkey-on-eks ──────────────┐
│   EC2 source host    │   1. BGSAVE      │                                            │
│                      │ ─────────────►   │  2. helm-values flip RESTORE_ENABLED=true  │
│  ┌────────────────┐  │   2. aws s3 cp   │                                            │
│  │ Valkey/Redis   │  │ ────────────────►│   ┌──────────── valkey-0 pod ──────────┐   │
│  │  (running)     │  │                  │   │  initContainer: restore-rdb        │   │
│  │ /var/lib/.../  │  │                  │   │  ├─ aws s3 cp s3://bucket/...      │   │
│  │   dump.rdb     │  │                  │   │  └─ mv → /data/dump.rdb            │   │
│  └────────────────┘  │                  │   │  Valkey starts → loads dump.rdb    │   │
└──────────────────────┘                  │   │  → role: master                    │   │
                                          │   └────────────────────────────────────┘   │
                                          │   replicas (valkey-1..3) full-sync via     │
                                          │   PSYNC from the new primary               │
                                          └────────────────────────────────────────────┘
                                                  │
                                                  ▼  3. apps cut over to
                                                     valkey.valkey.svc..:6379
```

The Terraform-provisioned `valkey-migration` S3 bucket is the staging area (AES-256 SSE, public-access blocks on). The restore initContainer authenticates via Pod Identity (`valkey-sa` → `<cluster>-valkey-restore-s3` IAM role) — no AWS keys in pod spec.

### Pre-flight checks

Run all of these before touching anything.

#### 1. Source state and compatibility

```bash
valkey-cli INFO server | grep -E '^(redis_version|valkey_version|process_id):'
valkey-cli INFO keyspace                # which DBs hold data
valkey-cli DBSIZE                        # key count (current db, default db0)
valkey-cli INFO memory | grep '^used_memory_human:'
valkey-cli INFO persistence | grep -E '^(rdb_last_save_time|aof_enabled):'
valkey-cli LASTSAVE
ls -lh /var/lib/valkey/dump.rdb
```

**Write down** `DBSIZE`, `used_memory_human`, and the version — you'll cross-check after the restore.

**Multi-DB warning.** If `INFO keyspace` shows keys in `db1`+, only `db0` migrates cleanly. Consolidate to `db0` first or switch to cluster mode with hash tags.

#### 2. Target stack readiness

```bash
export KUBECONFIG=$(pwd)/kubeconfig.yaml
kubectl get nodes -l NodeGroupType=valkey
kubectl -n valkey get pods               # expect: valkey-0..3 2/2 Running
kubectl -n argocd get application valkey \
  -o jsonpath='sync={.status.sync.status} health={.status.health.status}'
```

#### 3. Migration bucket + Pod Identity

The restore initContainer fails with `403 Forbidden` if Pod Identity isn't associated. Verify **before** flipping anything:

```bash
BUCKET=$(terraform -chdir=data-stacks/valkey-on-eks/terraform/_local \
           output -raw valkey_migration_bucket)
aws s3 ls "s3://${BUCKET}/"               # bucket reachable

CLUSTER_NAME=$(terraform -chdir=data-stacks/valkey-on-eks/terraform/_local \
                output -raw cluster_name)
aws eks list-pod-identity-associations \
  --cluster-name "$CLUSTER_NAME" --namespace valkey --service-account valkey-sa \
  --query 'associations[0].roleArn'
# Expect: arn ending with /<cluster>-valkey-restore-s3
```

If association is empty, re-run `cd data-stacks/valkey-on-eks && ./deploy.sh`.

#### 4. Network reachability — both directions

```bash
# (a) EC2 → S3 (on the EC2 host)
aws s3 ls "s3://${BUCKET}/" --region us-west-2

# (b) EKS pod → S3 (via Pod Identity)
kubectl -n valkey exec valkey-0 -c valkey -- sh -c \
  "aws --region us-west-2 s3 ls s3://${BUCKET}/ 2>&1 | head -3"
```

Fix Pod Identity / S3 VPC endpoint if (b) fails — otherwise the restore step will fail half-way.

### Downtime strategy

Writes that arrive after BGSAVE starts are lost on cutover. Pick one:

| Strategy | How | Trade-off |
| --- | --- | --- |
| **App-level pause** | Stop the app's write loops; reads continue | Cleanest, needs app coordination |
| **Network drop** | Remove TCP 6379 ingress in the source's SG | Hard cut, drops reads too |
| **`CLIENT PAUSE … WRITE`** | Valkey 7+ / Redis 7+ — surgical write-pause | Reads continue; ~30 min cap; broken by network blips |
| **Live tail + replay** | Replay missed writes from your source-of-truth log post-cutover | Only if you have such a log (Kafka, DDB stream) |

:::danger Do NOT use `REPLICAOF <unreachable-host> 0`
A few old runbooks suggest this to force read-only. `REPLICAOF` takes a real `host port`; port `0` is invalid in Valkey 7.0+. Use one of the four strategies above.
:::

### Step-by-step

#### Step 0 — Rehearse with a copy (recommended)

If the dataset is large or this is your first run, rehearse against a copy of the EC2 source. Restore a recent `dump.rdb` into `/var/lib/valkey-test/dump.rdb`, point a sandbox `valkey-server` at it, then run the migration end-to-end into a **test** S3 bucket. Catches RDB-version, ACL, and TLS surprises with zero prod risk.

#### Step 1 — Back up the source RDB locally

Before BGSAVE on prod, snapshot whatever `dump.rdb` already exists. If BGSAVE fails or corrupts state, this is your roll-back.

```bash
sudo cp -p /var/lib/valkey/dump.rdb \
  /var/lib/valkey/dump.rdb.pre-migration.$(date +%s)
```

#### Step 2 — Back up the target (only if non-empty)

Skip for a freshly deployed target. For an [already-serving target](#already-serving-target), at minimum snapshot it before the wipe:

```bash
PASS=$(kubectl -n valkey get secret valkey-auth -o jsonpath='{.data.default}' | base64 -d)
kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli -a "$PASS" --no-auth-warning BGSAVE
sleep 5
kubectl -n valkey cp -c valkey valkey-0:/data/dump.rdb /tmp/target-pre-migration.rdb
aws s3 cp /tmp/target-pre-migration.rdb \
  "s3://${BUCKET}/pre-migration-backups/$(date +%Y%m%d-%H%M%S)/dump.rdb"
```

#### Step 3 — Stop writes on the source

Apply your [downtime strategy](#downtime-strategy). Verify writes have stopped by sampling a known key for ~10 s.

#### Step 4 — BGSAVE and upload to S3

The bundled script captures `LASTSAVE`, issues `BGSAVE`, polls until it advances, verifies the local file, uploads to S3, and HEAD-verifies the upload:

```bash
export REDISCLI_AUTH="$(sudo cat /etc/valkey/auth)"

./data-stacks/valkey-on-eks/examples/migration/ec2-bgsave-to-s3.sh \
  --host valkey.internal.example.com \
  --port 6379 \
  --s3-bucket "${BUCKET}" \
  --s3-prefix valkey-migration \
  --rdb-path /var/lib/valkey/dump.rdb \
  --timeout-seconds 1800
```

Uploads to `s3://${BUCKET}/valkey-migration/dump.rdb` — **no shard ordinal** (the optional `--shard N` flag is only for cluster-mode migrations).

Exit codes: `0` = OK; `1` = source/BGSAVE error; `2` = S3 error; `64` = bad args; `127` = missing tool.

**Checkpoint** — confirm what's in S3:

```bash
aws s3 ls "s3://${BUCKET}/valkey-migration/dump.rdb"
```

#### Step 5 — Enable the restore initContainer

The initContainer is **always rendered** in the StatefulSet but gated by `RESTORE_ENABLED`. Edit `infra/terraform/helm-values/valkey.yaml` — find `extraInitContainers[0].env` and flip three values:

```yaml
extraInitContainers:
  - name: restore-rdb
    env:
      - name: RESTORE_ENABLED
        value: "true"             # was "false"
      - name: S3_BUCKET
        value: "valkey-on-eks-valkey-migration-XXXX"   # was "" — your $BUCKET
      - name: S3_PREFIX
        value: "valkey-migration"
      - name: ON_MISSING
        value: "fail"             # `fail` = block startup if object missing
```

`ON_MISSING: fail` is correct for a migration — if S3 has no object, the pod stays in `Init:Error` rather than starting empty. Use `skip` only for fresh deploys that should never need restore.

#### Step 6 — Trigger the restore

Recycle the StatefulSet so pods start on empty PVCs and the initContainer runs:

```bash
kubectl -n valkey scale statefulset valkey --replicas=0
kubectl -n valkey wait --for=delete pod -l app.kubernetes.io/name=valkey --timeout=2m
kubectl -n valkey delete pvc -l app.kubernetes.io/name=valkey
cd data-stacks/valkey-on-eks && ./deploy.sh
kubectl -n valkey scale statefulset valkey --replicas=4
```

:::warning
Steps 1–3 wipe existing Valkey data. The Step 2 backup is your only rollback artefact — keep it until the migration is verified stable.
:::

#### Step 7 — Watch the restore

```bash
kubectl -n valkey logs valkey-0 -c restore-rdb -f
# restore: checking s3://.../valkey-migration/dump.rdb
# restore: downloading 4823184 bytes to /data/dump.rdb.partial
# restore: placed dump.rdb (4823184 bytes) at /data/dump.rdb

kubectl -n valkey logs valkey-0 -c valkey | grep -E '(Loading RDB|Ready to accept|DB loaded)'
# * Loading RDB produced by version 9.0.2
# * Done loading RDB, keys loaded: 12345
# * Ready to accept connections tcp
```

For replicas (`valkey-1..3`), the same initContainer downloads the same RDB (wasteful but correct), then the chart's startup re-issues `REPLICAOF valkey-0...` and each replica full-syncs from the restored primary over the local network.

#### Step 8 — Validate

```bash
PASS=$(kubectl -n valkey get secret valkey-auth -o jsonpath='{.data.default}' | base64 -d)

# Replication health
kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli -a "$PASS" --no-auth-warning \
  INFO replication | grep -E '^(role|connected_slaves|slave[0-9]+):'
# expect: role:master · connected_slaves:3 · slaveN state=online lag=0

# Key count matches the source
kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli -a "$PASS" --no-auth-warning DBSIZE

# Spot-check known keys
for K in user:42:profile order:9001 session:abc123; do
  kubectl -n valkey exec valkey-0 -c valkey -- \
    valkey-cli -a "$PASS" --no-auth-warning GET "$K"
done
```

**Checkpoint — do not cut over if any of these fail:**

- `DBSIZE` matches the source to within ~0.1% (TTL drift accounts for tiny mismatches).
- All three replicas `state=online`, `lag ≤ 1`.
- Spot-check keys return expected values.

If `DBSIZE` is off by > 1%, see [Troubleshooting](#troubleshooting).

#### Step 9 — Cut over

| Path | EKS endpoint |
|---|---|
| Writes | `valkey.valkey.svc.cluster.local:6379` |
| Reads (load-balanced) | `valkey-read.valkey.svc.cluster.local:6379` |

For applications outside the EKS cluster, expose `valkey` via a `LoadBalancer` Service or NLB.

The target's ACL passwords differ from the source's (Terraform generates fresh ones):

```bash
kubectl -n valkey get secret valkey-auth -o jsonpath='{.data.default}' | base64 -d
```

Roll applications one at a time and monitor error rates + `valkey-cli INFO stats | grep instantaneous_ops_per_sec`.

#### Step 10 — Disable the restore initContainer

Once stable, flip `RESTORE_ENABLED` back to `"false"` in `helm-values/valkey.yaml` and re-apply. Prevents accidental re-restore on future pod restarts. The S3 object stays in the bucket; see [Cleanup](#cleanup).

### Rollback (Approach A)

If Step 8 validation fails, do not cut over:

- **Script failed (Steps 4–5).** No target data touched. Fix and re-run, or abandon and stay on EC2.
- **Restore succeeded but data is wrong (Step 8).** Either re-run the migration with a corrected source RDB (re-do Steps 1–7), or restore the Step 2 target backup (`aws s3 cp /tmp/target-pre-migration.rdb s3://${BUCKET}/valkey-migration/dump.rdb`, then redo Step 6).
- **Already cut over but data issues found.** Roll app config back to EC2 (source still has its data — you only paused writes). Re-attempt later.

In all three, the Step 1 source-local backup is the safety net.

### Already-serving target

If the EKS cluster is already serving production and you cannot wipe its PVCs:

**Safer option** — bring up a parallel target in a different namespace, migrate cleanly, swap traffic. The chart accepts a `--namespace` override.

**In-place option** — restore only `valkey-0` (against a freshly-deleted PVC), keep replicas, fail over to swap which dataset wins:

```bash
PASS=$(kubectl -n valkey get secret valkey-auth -o jsonpath='{.data.default}' | base64 -d)

# 1. BACKUP first (Step 2 above — do not skip)

# 2. Promote a replica so the primary is free to be the recovery target
kubectl -n valkey exec valkey-1 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning REPLICAOF NO ONE
# Re-point writers at valkey-1 temporarily.

# 3. BGSAVE + upload (Step 4 above, unchanged).
# 4. Flip RESTORE_ENABLED=true (Step 5 above, unchanged).

# 5. Delete only valkey-0's PVC + pod
kubectl -n valkey delete pvc data-valkey-0
kubectl -n valkey delete pod valkey-0
# StatefulSet recreates valkey-0 with empty PVC → initContainer downloads RDB →
# Valkey loads it → valkey-0 is the RESTORED primary.

# 6. Promote valkey-0 back; valkey-1 returns to replica
kubectl -n valkey exec valkey-1 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning \
    REPLICAOF valkey-0.valkey-headless.valkey.svc.cluster.local 6379

# 7. Other replicas full-sync from the new primary; validate (Step 8); cut over (Step 9).
```

More moving parts — use only when you must preserve the existing cluster's data up to the swap moment.

## Approach B — Live PSYNC replication

The EKS pod becomes a temporary replica of the EC2 source: source streams its RDB plus subsequent writes; you cut over with `REPLICAOF NO ONE` once `master_repl_offset` converges. Cutover is **seconds**, but every condition in the [decision matrix](#choose-your-approach) needs to hold for the duration of the sync — which can be hours for a large dataset.

### Architecture

```
┌──────────── EC2 source ─────────────┐    ┌──────── EKS valkey-on-eks ────────┐
│                                     │    │                                   │
│  Valkey/Redis primary (prod)        │    │   ┌──── valkey-0 ────┐            │
│  fork → BGSAVE → RDB → wire stream  ├───►│   │ REPLICAOF        │            │
│  repl-backlog buffer (RAM)          ├───►│   │   <ec2-ip> 6379  │            │
│  live command stream                ├───►│   │ master_link:up   │            │
│                                     │    │   └──────────────────┘            │
└─────────────────────────────────────┘    │           │ at cutover            │
                                           │           ▼                       │
                                           │   REPLICAOF NO ONE → primary      │
                                           │   replicas (1..3) PSYNC from it   │
                                           └───────────────────────────────────┘
```

### Pre-flight checks (in addition to [Approach A's Step 1](#1-source-state-and-compatibility))

#### 1. Source RAM headroom

The source's BGSAVE forks (CoW doubles RAM under heavy writes) **and** every write during the sync sits in the replication backlog. Both come out of source RAM.

```bash
valkey-cli INFO memory | grep -E '^(used_memory_human|maxmemory_human):'
valkey-cli CONFIG GET repl-backlog-size       # default 1 MB — too small for prod
valkey-cli INFO replication | grep -E '^(role|connected_slaves):'
```

Headroom needed ≈ `(used_memory × 1.5) + (peak_write_rate × sync_duration)`. As a heuristic: 30 GiB working set needs ≥ 60 GiB source RAM.

**If source is > 70% memory-utilized in steady state, use Approach A instead.** PSYNC will OOM the source.

#### 2. Bump `repl-backlog-size` on the source

The 1 MB default fills in seconds during a real migration. When it overflows, PSYNC falls back to **full resync** — another fork + RDB stream from scratch.

```bash
# Size for ~10 min of writes at peak rate. Example: 100k writes/s × 256 B = 25 MB/s × 600 s ≈ 15 GB.
valkey-cli CONFIG SET repl-backlog-size 16gb
valkey-cli CONFIG REWRITE     # persist to valkey.conf
```

For > 50 GiB datasets, initial sync alone can take 10–30 min. Size the backlog for the **full sync duration**, not just steady-state lag.

#### 3. Network — EKS pod → EC2 on TCP 6379

```bash
# Get EKS pod CIDRs and open the source SG to them on 6379
EKS_VPC=$(aws eks describe-cluster --name <cluster> --query 'cluster.resourcesVpcConfig.vpcId' --output text)
aws ec2 describe-vpcs --vpc-ids "$EKS_VPC" \
  --query 'Vpcs[0].CidrBlockAssociationSet[].CidrBlock' --output text

# Probe from inside the cluster
kubectl -n valkey run conn-probe --rm -i -t --restart=Never \
  --image=docker.io/valkey/valkey:9.0.2 -- \
  valkey-cli -h <ec2-private-ip> -p 6379 -a <source-password> ping
# Expect: PONG
```

Latency matters. Same-VPC is the supported case; cross-VPC peering works but extends full-sync wall-clock.

#### 4. Source `bind` directive

```bash
grep -E '^bind' /etc/valkey/valkey.conf
# bind 0.0.0.0 -::*    OK
# bind 127.0.0.1        BAD — replica can't connect
# bind <vpc-ip>         OK if reachable from EKS pod CIDR
```

To loosen without restart (preserves in-memory state): `valkey-cli CONFIG SET bind "0.0.0.0 -::*" && valkey-cli CONFIG REWRITE`.

#### 5. Auth and TLS alignment

This is where most live-replication migrations fall over.

```bash
valkey-cli CONFIG GET requirepass
valkey-cli CONFIG GET masterauth
valkey-cli CONFIG GET tls-port
```

The EKS replica must hold:

- The source's password as `masterauth` (Valkey ≤ 7) or `primaryauth` (Valkey 8+). The chart's `replica-replication-user-password` doesn't apply here — the source's password does.
- The source's TLS CA bundle if the source listens on `tls-port`. Mount the CA and set `tls-replication yes`.

ACL state from the source **is** replicated via the PSYNC stream (writes including `ACL SETUSER` flow through), so you don't need to manually export/re-issue ACLs. But ensure the source's `default` (or whichever user the chart connects as) has the necessary permissions on both ends after `REPLICAOF NO ONE`.

If auth doesn't line up, the replica logs show a tight loop of `Error reading sync metadata` or `NOAUTH Authentication required`. Fix and retry.

### Step-by-step (Approach B)

#### Step 1 — Make valkey-0 a replica of EC2

The upstream `valkey-io/valkey-helm` chart does **not** expose a config knob to point at an external primary at chart-render time — it bakes `REPLICAOF valkey-0.valkey-headless... 6379` into the replica pods' config. The right approach is to bring up the StatefulSet empty and reconfigure at runtime:

```bash
# Clear any existing target data
kubectl -n valkey scale statefulset valkey --replicas=0
kubectl -n valkey delete pvc -l app.kubernetes.io/name=valkey

# Bring up only valkey-0; it starts as a standalone primary
kubectl -n valkey scale statefulset valkey --replicas=1
kubectl -n valkey wait --for=condition=Ready pod/valkey-0 --timeout=300s

# Set the source's password as masterauth, then issue REPLICAOF.
# These changes are runtime; CONFIG REWRITE would persist them but the
# chart-managed valkey.conf reverts on pod restart — that's fine for a one-time
# migration: don't restart the pod until cutover.
TARGET_PASS=$(kubectl -n valkey get secret valkey-auth -o jsonpath='{.data.default}' | base64 -d)

kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli \
  -a "$TARGET_PASS" --no-auth-warning \
  CONFIG SET masterauth "$SOURCE_PASS"

kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli \
  -a "$TARGET_PASS" --no-auth-warning \
  REPLICAOF "$EC2_SOURCE_IP" 6379
```

#### Step 2 — Watch the initial sync

```bash
kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli \
  -a "$TARGET_PASS" --no-auth-warning INFO replication
# role:slave
# master_link_status:up                       ← critical
# master_sync_in_progress:1 → 0               ← flips to 0 when initial sync done
# master_last_io_seconds_ago: <small>         ← steady stream healthy
# master_repl_offset: <large monotonic>       ← matches source's repl_offset
```

Tail `kubectl -n valkey logs valkey-0 -c valkey -f` in another window — expect clear `MASTER <-> REPLICA sync started` → `Full resync from master` → `MASTER <-> REPLICA sync: Finished with success`. Any `NOAUTH`, `Connection refused`, or `Loading RDB produced by version` means a pre-flight check missed something — fix and retry.

For > 10 GiB initial sync, expect 100 Mbps – 1 Gbps wall-clock depending on instance type and topology.

#### Step 3 — Validate before cutover

Once `master_sync_in_progress=0` and `master_link_status=up`:

```bash
# DBSIZE match
kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli -a "$TARGET_PASS" --no-auth-warning DBSIZE
ssh ec2-user@$EC2_SOURCE_IP -- valkey-cli -a "$SOURCE_PASS" DBSIZE

# repl_offset within ~1000 of each other in steady state
kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli -a "$TARGET_PASS" --no-auth-warning \
  INFO replication | grep -E 'master_repl_offset|slave_repl_offset'

# Sample-key match
KEYS=$(ssh ec2-user@$EC2_SOURCE_IP -- valkey-cli -a "$SOURCE_PASS" --scan | shuf -n 5)
for k in $KEYS; do
  src=$(ssh ec2-user@$EC2_SOURCE_IP -- valkey-cli -a "$SOURCE_PASS" GET "$k")
  dst=$(kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli -a "$TARGET_PASS" --no-auth-warning GET "$k")
  [[ "$src" == "$dst" ]] && echo "OK   $k" || echo "DIFF $k"
done
```

If any sample differs, force a fresh full resync by re-running `REPLICAOF` and investigate the network/auth path.

#### Step 4 — Quiesce writes and final lag check

```bash
# Pause writes on the source (reads continue)
ssh ec2-user@$EC2_SOURCE_IP -- valkey-cli -a "$SOURCE_PASS" CLIENT PAUSE 30000 WRITE

# Confirm replica caught up to the byte
kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli \
  -a "$TARGET_PASS" --no-auth-warning INFO replication | grep master_repl_offset
ssh ec2-user@$EC2_SOURCE_IP -- valkey-cli -a "$SOURCE_PASS" \
  INFO replication | grep master_repl_offset
```

#### Step 5 — Promote the EKS replica

```bash
kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli \
  -a "$TARGET_PASS" --no-auth-warning REPLICAOF NO ONE
# role:master
```

#### Step 6 — Bring up replicas

```bash
kubectl -n valkey scale statefulset valkey --replicas=4
kubectl -n valkey wait --for=condition=Ready pod/valkey-1 --timeout=300s
# valkey-1..3 auto-issue REPLICAOF valkey-0... per the chart's startup; they
# PSYNC from valkey-0 (which now holds the migrated dataset).

kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli \
  -a "$TARGET_PASS" --no-auth-warning INFO replication | grep -E '^(connected_slaves|slave[0-9]):'
# expect: connected_slaves:3 with all three state=online lag=0
```

#### Step 7 — Cut over

Same as [Approach A, Step 9](#step-9--cut-over). Update apps to point at `valkey.valkey.svc.cluster.local:6379` for writes, `valkey-read...` for reads.

#### Step 8 — Decommission the source

After ≥ 24 h (preferably ≥ 1 week) of stable EKS operation:

```bash
ssh ec2-user@$EC2_SOURCE_IP -- valkey-cli -a "$SOURCE_PASS" CLIENT KILL TYPE normal
ssh ec2-user@$EC2_SOURCE_IP -- valkey-cli -a "$SOURCE_PASS" BGSAVE
ssh ec2-user@$EC2_SOURCE_IP -- aws s3 cp /var/lib/valkey/dump.rdb \
  s3://your-archive-bucket/valkey-source-final-$(date +%Y%m%d).rdb --storage-class GLACIER
# Stop and terminate the EC2 instance per your standard process
```

### Rollback (Approach B)

1. **Before `REPLICAOF NO ONE`** — easy. The source is still authoritative. Run `REPLICAOF NO ONE` on the EKS pod just to detach (so it stops chasing the source), wipe PVCs, retry.
2. **After `REPLICAOF NO ONE`, before app cutover** — EKS pod is now an independent primary holding a stale snapshot; source has resumed serving writes. Resume traffic on EC2; later, redo Approach A from a fresh BGSAVE.
3. **After app cutover** — EKS has writes EC2 doesn't know about. Rolling back loses them. Accept the loss (rare; small datasets only), or don't roll back — debug forward on EKS.

The lesson: **validate aggressively at Step 3**. Once Step 5 happens and the source resumes writes, options narrow fast.

### Common failure modes

| Symptom | Cause | Fix |
|---|---|---|
| `Replica bio thread: Error reading sync metadata` loop | Auth mismatch — replica didn't `CONFIG SET masterauth` | Set `masterauth` on the replica to the source's password |
| `MASTER aborted replication with an error: NOAUTH` | Same as above | Same |
| Initial sync runs forever | `repl-backlog-size` too small → backlog overflows → full-resync loop | Raise `repl-backlog-size` on source (pre-flight Step 2) |
| `master_link_status: down` flapping | Network instability / SG drop | `mtr` from pod to source; verify SG rule on source |
| `Loading RDB produced by version X.Y.Z, my version is A.B.C` | Source RDB version newer than target | Pin matching-major Valkey image first, then upgrade after migration |
| Replica's `master_repl_offset` < source's by constant amount | Replica can't keep up with write rate | More CPU on the replica, or accept lag and wait |

### Variant: RedisShake

[**RedisShake**](https://github.com/tair-opensource/RedisShake) is a hardened, external implementation of PSYNC + offline RDB + key-level filtering. **Prefer it over a hand-rolled `REPLICAOF`** when:

- Asymmetric / firewalled network (RedisShake initiates from the target side).
- Filter by DB number, key pattern, or data type (`allow_key_prefix = ["user:", "session:"]`).
- Rate-limiting (don't saturate the source NIC).
- Need to survive transient network blips without full-resync (RedisShake buffers to disk).
- Cross-version migrations where RDB-format compatibility is in question (uses key-level `DUMP`/`RESTORE`, not raw RDB stream).

Skeleton config:

```toml
# redisshake.toml
[sync_reader]
  cluster = false
  address = "<ec2-source-ip>:6379"
  password = "<source-password>"
  sync_rdb = true
  sync_aof = true

[redis_writer]
  cluster = false
  address = "valkey.valkey.svc.cluster.local:6379"
  password = "<target-password>"

[filter]
  allow_db = [0]
  # allow_key_prefix = ["user:", "session:"]
```

Deploy as a Kubernetes Job using `ghcr.io/tair-opensource/redisshake:latest` with the config mounted from a ConfigMap. The Job logs progress and exits when caught up. Most hand-rolled `REPLICAOF` migrations evolve into a RedisShake migration on the second attempt — start with it.

## Cleanup

After ≥ 24 h of stable operation:

```bash
# Delete the migration RDB (one-time staging artefact)
aws s3 rm "s3://${BUCKET}/valkey-migration/dump.rdb"
aws s3 rm "s3://${BUCKET}/pre-migration-backups/" --recursive

# Optional: 30-day expiry lifecycle rule for future runs
aws s3api put-bucket-lifecycle-configuration --bucket "${BUCKET}" --lifecycle-configuration '{
  "Rules": [{
    "ID": "valkey-migration-30d-expire",
    "Status": "Enabled",
    "Filter": {"Prefix": "valkey-migration/"},
    "Expiration": {"Days": 30}
  }]
}'

# Verify restore initContainer is disabled
kubectl -n valkey get statefulset valkey -o jsonpath='{.spec.template.spec.initContainers[0].env}' | \
  python3 -m json.tool | grep -A1 RESTORE_ENABLED
# expect: "value": "false"
```

## Troubleshooting

### `valkey-0` stays `Init:Error`

```bash
kubectl -n valkey logs valkey-0 -c restore-rdb
```

| Symptom | Cause | Fix |
|---|---|---|
| `restore: object missing at s3://…/valkey-migration/dump.rdb` | Script wrote to a sharded key (used `--shard 0` → `…/0/dump.rdb`) | Re-upload without `--shard`, or `aws s3 mv` the existing object to `…/dump.rdb` |
| `restore: object missing` (and bucket is right) | `S3_BUCKET` or `S3_PREFIX` typo in helm-values | Compare against the migration script's `Uploaded object` line |
| `aws s3 cp` fails with `403 Forbidden` | Pod Identity not associated, or IAM policy missing the bucket | Re-check Pre-flight Step 3 |
| `dial tcp: lookup s3.amazonaws.com` | CoreDNS or VPC S3 endpoint issue | Check S3 Gateway endpoint + CoreDNS logs |
| `restore: size mismatch — expected=X actual=Y` | Source RDB modified mid-upload | Re-stop source writes; re-run the migration script |
| `restore: existing dump.rdb found … skipping` | PVC wasn't deleted before re-trigger | Scale to 0, delete PVCs, scale back up |

### Replicas stuck syncing

```bash
for i in 1 2 3; do
  kubectl -n valkey logs valkey-$i -c valkey | grep -E '(MASTER|sync|psync|fullsync)' | tail -10
done
```

- **`Master is currently unable to PSYNC but should be in the future`** — primary rejecting writes during a save. Wait for `LASTSAVE` to advance.
- **`Trying a partial resynchronization (request 0)` repeatedly** — backlog exhausted. Force a fresh full sync: `kubectl -n valkey delete pod valkey-1`.
- **PSYNC succeeds but `lag` stuck > 0** — primary write rate exceeds replica apply rate. Check application isn't double-targeting.

### `DBSIZE` doesn't match source

Within 0.1% drift is normal (TTLs). Beyond that:

- **Multi-DB source**: only `db0` migrated. Run `INFO keyspace` on both sides and compare.
- **Encoding accounting**: `used_memory_human` can differ 10–30% between Redis 6 and Valkey 9 (`listpack` vs `ziplist` for small structures). **Not** data loss — `OBJECT ENCODING <key>` and `GET <key>` confirm.
- **AOF tail held writes not in RDB**: if source has `appendonly yes` and BGSAVE coincided with heavy writes, some recent writes live in AOF only. Mitigation: pause writes longer pre-BGSAVE, or `BGREWRITEAOF` first.

## References

- [Valkey persistence docs](https://valkey.io/topics/persistence/) — RDB / AOF semantics.
- [Valkey replication](https://valkey.io/topics/replication/) — PSYNC + backlog tuning.
- [Valkey CLIENT PAUSE](https://valkey.io/commands/client-pause/) — write-pause command.
- [AWS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html) — how the restore initContainer authenticates to S3.
- [Replication mode runbook](./replication.md) — primary/replica health checks referenced above.
- [Cluster mode migration](./cluster-mode.md#migration-from-replication-mode) — for sharded target instead.
- [RedisShake](https://github.com/tair-opensource/RedisShake) — external PSYNC implementation.
