---
title: EC2 → EKS Migration
sidebar_position: 4
---

# Self-Managed Valkey/Redis on EC2 → EKS Migration

Move a self-managed Valkey or Redis instance running on EC2 (or any other host) onto the EKS-hosted **replication-mode** cluster. This document covers two paths:

- **[Approach A — RDB through S3](#approach-a--rdb-through-s3).** Stop writes on the source, BGSAVE, upload to S3, restore on the target via an initContainer. Works in restricted networks, across accounts, and across regions; this stack ships the IAM, S3 bucket, and initContainer for it. Trade-off: a brief write freeze (5–30 minutes for ≤ 50 GiB on gp3, scales linearly).
- **[Approach B — Live PSYNC replication](#approach-b--live-psync-replication).** EKS pod becomes a temporary replica of the EC2 source over `REPLICAOF`, streams writes live, then promotes on cutover. Cutover window is **seconds**. Trade-off: requires a low-latency network path EKS → EC2, source RAM headroom for the replication backlog, and matching auth/TLS config.

Both paths converge on the same end state — Valkey on EKS holding all the source data, replicas back-filling, application traffic cut over. Pick based on your network topology, RAM headroom, and downtime budget. There is a [decision matrix below](#choose-your-migration-approach).

:::warning Production-safety reminder
**Approach A is destructive to the target cluster on the happy path** — it deletes the target's PVCs before restoring. **Read the entire doc once before running anything.** Capture the source's `DBSIZE` and `used_memory_human` first; you will cross-check them after the restore. If your target cluster is already serving production data, jump to [Already-serving target](#already-serving-target) — the destructive path is wrong for you.

**Approach B is non-destructive on both ends** until you run `REPLICAOF NO ONE` at cutover, but it places sustained read load on the source primary during the initial sync. Do not run it on a source whose primary is already > 70% memory-utilized.
:::

## Which migration is this?

| Target topology | Use |
| --- | --- |
| **Replication mode** (this stack's default: 1 primary + N replicas in the `valkey` namespace) | **This document.** |
| **Cluster mode** (sharded, in the `valkey-cluster` namespace) | See [Cluster Mode → Migration from Replication Mode](./cluster-mode.md#migration-from-replication-mode). The cluster-mode path uses `valkey-cli --cluster import` from a temporary pod, not RDB-through-S3. |

## Choose your migration approach

| Constraint / requirement | Approach A: RDB through S3 | Approach B: Live PSYNC |
|---|---|---|
| **Cutover downtime** | 5–30 min for ≤ 50 GiB; scales linearly | Seconds |
| **Network path** | Both sides → S3 (egress to AWS endpoints) | EKS pod → EC2 on TCP `:6379`, low-latency, no firewall in the middle |
| **Cross-account / cross-region** | ✓ Works as long as both sides can reach the S3 bucket | ✗ Requires VPC peering / TGW with sec-group rules |
| **Source RAM headroom** | Not required (BGSAVE happens once) | **Required** — primary buffers writes in `repl-backlog-size` until lag = 0; OOM risk if source already > 70% memory |
| **Source TLS / auth** | Not in scope (RDB is local-disk-then-S3) | Replica must hold `masterauth`/`primaryauth`, and CA bundle if source uses TLS |
| **Network blip mid-migration** | No source impact; re-upload and retry | Source primary backlog grows; long blips force a full resync (more source CPU + RAM) |
| **Cluster mode target** | ✗ Use [`--cluster import`](./cluster-mode.md#migration-from-replication-mode) instead | ✗ PSYNC puts every key on shard 0; same redirect to `--cluster import` |
| **Rehearse against a copy first** | ✓ Easy — copy the RDB to a test bucket, run the same flow | Possible but fiddly — needs a test EC2 instance |
| **Operational complexity** | Higher: S3 + IAM + initContainer + Pod Identity | Lower: one `REPLICAOF` command on a healthy network |
| **Best when…** | Production data, regulated network, > 50 GiB working set, source already memory-tight, or any cross-account/region work | Same VPC, < 50 GiB, source has RAM headroom, ops team comfortable debugging engine state under time pressure |

**If you can't decide:** start with Approach A. The downtime window is annoying but the failure modes are well-understood and you can rehearse against a copied RDB. Approach B is faster but unforgiving.

There is a third option many teams gravitate to:

- **[RedisShake](https://github.com/tair-opensource/RedisShake)** — a hardened, external implementation of PSYNC plus offline-RDB plus key-level filtering. **Strongly recommend it over a hand-rolled `REPLICAOF`** when your network is asymmetric, when you want to filter by DB/keyspace pattern, when you need rate-limiting, or when you simply don't want to debug engine-level replication state. Covered in [Approach B → RedisShake variant](#variant-redisshake).

## Approach A — RDB through S3

The remainder of this section (when to use it, compatibility, architecture, pre-flight, downtime strategy, step-by-step) is the runbook for Approach A. Skip to [Approach B](#approach-b--live-psync-replication) if you've decided to use live PSYNC instead.

### When to use Approach A

- **Source**: a single Valkey or Redis instance running on EC2 (or any host with network reach to AWS S3) — any version compatible with the target's Valkey image, see the [compatibility matrix](#compatibility-matrix) below.
- **Target**: this stack's EKS replication cluster — freshly deployed (recommended) **or** already-serving with the [Already-serving target flow](#already-serving-target).
- **Downtime budget**: source write traffic must pause from BGSAVE start until cutover. **Expect 5–30 minutes for datasets up to ~50 GiB on gp3.** Larger datasets scale roughly linearly with S3 ↔ EBS download throughput.
- **Network**: the EC2 source must reach S3 in the target AWS region. The EKS pods must reach the migration bucket via Pod Identity. See [Pre-flight checks](#pre-flight-checks).

## Compatibility matrix

| Source | Target Valkey image | Notes |
|---|---|---|
| Redis 7.2.x | Valkey 9.0.x (default) | Supported. RDB format compatible. |
| Redis 7.0.x | Valkey 9.0.x | Supported. RDB version 11 → 12 forward compatible. |
| Redis 6.2.x | Valkey 9.0.x | Supported. Test with a copy first ([Step 0](#step-0--rehearse-with-a-copy-recommended)). |
| Redis ≤ 6.0 | Valkey 9.0.x | RDB version mismatch likely. Either pin a Valkey image of the matching major before migrating then upgrade, or use `valkey-cli --cluster import` (key-level migration, no RDB compat needed). |
| Valkey 7.2.x → 9.0.x | Valkey 9.0.x | Native, no compatibility concerns. |
| Bitnami chart Valkey | Valkey 9.0.x | RDB compatible. ACL config is chart-specific — re-issue ACL on the target. |

To check the source's RDB format version:

```bash
xxd -l 9 -c 9 /var/lib/valkey/dump.rdb | head -1
# 00000000: 5245 4449 5330 3031 32                       REDIS0012
# 5245 4449 53 = "REDIS"; the trailing four bytes are the format version (0012 = v12)
```

## Architecture

```
┌──────────────────────┐                  ┌─────────── EKS valkey-on-eks ──────────────┐
│   EC2 source host    │   1. BGSAVE      │                                            │
│                      │ ─────────────►   │  2. helm-values flip RESTORE_ENABLED=true  │
│  ┌────────────────┐  │   2. aws s3 cp   │                                            │
│  │ Valkey/Redis   │  │ ────────────────►│   ┌──────────── valkey-0 pod ──────────┐   │
│  │  (running)     │  │                  │   │  initContainer: restore-rdb        │   │
│  │ /var/lib/.../  │  │                  │   │  ├─ aws s3 cp s3://bucket/...      │   │
│  │   dump.rdb     │  │                  │   │  └─ mv → /data/dump.rdb            │   │
│  └────────────────┘  │                  │   │                                    │   │
│                      │                  │   │  Valkey starts → loads dump.rdb    │   │
└──────────────────────┘                  │   │  → role: master                    │   │
                                          │   └────────────────────────────────────┘   │
                                          │                                            │
                                          │   replicas (valkey-1..3) sync from new     │
                                          │   primary via PSYNC (full sync)            │
                                          └────────────────────────────────────────────┘
                                                  │
                                                  ▼
                                          3. apps cut over to valkey.valkey.svc..:6379
```

The Terraform-provisioned `valkey-migration` S3 bucket is the staging area, with AES-256 SSE and all four public-access blocks enabled. The restore initContainer authenticates to S3 via Pod Identity (the `valkey-sa` ServiceAccount → `<cluster>-valkey-restore-s3` IAM role), so no AWS keys live in the pod spec or Helm values.

## Pre-flight checks

Run **all** of these before you touch anything. A red flag here is much cheaper than a failed cutover.

### 1. Source state and compatibility

```bash
# On the EC2 source host
valkey-cli INFO server | grep -E '^(redis_version|valkey_version|os|process_id):'
valkey-cli INFO keyspace                # confirms which DBs (db0, db1, ...) hold data
valkey-cli DBSIZE                        # key count in the CURRENT db (default db0)
valkey-cli INFO memory | grep -E '^(used_memory_human|used_memory_peak_human|maxmemory_human):'
valkey-cli INFO persistence | grep -E '^(rdb_last_save_time|rdb_last_bgsave_status|aof_enabled):'
valkey-cli LASTSAVE
ls -lh /var/lib/valkey/dump.rdb
```

**Write down**:

- `DBSIZE` (and the value for each db if you're using multiple).
- `used_memory_human`.
- `redis_version` / `valkey_version`.

**Multi-DB warning.** If `INFO keyspace` shows keys in `db1`, `db2`, … only `db0` migrates cleanly to the target (the target chart does not partition databases). If you have multi-DB data, consolidate into `db0` on the source first (or use cluster mode with hash tags).

**AOF interaction.** The source's `BGSAVE` always produces an RDB regardless of `appendonly yes`. The target loads `dump.rdb` on startup only when there is **no AOF file** in `/data` (which is the case on a freshly-deleted PVC — exactly what this runbook does).

### 2. Target stack readiness

```bash
# From a host with kubectl + AWS access to the target cluster
export KUBECONFIG=$(pwd)/kubeconfig.yaml

# Cluster reachable
kubectl get nodes -l NodeGroupType=valkey

# All 4 replication-mode pods up
kubectl -n valkey get pods
# expect: valkey-0..3 with 2/2 Running

# ArgoCD app Synced + Healthy
kubectl -n argocd get application valkey \
  -o jsonpath='sync={.status.sync.status} health={.status.health.status}'
```

### 3. Target migration bucket exists

```bash
BUCKET=$(terraform -chdir=data-stacks/valkey-on-eks/terraform/_local \
           output -raw valkey_migration_bucket)
echo "Migration bucket: $BUCKET"

# Bucket must be reachable and writeable from the host you'll run the script on
aws s3 ls "s3://${BUCKET}/" 2>&1
echo "Pre-migration bucket content (should be empty or only prior runs):"
aws s3 ls "s3://${BUCKET}/" --recursive
```

### 4. Pod Identity is wired up

The restore initContainer reads S3 via Pod Identity. Verify the association exists **before** touching helm values — otherwise the initContainer will fail with `403 Forbidden` and you'll be debugging a half-done migration:

```bash
CLUSTER_NAME=$(terraform -chdir=data-stacks/valkey-on-eks/terraform/_local \
                output -raw cluster_name)

aws eks list-pod-identity-associations \
  --cluster-name "$CLUSTER_NAME" \
  --namespace valkey \
  --service-account valkey-sa \
  --query 'associations[0].{Sa:serviceAccount,Role:roleArn}'
# Expect: an association whose roleArn ends with /<cluster>-valkey-restore-s3
```

If empty, run `cd data-stacks/valkey-on-eks && ./deploy.sh` to reconcile Terraform — the association is created from `infra/terraform/valkey.tf`.

### 5. Network reachability — both directions

```bash
# (a) EC2 source → S3 in the target region
#     (run on the EC2 host)
aws s3 ls "s3://${BUCKET}/" --region us-west-2 || \
  echo "EC2 source cannot reach S3 — check IAM role, security group egress, VPC endpoints"

# (b) EKS pods → S3 via Pod Identity
#     (run via kubectl exec on any existing valkey pod; uses the same SA)
kubectl -n valkey exec valkey-0 -c valkey -- sh -c '
  apk add --no-cache aws-cli >/dev/null 2>&1 || true
  aws --region us-west-2 s3 ls "s3://'"${BUCKET}"'/" 2>&1 | head -3
' || echo "(if `apk` is not available, run a one-off aws-cli pod instead — see Troubleshooting)"
```

If (b) fails, the migration will fail at restore time. Fix Pod Identity / the S3 VPC endpoint before going further.

## Decide your downtime strategy

Any writes that arrive **after** BGSAVE starts on the source are not in the resulting `dump.rdb` and will be lost on cutover. Pick one:

| Strategy | How | Trade-off |
| --- | --- | --- |
| **Application-level pause** | Stop your app's write loops; reads can continue against the source. | Cleanest. Requires app-level coordination. |
| **Network drop** | Remove TCP 6379 ingress in the source's security group (drops all clients, including reads). | Hard cut. Fastest. |
| **`CLIENT PAUSE`** | `valkey-cli CLIENT PAUSE <ms> WRITE` — pauses WRITE clients (Valkey 7+ / Redis 7+). | Surgical (reads still work), but the pause cap is ~30 min and a network blip ends the pause. |
| **Live tail + replay** | Accept that writes during the BGSAVE window are lost; replay them post-cutover from your app's source-of-truth log. | Use only when you have such a log (Kafka, DynamoDB stream, etc.). |

:::danger Do NOT use `REPLICAOF <unreachable-host> 0`
A few old runbooks suggest making the source a "replica of nowhere" to force read-only. `REPLICAOF` takes a real `host port`; port `0` is invalid in Valkey 7.0+ and may be silently accepted in older Redis with surprising behavior. Use one of the four strategies above.
:::

## Step-by-step migration

### Step 0 — Rehearse with a copy (recommended)

If your dataset is large or this is your first run, rehearse against a **copy** of the EC2 source before touching production:

```bash
# On a sandbox EC2 host:
# 1. Restore a recent dump.rdb from your backups into /var/lib/valkey-test/dump.rdb
# 2. Run valkey-server pointed at that directory
# 3. Run the migration end-to-end against this copy, into a TEST migration bucket
```

This catches RDB version surprises, ACL / TLS issues, and AOF mismatches without risking prod. Skip only if you've migrated this exact source ↔ target pair before.

### Step 1 — Backup the source RDB locally

Before BGSAVE on prod, make a local backup of whatever `dump.rdb` the source already has. If BGSAVE fails or corrupts state, you can roll back.

```bash
SRC_DIR=/var/lib/valkey                            # adjust to your install
sudo cp -p "${SRC_DIR}/dump.rdb" "${SRC_DIR}/dump.rdb.pre-migration.$(date +%s)"
sudo ls -lh "${SRC_DIR}"/dump.rdb*
```

### Step 2 — Backup the target's existing data (only if non-empty)

Skip this step for a freshly deployed target. If your target is already serving production data — see [Already-serving target](#already-serving-target) for the full alternate flow, but at minimum take a snapshot **before** you wipe PVCs:

```bash
PASS=$(kubectl -n valkey get secret valkey-auth -o jsonpath='{.data.default}' | base64 -d)

# 1. Trigger BGSAVE on the current primary so dump.rdb on the PV is fresh.
kubectl -n valkey exec valkey-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning BGSAVE
sleep 5
kubectl -n valkey exec valkey-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning LASTSAVE

# 2. Copy the RDB out of the pod to a safe location.
kubectl -n valkey cp -c valkey \
  valkey-0:/data/dump.rdb \
  /tmp/target-pre-migration.rdb
ls -lh /tmp/target-pre-migration.rdb

# 3. Optional: upload to S3 as well.
aws s3 cp /tmp/target-pre-migration.rdb \
  "s3://${BUCKET}/pre-migration-backups/$(date +%Y%m%d-%H%M%S)/dump.rdb"
```

### Step 3 — Stop writes on the source

Apply your chosen [downtime strategy](#decide-your-downtime-strategy). Verify writes have stopped by sampling a known key on the source and confirming it doesn't change for ~10 seconds.

### Step 4 — BGSAVE and upload to S3

The bundled script handles the full sequence: capture `LASTSAVE`, issue `BGSAVE`, poll until `LASTSAVE` advances, verify the local file, upload to S3, verify the upload via `head-object`.

Run on the EC2 source (or any host with `valkey-cli` / `redis-cli` + the AWS CLI):

```bash
# Either pass --password explicitly, or export REDISCLI_AUTH first.
# Prefer the env var — it keeps the password out of the host's process list.
export REDISCLI_AUTH="$(sudo cat /etc/valkey/auth)"

./data-stacks/valkey-on-eks/examples/migration/ec2-bgsave-to-s3.sh \
  --host valkey.internal.example.com \
  --port 6379 \
  --s3-bucket "${BUCKET}" \
  --s3-prefix valkey-migration \
  --rdb-path /var/lib/valkey/dump.rdb \
  --timeout-seconds 1800
```

The script uploads to `s3://${BUCKET}/valkey-migration/dump.rdb` — **no shard ordinal** in the path for replication mode. (The optional `--shard N` flag prepends a shard subdirectory; only set it for the cluster-mode migration covered separately.)

Expected output ends with:

```
SUCCESS
 Source host         : valkey.internal.example.com:6379
 Shard ordinal       : <replication-mode, no shard>
 Uploaded object     : s3://valkey-on-eks-valkey-migration-XXXX/valkey-migration/dump.rdb
 Object size         : 4823184 bytes
```

Script exit codes:

| Exit code | Meaning |
|---|---|
| `0` | RDB uploaded and verified |
| `1` | BGSAVE timeout, or source connection failed |
| `2` | S3 upload or HEAD verification failed |
| `64` | Bad arguments |
| `127` | Required tool (`valkey-cli`, `aws`, `stat`) missing |

**Checkpoint** — before proceeding, sanity-check what's in S3:

```bash
aws s3 ls "s3://${BUCKET}/valkey-migration/dump.rdb"
# expect: one line, size matches the source's /var/lib/valkey/dump.rdb
```

### Step 5 — Enable the restore initContainer

The restore initContainer is **always present** in the StatefulSet pod spec (always-emit, runtime-gate pattern). When `RESTORE_ENABLED=false` it `exit 0`s immediately. Flip it on by editing `infra/terraform/helm-values/valkey.yaml` — find the `extraInitContainers[0].env` block and change three values:

```yaml
extraInitContainers:
  - name: restore-rdb
    image: amazon/aws-cli:2.17.0
    env:
      - name: RESTORE_ENABLED
        value: "true"             # was "false"
      - name: AWS_REGION
        value: ${region}
      - name: S3_BUCKET
        value: "valkey-on-eks-valkey-migration-XXXX"   # was ""  (your $BUCKET)
      - name: S3_PREFIX
        value: "valkey-migration"
      - name: ON_MISSING
        value: "fail"
    # … rest unchanged
```

:::note
The doc deliberately shows the actual `extraInitContainers[0].env` structure. There is **no** top-level `restore:` block in this chart — older versions of this runbook referenced one that doesn't exist.
:::

`ON_MISSING` controls behavior when the S3 object is missing:

| Value | Behavior |
|---|---|
| `fail` (recommended for migration) | Exit non-zero. The Valkey container does not start. The pod stays in `Init:Error`. Forces the operator to debug missing data. |
| `skip` | Exit 0. Valkey starts with an empty dataset. Useful for fresh deploys (default new clusters) or for replicas that should sync from the primary, not from S3. |

### Step 6 — Trigger the restore

Recycle the StatefulSet so each pod starts on an empty PVC and the initContainer runs against the new S3 object:

```bash
# 1. Scale to 0 — graceful shutdown of all 4 pods. PDB does not block scale-down.
kubectl -n valkey scale statefulset valkey --replicas=0
kubectl -n valkey wait --for=delete pod -l app.kubernetes.io/name=valkey --timeout=2m

# 2. Delete the PVCs so initContainer lands on an empty /data.
#    (Without this, the initContainer's idempotency check skips the download.)
kubectl -n valkey delete pvc -l app.kubernetes.io/name=valkey

# 3. Apply the updated Helm values via the standard path.
cd data-stacks/valkey-on-eks
./deploy.sh

# 4. Scale back to 4. ArgoCD picks up the new extraInitContainers env on Sync.
kubectl -n valkey scale statefulset valkey --replicas=4
```

:::warning
Steps 1-2 wipe the existing Valkey data. The Step 2 backup (`/tmp/target-pre-migration.rdb`) is your only rollback artefact at this point — keep it until the migration is verified stable.
:::

### Step 7 — Watch the restore

```bash
# Init container logs from the primary pod
kubectl -n valkey logs valkey-0 -c restore-rdb -f
```

Expected output:

```
restore: checking s3://valkey-on-eks-valkey-migration-XXXX/valkey-migration/dump.rdb
restore: downloading 4823184 bytes to /data/dump.rdb.partial
restore: placed dump.rdb (4823184 bytes) at /data/dump.rdb
```

Then the main Valkey container starts, loads `dump.rdb`, and you'll see in `valkey-0`'s log:

```bash
kubectl -n valkey logs valkey-0 -c valkey | grep -E '(Loading RDB|Ready to accept|DB loaded)'
# * Loading RDB produced by version 9.0.2
# * RDB age 27 seconds
# * RDB memory usage when created 12.34 Mb
# * Done loading RDB, keys loaded: 12345, keys expired: 0.
# * DB loaded from disk: 0.045 seconds
# * Ready to accept connections tcp
```

For replicas (`valkey-1..3`), the same initContainer runs (and downloads the same RDB — wasteful but correct), then the chart's startup script issues `REPLICAOF valkey-0...`. Each replica drops its dataset and full-syncs from the freshly-restored primary over the local network.

### Step 8 — Validate

```bash
PASS=$(kubectl -n valkey get secret valkey-auth -o jsonpath='{.data.default}' | base64 -d)

# (a) All 4 pods 2/2 Ready
kubectl -n valkey get pods

# (b) Replication health — primary has 3 connected replicas, all in sync
kubectl -n valkey exec valkey-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning INFO replication | \
  grep -E '^(role|connected_slaves|min_slaves_good_slaves|slave[0-9]+):'
# expect: role:master
#         connected_slaves:3
#         min_slaves_good_slaves:3
#         slave0:ip=...,state=online,lag=0
#         slave1:ip=...,state=online,lag=0
#         slave2:ip=...,state=online,lag=0

# (c) Keyspace size matches the source
kubectl -n valkey exec valkey-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning DBSIZE
# expect: the number you wrote down in Pre-flight Step 1

# (d) Memory size matches (small drift is expected — see Troubleshooting)
kubectl -n valkey exec valkey-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning INFO memory | grep '^used_memory_human:'

# (e) Spot-check a few known keys
for K in user:42:profile order:9001 session:abc123; do
  kubectl -n valkey exec valkey-0 -c valkey -- \
    valkey-cli -a "$PASS" --no-auth-warning GET "$K"
done
```

**Checkpoint — do NOT proceed if any of these fail**:

- `DBSIZE` matches the source to within ~0.1% (TTL expirations during the migration window account for tiny drift).
- `connected_slaves:3` and all three replicas `state=online` with `lag` ≤ 1.
- Spot-check keys return the expected values.

If `DBSIZE` is off by more than 1%, see [Troubleshooting](#troubleshooting). Do not cut over.

### Step 9 — Cut over application traffic

Update your application config to point at the EKS endpoints:

| Path | EKS endpoint |
|---|---|
| Writes | `valkey.valkey.svc.cluster.local:6379` |
| Reads (load-balanced across replicas) | `valkey-read.valkey.svc.cluster.local:6379` |

For applications outside the EKS cluster, expose `valkey` via a `LoadBalancer` Service or an NLB — see `service.type` in `infra/terraform/helm-values/valkey.yaml`.

ACL passwords differ between the EC2 source and the EKS target (Terraform generated fresh passwords for the target). Update your client config:

```bash
# Get the new ACL passwords
kubectl -n valkey get secret valkey-auth -o jsonpath='{.data.default}' | base64 -d
kubectl -n valkey get secret valkey-auth -o jsonpath='{.data.replication-user}' | base64 -d
```

Apply config changes to applications and roll one app at a time. Monitor application error rates and the target's `valkey-cli INFO stats | grep instantaneous_ops_per_sec` for traffic.

### Step 10 — Disable the restore initContainer

Once the cutover is complete and the cluster is stable for at least a few minutes, flip `RESTORE_ENABLED` back to `"false"`:

```yaml
extraInitContainers:
  - name: restore-rdb
    env:
      - name: RESTORE_ENABLED
        value: "false"           # was "true"
```

```bash
cd data-stacks/valkey-on-eks && ./deploy.sh
```

This prevents accidental re-restores on future pod restarts. The initContainer stays in the pod spec but exits 0 immediately. The S3 object stays in the bucket per its Lifecycle rules (see [Cleanup](#cleanup)).

## Rollback

If validation in Step 8 fails, **do not cut over**. Rollback paths from worst to best:

**A. Migration script failed (steps 4–5).** No target data has been touched. Investigate using the script's exit code and S3 contents; either fix and re-run, or abandon and keep using the source.

**B. Restore succeeded but data is wrong (Step 8 mismatch).** The target's current `/data/dump.rdb` is the freshly-restored copy. You have two options:

```bash
# Option 1 — re-run the migration with a corrected source RDB
kubectl -n valkey scale statefulset valkey --replicas=0
kubectl -n valkey wait --for=delete pod -l app.kubernetes.io/name=valkey --timeout=2m
kubectl -n valkey delete pvc -l app.kubernetes.io/name=valkey
# Fix the source (e.g. re-run BGSAVE with no concurrent writers, or fix
# multi-DB consolidation), re-upload, then:
kubectl -n valkey scale statefulset valkey --replicas=4

# Option 2 — restore from the Step 2 backup of the target's pre-migration data
aws s3 cp /tmp/target-pre-migration.rdb \
  "s3://${BUCKET}/valkey-migration/dump.rdb"
# … then redo Step 6 to restore the OLD target data back.
```

**C. Application has cut over but you find data issues.** Roll application config back to the EC2 source. The EC2 source still has its data (you only **stopped writes**, not data). After rolling app config back, decide whether to re-attempt migration later or stay on EC2.

In all three cases, the safety net is the Step 1 source-local backup (`/var/lib/valkey/dump.rdb.pre-migration.<timestamp>`). If the source's working state has been corrupted, copy the backup over `dump.rdb` and restart the EC2 Valkey.

## Already-serving target

If the EKS cluster is already serving production reads/writes and you cannot afford to wipe its PVCs, the steps differ. The idea: restore only `valkey-0` (against a freshly-deleted PVC), keep replicas intact, then let the cluster decide via failover which dataset wins.

The safer variant: bring up a **parallel** target cluster in a different namespace, migrate into it cleanly, then swap traffic. The chart accepts `--namespace` overrides, so a second release is straightforward.

If you must restore into the existing cluster:

```bash
PASS=$(kubectl -n valkey get secret valkey-auth -o jsonpath='{.data.default}' | base64 -d)

# 1. BACKUP the current cluster (do not skip — Step 2 above shows how).

# 2. Promote a replica to primary so writes can pause briefly without the
#    primary being the recovery target.
kubectl -n valkey exec valkey-1 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning REPLICAOF NO ONE
# Update writers to point at valkey-1 (or the read service `valkey-read` if
# you can tolerate stale reads briefly).

# 3. Run BGSAVE on the source EC2 + upload to S3 (Step 4 above, unchanged).

# 4. Flip RESTORE_ENABLED=true in helm-values (Step 5 above, unchanged).
cd data-stacks/valkey-on-eks && ./deploy.sh

# 5. Delete ONLY valkey-0's PVC + pod (not the whole StatefulSet).
kubectl -n valkey delete pvc data-valkey-0
kubectl -n valkey delete pod valkey-0
# The StatefulSet recreates valkey-0 with an empty PVC → the initContainer
# downloads dump.rdb → Valkey starts and loads it → valkey-0 is now the
# RESTORED primary (chart auto-elects ordinal 0 as primary on startup).

# 6. Promote valkey-0 back to primary; valkey-1 demotes to replica.
kubectl -n valkey exec valkey-1 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning REPLICAOF valkey-0.valkey-headless.valkey.svc.cluster.local 6379

# 7. The replicas (valkey-1..3) will full-sync from valkey-0's new dataset —
#    their existing data is wiped during the sync. Watch:
for i in 1 2 3; do
  kubectl -n valkey logs valkey-$i -c valkey --tail=20 | grep -E '(sync|psync|MASTER)'
done

# 8. Re-validate (Step 8) and cut over (Step 9).
```

This flow has more moving parts than the destructive flow. Use it only when the existing cluster has data you want to preserve up to the moment of the swap.

## Approach B — Live PSYNC replication

This approach establishes a temporary **primary → replica** relationship across the wire: the EKS pod becomes a replica of the EC2 source, the source streams its current state plus all subsequent writes to the EKS pod, and you cut over with `REPLICAOF NO ONE` once `master_repl_offset` matches.

The cutover window is **seconds**. The trade-off is operational fragility — every condition in the [decision matrix](#choose-your-migration-approach) needs to hold for the duration of the migration, which can be hours for a large dataset.

### Architecture

```
┌──────────────────── EC2 source host ────────────────────┐    ┌──────────── EKS valkey-on-eks ────────────┐
│                                                         │    │                                           │
│  ┌─────────────────────────┐                            │    │   ┌─────── valkey-0 pod ─────────┐        │
│  │  Valkey/Redis primary   │   1. PSYNC handshake       │    │   │                              │        │
│  │   serving prod traffic  │ ─────────────────────────► │    │   │  Valkey 9.0.x, configured    │        │
│  │                         │                            │    │   │  as a replica via:           │        │
│  │  fork → BGSAVE → RDB    │   2. RDB stream (one-shot) │    │   │  REPLICAOF <ec2-ip> 6379     │        │
│  │  → wire stream          │ ─────────────────────────► │    │   │                              │        │
│  │                         │                            │    │   │  Loads RDB → role=slave      │        │
│  │  repl-backlog buffer    │   3. live command stream   │    │   │  Streams writes from primary │        │
│  │  (ring buffer, RAM)     │ ─────────────────────────► │    │   │  master_link_status: up      │        │
│  │                         │                            │    │   │                              │        │
│  └─────────────────────────┘                            │    │   └──────────────────────────────┘        │
│                                                         │    │              │ at cutover               │
└─────────────────────────────────────────────────────────┘    │              ▼                          │
                                                               │   REPLICAOF NO ONE → role=master         │
                                                               │   replicas (valkey-1..3) PSYNC from it   │
                                                               └──────────────────────────────────────────┘
```

### Pre-flight checks (Approach B specific)

Run **all** of these in addition to the EC2-side state capture from [Approach A's pre-flight](#1-source-state-and-compatibility):

#### 1. Source RAM headroom

The source primary forks for the initial BGSAVE (CoW doubling under heavy write traffic) **and** holds every write that happens during the sync in the replication backlog buffer. Both come out of the source's RAM.

```bash
# On the EC2 source host
valkey-cli INFO memory | grep -E '^(used_memory_human|used_memory_peak_human|maxmemory_human):'
valkey-cli CONFIG GET repl-backlog-size       # default 1 MiB; production should be much larger
valkey-cli INFO replication | grep -E '^(role|connected_slaves|repl_backlog_size):'
```

**Required headroom**: at least `(used_memory × 1.5) + (peak_write_rate_in_bytes × expected_sync_duration_seconds)`. As a rough heuristic, for a 30 GiB working set you want at least 60 GiB of source RAM available, more if the source already has replicas attached.

If the source is > 70% memory-utilized in steady state, **do not use Approach B** — use Approach A instead. PSYNC will OOM the source primary mid-migration.

#### 2. Tune `repl-backlog-size` on the source

The default `repl-backlog-size` of 1 MiB is far too small for a real migration. If the buffer fills before the replica catches up, the source falls back from partial-resync to **full-resync**, which means another fork + RDB stream and the work-so-far is wasted.

```bash
# Size the backlog to hold ~10 minutes of writes at peak rate.
# Example: 100k writes/sec * 256 bytes avg = 25.6 MB/s * 600s = ~15 GB.
# Round up to next power of 2 for efficiency.
valkey-cli CONFIG SET repl-backlog-size 16gb
valkey-cli CONFIG REWRITE     # persist to valkey.conf so it survives restart

# Verify
valkey-cli CONFIG GET repl-backlog-size
```

For datasets > 50 GiB, expect the initial sync alone to take 10–30 minutes. Size the backlog for the **full sync duration plus a buffer**, not just the steady-state lag.

#### 3. Network reachability — EKS pod → EC2

```bash
# (a) Open the source security group to the EKS pod CIDR(s)
EKS_POD_CIDRS=$(aws ec2 describe-vpcs \
  --vpc-ids $(aws eks describe-cluster --name <cluster> --query 'cluster.resourcesVpcConfig.vpcId' --output text) \
  --query 'Vpcs[0].CidrBlockAssociationSet[].CidrBlock' --output text)
echo "EKS pod CIDRs: $EKS_POD_CIDRS"

# Add an inbound rule to the EC2 source SG: TCP 6379 from those CIDRs.

# (b) Probe from a pod
kubectl -n valkey run conn-probe --rm -i -t --restart=Never \
  --image=docker.io/valkey/valkey:9.0.2 -- \
  valkey-cli -h <ec2-private-ip> -p 6379 -a <source-password> ping
# Expect: PONG
```

Latency between the pod and the EC2 source matters. Sustained replication is sensitive to RTT and packet loss. A same-VPC migration is the supported case; cross-VPC peering works but expect higher full-sync wall-clock time.

#### 4. Source `bind` directive

```bash
# On the EC2 source
grep -E '^bind' /etc/valkey/valkey.conf
# bind 0.0.0.0 -::*    OK
# bind 127.0.0.1        BAD — replica cannot connect
# bind 10.0.1.5         OK if 10.0.1.5 is the EC2's VPC IP that the pod CIDR can reach
```

If `bind` is too restrictive, update the config and `valkey-cli SHUTDOWN NOSAVE` then restart — losing the in-memory state would defeat the migration. Instead, edit the config, then `valkey-cli CONFIG SET bind "0.0.0.0 -::*"` followed by `CONFIG REWRITE` to apply without restart.

#### 5. Auth, TLS, and ACL alignment

This is where most live-replication migrations fall over.

```bash
# On the source
valkey-cli CONFIG GET requirepass             # password auth
valkey-cli CONFIG GET masterauth              # for source's own replicas (if any)
valkey-cli CONFIG GET tls-port                # TLS-only, mTLS, or plain?
valkey-cli ACL LIST                            # any non-default users that need to be replicated?
```

The replica (EKS pod) must:

- Hold the source's password in `masterauth` (Valkey ≤ 7.x) or `primaryauth` (Valkey 8+).
- Trust the source's TLS CA if the source listens on `tls-port`. Mount the CA bundle into the pod and set `tls-cluster yes` + `tls-replication yes` on the replica.
- Match the source's ACL configuration if non-default users are in use. ACLs do **not** propagate via `PSYNC` automatically — you must export `ACL LIST` from the source and re-issue on the target after cutover.

If any of these don't line up, PSYNC fails with `NOAUTH Authentication required` or an SSL handshake error. We saw this exact pattern in a recent debug session — the symptom is a tight loop of `Replica bio thread: Error reading sync metadata` in the replica logs.

### Step-by-step (Approach B)

#### Step 1 — Configure the EKS pod as a replica

The official `valkey-io/valkey-helm` chart deploys this stack with all four pods configured as a replication set already (`valkey-0` is primary, `valkey-1..3` are replicas of `valkey-0`). For Approach B, you instead want `valkey-0` to be a replica of the **EC2 source**.

The cleanest way is a temporary helm values override:

```yaml
# Add to infra/terraform/helm-values/valkey.yaml under primary:
primary:
  extraEnvVars:
    - name: VALKEY_MASTER_HOST
      value: "<ec2-source-private-ip>"
    - name: VALKEY_MASTER_PORT_NUMBER
      value: "6379"
    - name: VALKEY_MASTER_PASSWORD
      valueFrom:
        secretKeyRef:
          name: valkey-source-auth
          key: source-password
```

Or, simpler for a one-time migration, do it manually on a freshly-restarted pod:

```bash
# Delete PVCs first so the pod starts empty
kubectl -n valkey scale statefulset valkey --replicas=0
kubectl -n valkey delete pvc -l app.kubernetes.io/name=valkey
kubectl -n valkey scale statefulset valkey --replicas=1   # bring up only valkey-0

# Wait for valkey-0 ready
kubectl -n valkey wait --for=condition=Ready pod/valkey-0 --timeout=300s

# Set the source password as masterauth, then issue REPLICAOF
kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli \
  -a "$TARGET_PASS" --no-auth-warning \
  CONFIG SET masterauth "$SOURCE_PASS"

kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli \
  -a "$TARGET_PASS" --no-auth-warning \
  REPLICAOF "$EC2_SOURCE_IP" 6379
```

#### Step 2 — Watch the initial sync

```bash
# On the EKS replica (valkey-0)
kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli \
  -a "$TARGET_PASS" --no-auth-warning INFO replication

# Look for:
#   role:slave
#   master_link_status:up                      ← critical
#   master_sync_in_progress:1 → 0              ← flips to 0 when initial sync done
#   master_last_io_seconds_ago: <small number> ← steady stream is healthy
#   master_repl_offset: <large monotonic int>  ← matches the source's repl_offset
```

Tail the pod logs in another window — the initial sync produces clear `Loading RDB`, `MASTER <-> REPLICA sync started`, `Full resync from master`, then `MASTER <-> REPLICA sync: Finished with success`. Any `NOAUTH`, `Connection refused`, or `Loading RDB produced by version` messages mean a pre-flight check missed something — fix and retry.

For datasets > 10 GiB, the initial sync's wall-clock time scales with the EC2 → pod network throughput. Expect 100 Mbps to 1 Gbps in practice depending on instance type and AZ topology.

#### Step 3 — Validate before cutover

Once `master_sync_in_progress = 0` and `master_link_status = up`:

```bash
# Compare DBSIZE
kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli -a "$TARGET_PASS" --no-auth-warning DBSIZE
ssh ec2-user@$EC2_SOURCE_IP -- valkey-cli -a "$SOURCE_PASS" DBSIZE

# Compare master_repl_offset — must be within ~1000 of each other in steady state
kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli -a "$TARGET_PASS" --no-auth-warning \
  INFO replication | grep -E 'master_repl_offset|slave_repl_offset'
ssh ec2-user@$EC2_SOURCE_IP -- valkey-cli -a "$SOURCE_PASS" \
  INFO replication | grep master_repl_offset

# Sample 5 random keys on both sides and verify identical values
KEYS=$(ssh ec2-user@$EC2_SOURCE_IP -- valkey-cli -a "$SOURCE_PASS" --scan | shuf -n 5)
for k in $KEYS; do
  src=$(ssh ec2-user@$EC2_SOURCE_IP -- valkey-cli -a "$SOURCE_PASS" GET "$k")
  dst=$(kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli -a "$TARGET_PASS" --no-auth-warning GET "$k")
  [[ "$src" == "$dst" ]] && echo "OK   $k" || echo "DIFF $k: src=$src dst=$dst"
done
```

If any sample differs, do not cut over. Investigate before continuing — usually the source had a write that lost during a brief network blip, and re-running `REPLICAOF` to force a full resync resolves it.

#### Step 4 — Quiesce writes and final lag check

```bash
# On the source — pause writes
ssh ec2-user@$EC2_SOURCE_IP -- valkey-cli -a "$SOURCE_PASS" CLIENT PAUSE 30000 WRITE

# On the replica — wait for full catch-up
kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli \
  -a "$TARGET_PASS" --no-auth-warning INFO replication | grep master_repl_offset
# Confirm matches source's master_repl_offset to the byte
```

`CLIENT PAUSE WRITE` blocks new writes for the specified duration but reads continue serving — applications time-out gracefully or buffer if they're well-behaved. The pause window must be long enough for the final replication lag (typically < 1 second on a healthy network) to drain.

#### Step 5 — Promote the EKS replica

```bash
# Detach from the source
kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli \
  -a "$TARGET_PASS" --no-auth-warning REPLICAOF NO ONE

# Verify
kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli \
  -a "$TARGET_PASS" --no-auth-warning INFO replication | grep '^role:'
# Expect: role:master
```

#### Step 6 — Bring up the rest of the replication set

```bash
# Scale back up — valkey-1..3 will PSYNC from valkey-0 (the new primary)
kubectl -n valkey scale statefulset valkey --replicas=4
kubectl -n valkey wait --for=condition=Ready pod/valkey-1 --timeout=300s
kubectl -n valkey wait --for=condition=Ready pod/valkey-2 --timeout=300s
kubectl -n valkey wait --for=condition=Ready pod/valkey-3 --timeout=300s

# Confirm all three replicas are connected and synced
kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli \
  -a "$TARGET_PASS" --no-auth-warning INFO replication | grep -E '^(connected_slaves|slave[0-9]):'
# Expect: connected_slaves:3 with all three slaveN lines showing state=online lag=0
```

#### Step 7 — Cut over application traffic

Same as [Approach A → Step 9](#step-9--cut-over-application-traffic). Update application config to point at:

- Writes: `valkey.valkey.svc.cluster.local:6379`
- Reads: `valkey-read.valkey.svc.cluster.local:6379`

Roll one application at a time, monitor error rates and `instantaneous_ops_per_sec` on the target.

#### Step 8 — Decommission the source

Once the target has been stable for > 24 hours (recommend > 1 week), proceed with the standard EC2 decommission:

```bash
# Stop the source's writers (if any beyond the migrated app)
ssh ec2-user@$EC2_SOURCE_IP -- valkey-cli -a "$SOURCE_PASS" CLIENT KILL TYPE normal

# Final cold-storage backup
ssh ec2-user@$EC2_SOURCE_IP -- valkey-cli -a "$SOURCE_PASS" BGSAVE
ssh ec2-user@$EC2_SOURCE_IP -- aws s3 cp /var/lib/valkey/dump.rdb \
  s3://your-cold-archive-bucket/valkey-source-final-$(date +%Y%m%d).rdb \
  --storage-class GLACIER

# Stop and terminate the EC2 instance per your standard decommission process
```

### Variant: RedisShake

[RedisShake](https://github.com/tair-opensource/RedisShake) is a hardened, external implementation of the same primary→replica relationship — but it runs as a separate process (or pod) rather than embedding in the engine. **Use it instead of native PSYNC when**:

- You need to filter by DB number, key pattern, or data type (e.g. only migrate keys matching `user:*`).
- You need rate-limiting (don't saturate the source's NIC).
- You want the migration to survive a network blip without falling back to full-resync (RedisShake buffers to disk).
- You need cross-version migrations where RDB format compatibility is in question (RedisShake uses key-level operations, not RDB stream).
- The source uses ACLs and you only want to migrate keys readable by a specific user.

The deployment shape is a one-off Kubernetes Job in the `valkey` namespace that:

1. Connects to the EC2 source (read-only, with credentials).
2. Connects to the EKS pod's primary endpoint (`valkey.valkey.svc.cluster.local:6379`).
3. Streams data from source to target with whatever filters you configured.
4. Logs progress and exits when caught up — at which point you cut over and decommission the source.

A skeleton RedisShake config:

```toml
# redisshake.toml
[sync_reader]
  cluster = false
  address = "<ec2-source-ip>:6379"
  username = ""
  password = "<source-password>"
  tls = false
  sync_rdb = true
  sync_aof = true

[redis_writer]
  cluster = false
  address = "valkey.valkey.svc.cluster.local:6379"
  username = ""
  password = "<target-password>"
  tls = false

[filter]
  allow_db = [0]              # only db0
  # allow_key_prefix = ["user:", "session:"]
```

Run as a Kubernetes Job (cluster-mode equivalent uses `[sync_reader] cluster = true`):

```bash
kubectl -n valkey run redisshake \
  --image=ghcr.io/tair-opensource/redisshake:latest \
  --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"redisshake","image":"ghcr.io/tair-opensource/redisshake:latest","command":["redis-shake","/config/redisshake.toml"],"volumeMounts":[{"name":"config","mountPath":"/config"}]}],"volumes":[{"name":"config","configMap":{"name":"redisshake-config"}}]}}' \
  --dry-run=client -o yaml > redisshake-job.yaml

# Create the ConfigMap from your toml above, then kubectl apply both.
```

For most hand-rolled `REPLICAOF` migrations, a RedisShake-based migration is what you'd evolve to on the second attempt anyway — start with it.

### Rollback (Approach B)

If validation in Step 3 fails or the cutover in Step 7 surfaces issues:

1. **Before `REPLICAOF NO ONE`** — easy rollback. The EC2 source is still authoritative, the EKS pod is just a replica. Run `REPLICAOF NO ONE` on the EKS pod to detach (so it stops chasing the source), wipe the EKS PVCs, and restart the migration. No data loss.

2. **After `REPLICAOF NO ONE` but before app cutover** — the EKS pod is now an independent primary holding a snapshot, and the EC2 source has resumed serving writes (which the EKS pod no longer sees). To roll back:
   - Resume normal traffic on the EC2 source.
   - Use Approach A's destructive flow to wipe the EKS pod and re-migrate from a fresh BGSAVE later.

3. **After app cutover** — the EKS pod has been accepting writes that the EC2 source doesn't know about. Rolling back to EC2 means losing those writes. Pick one:
   - Accept the loss, point apps back at EC2, reconcile diverged keys manually (rare; only feasible for small datasets).
   - Don't roll back; debug forward on the EKS side.

The lesson: **validate aggressively before Step 5**. Once you run `REPLICAOF NO ONE` and the source resumes writes, your rollback options narrow fast.

### Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `Replica bio thread: Error reading sync metadata` looping | Auth mismatch — source has password, replica didn't set `masterauth` / `primaryauth` | `CONFIG SET masterauth <source-password>` on replica |
| `MASTER aborted replication with an error: NOAUTH` | Same as above | Same as above |
| Initial sync runs forever | `repl-backlog-size` too small; backlog overflows mid-sync, loops back to full-resync | Raise `repl-backlog-size` on source (Step 2 of pre-flight) |
| `master_link_status: down` flapping | Network instability or sec-group drop | Run `ping`/`mtr` from pod to source IP; verify SG rule on the source |
| `Loading RDB produced by version X.Y.Z, my version is A.B.C` | Source RDB version newer than target | Pin a Valkey image of the source's matching major in `helm-values/valkey.yaml`, then upgrade after migration |
| Replica's `master_repl_offset` < source's by a constant amount | Replica fell behind, can't catch up | Check pod CPU — replica may need more cores; or source write rate exceeds replica apply rate |
| `slave_read_only` blocks writes during validation | Default `slave-read-only yes` on the replica | Expected; do all writes on the source until cutover |

## Cluster-mode migration

If your target is the **cluster-mode** deployment (sharded, in the `valkey-cluster` namespace), do not use this runbook. Cluster mode uses a different migration path because keys must land on the correct shard based on their hash slot — an RDB-through-S3 restore would put all keys on one shard.

See [Cluster Mode → Migration from Replication Mode](./cluster-mode.md#migration-from-replication-mode). The flow there uses `valkey-cli --cluster import` from a temporary pod, which streams keys from the source and lets the cluster client route each key to the correct shard via the hash-slot map.

## Cleanup

After the migration is verified and stable for at least 24 hours:

```bash
# Delete the migration RDB from S3 (it was a one-time staging artefact).
aws s3 rm "s3://${BUCKET}/valkey-migration/dump.rdb"

# Also delete the Step 2 target-backup if you uploaded one:
aws s3 rm "s3://${BUCKET}/pre-migration-backups/" --recursive

# Optional: configure a Lifecycle rule so future migrations auto-expire after 30 days.
aws s3api put-bucket-lifecycle-configuration --bucket "${BUCKET}" --lifecycle-configuration '{
  "Rules": [{
    "ID": "valkey-migration-30d-expire",
    "Status": "Enabled",
    "Filter": {"Prefix": "valkey-migration/"},
    "Expiration": {"Days": 30}
  }]
}'
```

Verify the restore initContainer is disabled (Step 10):

```bash
kubectl -n valkey get statefulset valkey -o jsonpath='{.spec.template.spec.initContainers[0].env}' | \
  python3 -m json.tool | grep -A1 RESTORE_ENABLED
# expect: "value": "false"
```

If you decommission the EC2 source: stop writers, take one final RDB snapshot to S3 cold storage (Glacier), then proceed with the standard EC2 decommission checklist.

## Troubleshooting

### `valkey-0` stays `Init:Error`

```bash
kubectl -n valkey logs valkey-0 -c restore-rdb
kubectl -n valkey describe pod valkey-0 | grep -A 10 'restore-rdb'
```

| Symptom | Cause | Fix |
|---|---|---|
| `restore: object missing at s3://…/valkey-migration/dump.rdb` | Script wrote to a different key (e.g., used `--shard 0`, producing `…/0/dump.rdb`) | Re-upload without `--shard`, OR move the existing object: `aws s3 mv s3://$BUCKET/valkey-migration/0/dump.rdb s3://$BUCKET/valkey-migration/dump.rdb` |
| `restore: object missing` (and bucket is right) | `S3_BUCKET` or `S3_PREFIX` typo in helm-values | Compare bucket+prefix in `extraInitContainers[0].env` against the script's output line `Uploaded object` |
| `aws s3 cp` fails with `403 Forbidden` | Pod Identity not associated, or IAM policy missing the bucket | Run the Pre-flight check 4 — verify the association exists and the policy includes both the bucket ARN and bucket-ARN-slash-star |
| `dial tcp: lookup s3.amazonaws.com: no such host` | CoreDNS or VPC endpoint issue | Check the VPC's S3 Gateway endpoint route and CoreDNS pod logs |
| `restore: size mismatch — expected=X actual=Y` | Source RDB modified mid-upload, or upload truncated | Re-stop source writes, re-run the migration script |
| `restore: existing dump.rdb found … skipping download` | PVC was not deleted before triggering restore | Scale to 0, `kubectl delete pvc -l app.kubernetes.io/name=valkey`, scale back up |

### Replicas stuck syncing forever

```bash
for i in 1 2 3; do
  echo "--- valkey-$i ---"
  kubectl -n valkey logs valkey-$i -c valkey | grep -E '(MASTER|sync|psync|fullsync)' | tail -10
done
```

Common patterns:

- **`Master is currently unable to PSYNC but should be in the future`** — primary is rejecting writes during a save. Wait for the primary's `LASTSAVE` to advance.
- **`Trying a partial resynchronization (request 0).`** repeatedly — replication backlog exhausted. Restart the replica pod to force a fresh full sync: `kubectl -n valkey delete pod valkey-1`.
- **PSYNC succeeds but `info replication` shows `lag` stuck > 0** — primary is being written to faster than the replica can apply. Check application traffic isn't already double-targeting.

### `DBSIZE` doesn't match the source

Within **0.1%** drift is normal (key TTLs expiring during the migration window). Beyond that, investigate:

- **Multi-DB source**: if the source had keys in `db1`, `db2`, …, only `db0` migrated. Run `valkey-cli INFO keyspace` on both sides and compare.
- **Memory-only encoding difference**: `used_memory_human` can differ by up to 30% between Redis 6.x and Valkey 9.x for the same keyset. `OBJECT ENCODING` differs because Valkey 9 uses `listpack` for small lists/hashes/sorted-sets where Redis 6 used `ziplist`. This is **not** data loss — only an accounting difference. To compare a specific key:

  ```bash
  # On source
  valkey-cli OBJECT ENCODING <some-key>

  # On target
  kubectl -n valkey exec valkey-0 -c valkey -- \
    valkey-cli -a "$PASS" --no-auth-warning OBJECT ENCODING <same-key>
  ```

  If the encoding differs but the value is identical (`GET` returns the same content), it's accounting drift.

- **AOF on source held writes that didn't reach the RDB**: if the source has `appendonly yes` AND BGSAVE coincided with a heavy write burst, some recent writes may live in the AOF tail and not the RDB. The fix: pause writes longer before BGSAVE, or use `BGREWRITEAOF` first then `BGSAVE`.

### Pod Identity verification fails

The Pre-flight check 4 should return an association. If empty:

```bash
# Force a Terraform reconcile of the association resource
cd data-stacks/valkey-on-eks
./deploy.sh

# Check the IAM policy attached to the role
ROLE=$(aws eks list-pod-identity-associations \
        --cluster-name "$CLUSTER_NAME" --namespace valkey \
        --service-account valkey-sa \
        --query 'associations[0].roleArn' --output text)
aws iam list-attached-role-policies --role-name "${ROLE##*/}"
```

The role must have a policy granting `s3:GetObject` + `s3:ListBucket` on the migration bucket. The policy is defined at `infra/terraform/valkey.tf` resource `aws_iam_policy.valkey_restore_s3`.

## References

- [Valkey persistence docs](https://valkey.io/topics/persistence/) — RDB / AOF semantics.
- [Valkey CLIENT PAUSE](https://valkey.io/commands/client-pause/) — write-pause command used in the downtime strategy.
- [AWS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html) — how the restore initContainer authenticates to S3.
- [Replication mode runbook](./replication.md) — for primary/replica health checks referenced above.
- [Cluster mode migration](./cluster-mode.md#migration-from-replication-mode) — for migrating to the sharded cluster instead.
