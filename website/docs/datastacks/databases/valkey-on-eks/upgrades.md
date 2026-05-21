---
title: Upgrades
sidebar_position: 3
---

# Upgrade Runbooks

Three upgrade dimensions for this stack: **Helm chart version** (the `valkey-io/valkey-helm` chart), **Valkey image tag** (the data plane), and **Karpenter AMI** (the underlying node OS / EKS worker). Each is rolling and PDB-protected; rollback is via ArgoCD revision history or Karpenter drift correction.

## Pre-flight Checklist

Before any upgrade:

```bash
PASS=$(kubectl -n valkey get secret valkey-auth -o jsonpath='{.data.default}' | base64 -d)

# 1. All pods 2/2 Ready
kubectl -n valkey get pods
# expect: valkey-0..3   2/2   Running

# 2. Replication is healthy
kubectl -n valkey exec valkey-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning INFO replication | grep -E '^(role|connected_slaves|min_slaves_good_slaves):'
# expect: role:master ; connected_slaves:3 ; min_slaves_good_slaves:3

# 3. ArgoCD app is Synced + Healthy
kubectl -n argocd get application valkey \
  -o jsonpath='{"sync="}{.status.sync.status}{"  health="}{.status.health.status}{"\n"}'
# expect: sync=Synced  health=Healthy

# 4. Karpenter NodePool has spare capacity headroom (at least 1 node worth)
kubectl get nodes -l NodeGroupType=valkey
kubectl get nodepool valkey -o jsonpath='{.spec.limits}'
```

If any pre-flight fails, fix before proceeding. An upgrade against a degraded cluster compounds failure.

## 1. Helm Chart Version Bump

Use this for chart-only changes (added values, fixed templates, new features in upstream `valkey-helm`).

### Procedure

