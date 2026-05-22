---
title: EC2 → EKS Migration
sidebar_position: 4
---

# Self-Managed Valkey/Redis on EC2 → EKS Migration

Move a self-managed Valkey or Redis instance running on EC2 (or any other host) onto the EKS-hosted **replication-mode** cluster. The migration is **offline RDB snapshot through S3**: stop writes on the source, snapshot, upload, restore on the target. Online replication via `REPLICAOF` between EC2 and EKS is out of scope here — it is fragile across networks and version skew, and depends on routing/security-group setup outside the data plane.

:::warning Production-safety reminder
This runbook is **destructive** to the target cluster on the happy path — it deletes the target's PVCs before restoring. **Read the entire doc once before running anything.** Capture the source's `DBSIZE` and `used_memory_human` first; you will cross-check them after the restore. If your target cluster is already serving production data, jump to [Already-serving target](#already-serving-target) — the destructive path is wrong for you.
:::

## Which migration is this?

| Target topology | Use |
| --- | --- |
| **Replication mode** (this stack's default: 1 primary + N replicas in the `valkey` namespace) | **This document.** |
| **Cluster mode** (sharded, in the `valkey-cluster` namespace) | See [Cluster Mode → Migration from Replication Mode](./cluster-mode.md#migration-from-replication-mode). The cluster-mode path uses `valkey-cli --cluster import` from a temporary pod, not RDB-through-S3. |

## When to use this runbook

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
