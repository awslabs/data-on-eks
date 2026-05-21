---
title: EC2 → EKS Migration
sidebar_position: 4
---

# Self-Managed Valkey/Redis on EC2 → EKS Migration

Move a self-managed Valkey or Redis instance running on EC2 (or any other host) onto the EKS-hosted replication cluster. The migration is **offline RDB snapshot through S3**: pause writes on the source, snapshot, upload, restore on the target. Online replication via `REPLICAOF` between EC2 and EKS is out of scope here — it is fragile across networks and version skew, and depends on routing/security-group setup outside the data plane.

## When to use this runbook

- Source: a single Valkey or Redis instance (any version compatible with the target's Valkey image — see compatibility matrix below).
- Target: this stack's EKS replication cluster, freshly deployed or already serving (the runbook works for both, with a different recovery flow for already-serving clusters).
- Acceptable downtime: **5–30 minutes for datasets up to ~50 GiB** on `gp3`. Larger datasets scale roughly linearly with S3 → EBS download throughput.
- Network: the EC2 source must have outbound HTTPS to S3 in the target AWS region. The EKS cluster needs the migration bucket (Terraform-provisioned).

## Compatibility Matrix

| Source | Target Valkey image | Notes |
|---|---|---|
| Redis 7.2.x | Valkey 9.0.x (default) | Supported. RDB format compatible. |
| Redis 7.0.x | Valkey 9.0.x | Supported. RDB version 11 → 12 forward compatible. |
| Redis 6.2.x | Valkey 9.0.x | Supported. Test with a copy first. |
| Redis ≤ 6.0 | Valkey 9.0.x | RDB version mismatch likely. Pin a Valkey image of the matching major before migrating, then upgrade. |
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
│                      │ ─────────────►   │  2. helm values flip restore.enabled=true  │
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

## Pre-Migration

### 1. Sanity-check the source

```bash
# On the EC2 source host
valkey-cli INFO server | grep -E '^(redis_version|valkey_version|os|process_id):'
valkey-cli DBSIZE
valkey-cli INFO memory | grep '^used_memory_human'
valkey-cli LASTSAVE
ls -lh /var/lib/valkey/dump.rdb
```

Note the values — you'll cross-check them on the target.

### 2. Confirm the target migration bucket

```bash
# From a host with kubectl + AWS access to the target cluster
export KUBECONFIG=$(pwd)/kubeconfig.yaml

BUCKET=$(terraform -chdir=data-stacks/valkey-on-eks/terraform/_local output -raw valkey_migration_bucket)
echo "Migration bucket: $BUCKET"
aws s3 ls "s3://${BUCKET}/" 2>&1   # expect empty (or contains prior runs)
```

### 3. Stop write traffic on the source

Any writes that arrive between the BGSAVE start and the cutover are not migrated. Options:

- Application-level: pause your app's write path.
- Network-level: drop ingress on TCP 6379 in the source's security group.
- Valkey-level: set `replicaof <unreachable-host> 0` to convert the source to read-only (rare, requires the source to support replicaof).

If full pause is unacceptable, accept the documented data-loss window (writes after BGSAVE are lost) and plan a brief replay from your application's source-of-truth log. This is your call — the runbook is offline.

## Run the Migration

### Step 1 — BGSAVE and upload to S3

The bundled script handles the full sequence: capture `LASTSAVE`, issue `BGSAVE`, poll until `LASTSAVE` advances, verify the local file, upload to S3, verify the upload via `head-object`.

Run on the EC2 source (or any host with `valkey-cli` / `redis-cli` and `aws` CLI):

```bash
# Either pass --password explicitly, or export REDISCLI_AUTH first
export REDISCLI_AUTH="$(cat /etc/valkey/auth)"

./data-stacks/valkey-on-eks/examples/migration/ec2-bgsave-to-s3.sh \
  --host valkey.internal.example.com \
  --s3-bucket "${BUCKET}" \
  --s3-prefix valkey-migration \
  --shard 0 \
  --rdb-path /var/lib/valkey/dump.rdb \
  --timeout-seconds 1800
```

Expected output ends with:

```
SUCCESS
 Source host         : valkey.internal.example.com:6379
 Shard ordinal       : 0
 Uploaded object     : s3://valkey-on-eks-valkey-migration-XXXXXX/valkey-migration/0/dump.rdb
 Object size         : 4823184 bytes

 NEXT STEP
   Edit infra/terraform/helm-values/valkey.yaml in your data stack:
       restore:
         enabled: true
         s3Bucket: valkey-on-eks-valkey-migration-XXXXXX
         s3Prefix: valkey-migration
         onMissing: fail
   Then apply the EKS deploy:
       cd data-stacks/valkey-on-eks && ./deploy.sh
```

The script's exit codes:

| Exit code | Meaning |
|---|---|
| `0` | RDB uploaded and verified |
| `1` | BGSAVE timeout, or source connection failed |
| `2` | S3 upload or HEAD verification failed |
| `64` | Bad arguments |
| `127` | Required tool (`valkey-cli`, `aws`, `stat`) missing |

### Step 2 — Enable the restore initContainer

The restore initContainer is **always present** in the StatefulSet pod spec (always-emit, runtime-gate pattern). When `RESTORE_ENABLED=false` it `exit 0`s immediately. Flip it on by editing `infra/terraform/helm-values/valkey.yaml`:

```yaml
extraInitContainers:
  - name: restore-rdb
    image: amazon/aws-cli:2.17.0
    env:
      - name: RESTORE_ENABLED
        value: "true"           # was "false"
      - name: AWS_REGION
        value: ${region}
      - name: S3_BUCKET
        value: "valkey-on-eks-valkey-migration-XXXXXX"   # was ""
      - name: S3_PREFIX
        value: "valkey-migration"
      - name: ON_MISSING
        value: "fail"
    # ... rest unchanged
```

`ON_MISSING` controls behavior when the S3 object is missing:

| Value | Behavior |
|---|---|
| `fail` (recommended for migration) | Exit non-zero. The Valkey container does not start. The pod stays in `Init:Error`. Forces the operator to debug missing data. |
| `skip` | Exit 0. Valkey starts with an empty dataset. Useful for fresh deploys (default new clusters) or for replicas that should sync from the primary, not from S3. |

### Step 3 — Trigger the restore

The cleanest option is to recycle the StatefulSet so each pod starts on an empty PVC and the initContainer runs:

```bash
# Scale down to 0, delete PVCs (so initContainer has clean /data), scale back up
kubectl -n valkey scale statefulset valkey --replicas=0
kubectl -n valkey wait --for=delete pod -l app.kubernetes.io/name=valkey --timeout=2m
kubectl -n valkey delete pvc -l app.kubernetes.io/name=valkey
kubectl -n valkey scale statefulset valkey --replicas=4
```

:::warning
This destroys any existing in-cluster Valkey data. For a fresh cluster (no users yet) this is the right path. For a cluster already serving production reads, see the **already-serving cluster** flow at the end of this doc.
:::

Apply the updated Helm values via the standard path:

```bash
cd data-stacks/valkey-on-eks
./deploy.sh
```

This re-renders the ArgoCD Application with the new `extraInitContainers` env vars; ArgoCD reconciles, and the new pods come up running the restore initContainer.

### Step 4 — Watch the restore

```bash
# Init container logs from the primary pod
kubectl -n valkey logs valkey-0 -c restore-rdb -f
```

Expected output:

```
restore: checking s3://<bucket>/valkey-migration/0/dump.rdb
restore: downloading 4823184 bytes to /data/dump.rdb.partial
restore: placed dump.rdb (4823184 bytes) at /data/dump.rdb
```

The Valkey container starts, loads `dump.rdb` (logged as `Loading RDB produced by version X.Y.Z`), reaches `Ready to accept connections`, and the chart's readiness probe passes.

For replicas (`valkey-1..3`), the same initContainer runs, but the chart's startup script issues `REPLICAOF valkey-0...` once the Valkey container is up — replicas full-sync from the primary's just-restored dataset over the local network. This is faster than re-restoring each replica from S3.

### Step 5 — Validate

```bash
PASS=$(kubectl -n valkey get secret valkey-auth -o jsonpath='{.data.default}' | base64 -d)

# Replication health
kubectl -n valkey exec valkey-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning INFO replication
# expect: role:master ; connected_slaves:3 ; min_slaves_good_slaves:3

# Keyspace and memory match the source
kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli -a "$PASS" --no-auth-warning DBSIZE
kubectl -n valkey exec valkey-0 -c valkey -- valkey-cli -a "$PASS" --no-auth-warning INFO memory | \
  grep '^used_memory_human:'

# Sample a few known keys
kubectl -n valkey exec valkey-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning GET <known-key-from-source>
```

Cross-check `DBSIZE` and `used_memory_human` against the values you noted from the source in pre-migration step 1. Small deltas (`< 1%`) are normal due to encoding differences between Redis and Valkey; large deltas (`> 5%`) indicate a partial restore — re-investigate.

### Step 6 — Cut over

Update your application config (or DNS, or load-balancer target) to point at the EKS endpoints:

| Path | EKS endpoint |
|---|---|
| Writes | `valkey.valkey.svc.cluster.local:6379` |
| Reads (load-balanced) | `valkey-read.valkey.svc.cluster.local:6379` |

For applications outside the EKS cluster, expose `valkey` via a Kubernetes Service of type `LoadBalancer` or an NLB / Ingress — see the chart's `service.type` value. Note that ACL passwords differ between the EC2 source and the EKS target (Terraform generated fresh passwords for the target); update your client config accordingly:

```bash
# Get the new ACL passwords
kubectl -n valkey get secret valkey-auth \
  -o jsonpath='{.data.default}' | base64 -d
```

### Step 7 — Disable the restore initContainer

Once the cutover is complete and the cluster is stable, flip `RESTORE_ENABLED` back to `"false"`:

```yaml
extraInitContainers:
  - name: restore-rdb
    env:
      - name: RESTORE_ENABLED
        value: "false"
```

This prevents accidental re-restores on future pod restarts (the initContainer now exits 0 immediately). The S3 object stays in the bucket per its Lifecycle rules (none configured by default; see Cleanup below).

## Already-Serving Cluster Flow

If the EKS cluster is already serving production reads/writes and you cannot afford to wipe its PVCs, the steps differ:

1. **Promote a replica to primary** (see [Replication Cluster — Manual Failover](./replication.md#manual-primary-failover)) so writes can pause briefly without the primary being the recovery target.
2. **Run BGSAVE on the source EC2** and upload to S3 (Step 1 above, unchanged).
3. **Apply the restore initContainer config** (Step 2, unchanged).
4. **Restore only `valkey-0`**, not all pods:
   ```bash
   kubectl -n valkey delete pvc data-valkey-0
   kubectl -n valkey delete pod valkey-0
   ```
   The StatefulSet recreates `valkey-0`; the initContainer runs; Valkey starts and loads the new dataset.
5. **Promote `valkey-0` back to primary** via the manual failover sequence in reverse.
6. **Resync replicas** — they will full-sync from the new primary's dataset automatically.

This flow trades complexity for less downtime. Use only when the existing cluster has data you want to preserve up to the point of the failover.

## Cleanup

After the migration is verified and stable for at least 24 hours:

```bash
# Delete the migration RDB from S3
aws s3 rm "s3://${BUCKET}/valkey-migration/0/dump.rdb"

# Optional: configure a Lifecycle rule so future migrations auto-expire after N days
aws s3api put-bucket-lifecycle-configuration --bucket "${BUCKET}" --lifecycle-configuration '{
  "Rules": [{
    "ID": "valkey-migration-30d-expire",
    "Status": "Enabled",
    "Filter": {"Prefix": "valkey-migration/"},
    "Expiration": {"Days": 30}
  }]
}'
```

If you decommission the EC2 source, the standard EBS-volume-cleanup checklist applies (snapshot final state, delete instance, release EIP, etc.).

## Troubleshooting

**`valkey-0` stays `Init:Error`.** The initContainer failed. Logs:

```bash
kubectl -n valkey logs valkey-0 -c restore-rdb
kubectl -n valkey describe pod valkey-0 | grep -A 10 'restore-rdb'
```

Common causes:

| Symptom | Cause | Fix |
|---|---|---|
| `restore: object missing at s3://...` | Wrong `S3_BUCKET` / `S3_PREFIX`; key uploaded to a different shard ordinal | Re-check the upload step; the script logs the exact key it wrote |
| `aws s3 cp` fails with `403` | Pod Identity not associated, or IAM policy missing the bucket | Check the `aws_eks_pod_identity_association` for `valkey-sa`; verify the `valkey-restore-s3` policy resource list |
| `aws s3 cp` fails with `dial tcp: lookup s3.amazonaws.com: no such host` | CoreDNS or VPC endpoint issue | Check the VPC's S3 Gateway endpoint route and CoreDNS pod logs |
| `restore: size mismatch` | Source RDB modified mid-upload, or upload truncated | Re-run the migration script |

**Replicas stuck syncing forever.** The replication backlog is exhausted, or the primary's dataset is larger than the network can sync within the timeout. Check:

```bash
kubectl -n valkey logs valkey-1 -c valkey | grep -E '(MASTER|sync|psync|fullsync)'
```

If you see repeated `Master is currently unable to PSYNC but should be in the future`, the primary is rejecting writes during a save. Wait for the primary's `LASTSAVE` to advance, then the replica retries automatically.

**Dataset size on EKS doesn't match source.** Check what data structures Valkey is decoding differently. The most common offender is `OBJECT ENCODING` differences: Valkey 9.x uses `listpack` for small lists/hashes/sorted-sets where Redis 6.x used `ziplist`. Same data, different memory accounting. To compare:

```bash
# On source
valkey-cli OBJECT ENCODING <some-key>

# On target
kubectl -n valkey exec valkey-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning OBJECT ENCODING <same-key>
```