1. **Check the upstream changelog.** Read [valkey-io/valkey-helm releases](https://github.com/valkey-io/valkey-helm/releases) for the target version. Note breaking changes to values schema.

2. **Bump `targetRevision`** in `infra/terraform/argocd-applications/valkey.yaml`:

   ```yaml
   spec:
     source:
       repoURL: https://valkey.io/valkey-helm/
       chart: valkey
       targetRevision: "0.10.0"   # was "0.9.4"
   ```

3. **(Optional) Render and diff locally** to surface any helm-values incompatibility before ArgoCD tries to apply:

   ```bash
   helm repo add valkey https://valkey.io/valkey-helm/
   helm repo update
   helm template valkey valkey/valkey \
     --version 0.10.0 \
     -f infra/terraform/helm-values/valkey.yaml \
     --set namespace=valkey,service_account_name=valkey-sa,region=us-west-2 \
     > /tmp/new-render.yaml
   # diff against current
   ```

4. **Apply** by re-running the targeted Terraform apply, or by triggering an ArgoCD sync directly:

   ```bash
   # Option A: from the data stack overlay
   cd data-stacks/valkey-on-eks
   ./deploy.sh

   # Option B: targeted apply — faster when only the ArgoCD Application changed
   cd terraform/_local
   terraform apply -var-file=data-stack.tfvars -target='kubectl_manifest.valkey[0]' -auto-approve
   ```

5. **Watch the rolling restart.** ArgoCD applies the new chart, which writes a new ConfigMap (and possibly a new StatefulSet pod template hash). The StatefulSet rolls highest-ordinal-first by default — replicas restart before the primary.

   ```bash
   kubectl -n valkey rollout status statefulset/valkey --timeout=10m
   kubectl -n valkey get pods -w
   ```

6. **Verify.** Re-run the pre-flight checks plus the smoke test:

   ```bash
   kubectl apply -f data-stacks/valkey-on-eks/examples/valkey-replication-smoke.yaml
   kubectl -n valkey logs -f job/valkey-smoke
   ```

### Rollback

```bash
argocd app rollback valkey   # uses the previous revision
# or via kubectl, for a known-good chart version:
# bump argocd-applications/valkey.yaml targetRevision back, re-apply
```

The PDB still enforces `maxUnavailable: 1` during rollback. Both the original and rollback rollouts honor `terminationGracePeriodSeconds: 30` so replication links unwind cleanly.

## 2. Valkey Image Tag Bump (Minor / Patch)

Use this for Valkey patch upgrades (e.g., `9.0.2` → `9.0.3`) without a chart bump.

### Procedure

1. **Pin the new tag** in `infra/terraform/helm-values/valkey.yaml`:

   ```yaml
   image:
     registry: docker.io
     repository: valkey/valkey
     tag: "9.0.3"   # was empty (= chart's appVersion)
   ```

2. **Apply** as in Chart Bump step 4.

3. **Optional: pre-failover before the primary restarts.** The StatefulSet rolls highest-ordinal-first, so by default `valkey-3` → `valkey-2` → `valkey-1` → `valkey-0` (primary). Write clients see a brief unavailability window (5–15 seconds) when the primary restarts. To eliminate that:

   ```bash
   PASS=$(kubectl -n valkey get secret valkey-auth -o jsonpath='{.data.default}' | base64 -d)

   # Promote valkey-1 to primary BEFORE valkey-0 restarts
   kubectl -n valkey exec valkey-1 -c valkey -- \
     valkey-cli -a "$PASS" --no-auth-warning REPLICAOF NO ONE

   # Re-point other replicas
   for ord in 2 3; do
     kubectl -n valkey exec valkey-${ord} -c valkey -- \
       valkey-cli -a "$PASS" --no-auth-warning REPLICAOF \
         valkey-1.valkey-headless.valkey.svc.cluster.local 6379
   done

   # Now trigger the rolling update — valkey-0 is now a replica and restarts cleanly
   kubectl -n valkey rollout restart statefulset/valkey
   ```

   After the rollout completes, restore the original layout if desired (`valkey-0` as primary): repeat the `REPLICAOF` sequence in reverse.

   :::note
   The chart sets the `app.kubernetes.io/component` label based on the pod's role at chart-render time. After a `REPLICAOF NO ONE` flip, the Service selector eventually catches up because the chart's `prestop` hook re-evaluates role. If you see lingering write traffic to the old primary, manually patch the label:

   ```bash
   kubectl -n valkey label pod valkey-1 app.kubernetes.io/component=master --overwrite
   kubectl -n valkey label pod valkey-0 app.kubernetes.io/component=replica --overwrite
   ```
   :::

### Rollback

Revert the `image.tag` in `helm-values/valkey.yaml` and re-apply. The rollout is symmetric.

:::warning
Major-version downgrades (e.g., `9.x` → `8.x`) are not supported by Valkey. The on-disk RDB/AOF format may have evolved. Pin to the **same major version** when rolling back, and only roll back across patch/minor lines.
:::

## 3. Karpenter AMI Rollover

EKS bumps the recommended AMI for managed node groups and Karpenter-provisioned nodes regularly. The `valkey` NodePool's `EC2NodeClass` references `al2023@latest` by default, so Karpenter's drift detector flags nodes running an older AMI as `Drifted` and queues them for replacement.

### Procedure

The drift correction is **node-by-node**, paced by the PDB. Manually pace it for stricter control:

```bash
PASS=$(kubectl -n valkey get secret valkey-auth -o jsonpath='{.data.default}' | base64 -d)

for node in $(kubectl get nodes -l NodeGroupType=valkey -o name); do
  echo "Disrupting $node"
  kubectl annotate "$node" karpenter.sh/disrupted=true

  # Wait for the replacement node + Valkey pod to land
  while ! kubectl get nodes -l NodeGroupType=valkey \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' | \
        grep -q "True"; do
    sleep 10
  done

  # Verify replication is still healthy before continuing
  kubectl -n valkey exec valkey-0 -c valkey -- \
    valkey-cli -a "$PASS" --no-auth-warning INFO replication | \
    grep -E '^(role|connected_slaves):'
done
```

The PDB (`maxUnavailable: 1`) blocks Karpenter from disrupting more than one Valkey pod at a time, so even an unsupervised drift correction is bounded — but pacing manually lets you abort on the first sign of trouble.

### What happens during a node disruption

1. Karpenter taints the node with `karpenter.sh/disrupted=NoSchedule:NoExecute`.
2. Pods on the node are evicted respecting the PDB. The Valkey pod's `terminationGracePeriodSeconds: 30` lets the replica close its replication link cleanly (issuing `REPLCONF GETACK *` so the primary knows the replica's offset).
3. Karpenter provisions a new node in the same AZ when possible (the PVC is AZ-pinned).
4. The StatefulSet recreates the pod on the new node. The PVC reattaches; replication catches up via partial PSYNC against the cached backlog.
5. `connected_slaves` returns to the expected count within 30–60 seconds.

### Rollback

If the new AMI introduces an issue, pin the EC2NodeClass to a known-good AMI:

```yaml
# infra/terraform/manifests/karpenter/ec2nodeclass.yaml — patch the relevant class
amiSelectorTerms:
  - alias: al2023@v20260301   # pin to a specific dated AMI
```

Re-apply via `terraform apply` (or commit + ArgoCD sync). Karpenter's drift detector will replace any node not matching the new AMI selector.

## Capacity Resize (vertical)

Bumping a Valkey pod's memory budget requires both a `helm-values` change and a NodePool capability check.

```yaml
# infra/terraform/helm-values/valkey.yaml
resources:
  requests:
    cpu: 1000m
    memory: 28Gi   # was 12Gi
  limits:
    memory: 32Gi   # was 16Gi  -- target ~70-80% of node RAM
```

After applying, Karpenter notices the new pod resource request exceeds `r7g.large` (16 GiB) capacity and provisions a larger instance from the NodePool's `instance-size` requirements list (`large, xlarge, 2xlarge, 4xlarge, 8xlarge`). The NodePool's `limits` (default `cpu: 1000`, `memory: 4000Gi`) cap the total fleet.

### Procedure

1. Edit `resources.requests.memory` and `resources.limits.memory` in `helm-values/valkey.yaml`.
2. Apply via `./deploy.sh` (or targeted Terraform apply).
3. ArgoCD updates the StatefulSet pod template; the rolling update replaces each pod, and Karpenter provisions a larger node for each as it lands.
4. Verify nodes:

   ```bash
   kubectl get nodes -l NodeGroupType=valkey \
     -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.node\.kubernetes\.io/instance-type}{"\n"}{end}'
   # ip-...   r7g.2xlarge
   ```

The PVC size is independent of the instance size — to resize storage, see below.

## Storage Resize

EBS gp3 supports online resize. Increase `replica.persistence.size` in `helm-values/valkey.yaml`:

```yaml
replica:
  persistence:
    size: 100Gi   # was 50Gi
```

Apply via `./deploy.sh`. Each PVC's `spec.resources.requests.storage` updates; the AWS EBS volume expands online (no pod restart needed, but the filesystem may need to re-read its size — most images do this automatically). Verify:

```bash
kubectl -n valkey exec valkey-0 -c valkey -- df -h /data
# /dev/nvme1n1   100G   ...   /data
```

:::note
PVC resize requires the StorageClass to have `allowVolumeExpansion: true` — verify with `kubectl get sc gp3 -o jsonpath='{.allowVolumeExpansion}'`. The default `gp3` StorageClass in this stack has it enabled.
:::

## Combined Upgrade (chart + image + AMI)

For a major release that pairs a chart bump with a Valkey image bump and an EKS minor-version bump:

1. **Chart bump first** (lower-risk, schema diffs surface fastest).
2. **Image bump second** (data plane changes; replication compatibility verified by post-upgrade smoke test).
3. **AMI rollover last** (longest, paced by PDB).
4. **EKS minor-version upgrade** (separate runbook — see EKS managed node group upgrade docs).

Each step is independent; abort and rollback to the previous step's known-good state if any verification fails.
