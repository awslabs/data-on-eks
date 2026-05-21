---
title: Infrastructure Deployment
sidebar_position: 1
---

# Infrastructure Deployment

Provisions an EKS cluster with VPC, Karpenter, ArgoCD, and the official Valkey Helm release. Follows the Data-on-EKS [Base + Overlay pattern](../../contributing): the Valkey component lives in `infra/terraform/` (gated by `enable_valkey`); the overlay in `data-stacks/valkey-on-eks/` flips the gate and ships the deploy/cleanup scripts and examples.

## Prerequisites

| Tool | Tested version | Purpose |
|---|---|---|
| `terraform` | ≥ 1.5.0 | Terraform engine |
| `aws` CLI | ≥ 2.15 | Authentication; updating kubeconfig |
| `kubectl` | ≥ 1.30 | Cluster verification |
| `helm` | ≥ 3.13 | Manual chart inspection (optional) |
| `valkey-cli` or `redis-cli` | ≥ 7.2 | Smoke testing |

AWS credentials must be active (`aws sts get-caller-identity` returns successfully). Region defaults to `us-west-2`; override via `AWS_REGION` before running `deploy.sh`.

## Component Inventory

The deployment provisions the following AWS and Kubernetes resources, gated by `var.enable_valkey`:

```
infra/terraform/
├── valkey.tf                                   # Terraform glue
├── variables.tf                                # adds `enable_valkey` (bool, default false)
├── helm-values/
│   └── valkey.yaml                             # single source of truth for chart values
├── argocd-applications/
│   └── valkey.yaml                             # ArgoCD Application manifest, pinned chart version
└── manifests/
    └── karpenter/
        └── nodepool-valkey.yaml                # dedicated Graviton on-demand NodePool
```

| Resource | Purpose |
|---|---|
| `kubectl_manifest.valkey_namespace` | `valkey` namespace |
| `random_password.valkey_default_user` | 32-char ACL password for application traffic |
| `random_password.valkey_replication_user` | 32-char ACL password for replica → primary auth |
| `kubernetes_secret.valkey_auth` | Holds both passwords under keys `default` and `replication-user` |
| `aws_s3_bucket.valkey_migration` | Source bucket for the EC2-to-EKS migration runbook |
| `aws_s3_bucket_server_side_encryption_configuration.valkey_migration` | AES-256 SSE |
| `aws_s3_bucket_public_access_block.valkey_migration` | All four blocks enabled |
| `aws_iam_policy.valkey_restore_s3` | `s3:GetObject`, `s3:ListBucket` scoped to the migration bucket |
| `module.valkey_restore_pod_identity` | EKS Pod Identity association for SA `valkey-sa` |
| `kubectl_manifest.valkey` | ArgoCD Application that deploys the chart |
| Karpenter NodePool `valkey` | `r7g`/`r8g` Graviton, on-demand, taint `workload=valkey:NoSchedule`, label `NodeGroupType=valkey` |

## Topology

The default deployment is **1 primary + 3 replicas**, hard-spread across three Availability Zones via `topologySpreadConstraints` (`maxSkew: 1`, `whenUnsatisfiable: DoNotSchedule`). Karpenter provisions one Graviton on-demand node per pod from `us-west-2a`, `us-west-2b`, and `us-west-2c`. EBS PVCs use `volumeBindingMode: WaitForFirstConsumer` so the volume is created in the same AZ as its scheduled pod.

```
┌───────────────────── Region us-west-2 ─────────────────────┐
│                                                            │
│  AZ us-west-2a       AZ us-west-2b       AZ us-west-2c     │
│  ┌────────────┐      ┌────────────┐      ┌────────────┐    │
│  │ valkey-0   │      │ valkey-1   │      │ valkey-2   │    │
│  │ primary    │ ───► │ replica    │      │ replica    │    │
│  │ r7g.large  │      │ r7g.large  │      │ r7g.large  │    │
│  └────────────┘      └────────────┘      └────────────┘    │
│                                                            │
│  Service `valkey`         → primary (writes)               │
│  Service `valkey-read`    → all 4 pods, load-balanced      │
│  Service `valkey-headless`→ per-pod stable DNS             │
└────────────────────────────────────────────────────────────┘
```

A 4th replica is scheduled wherever Karpenter has spare capacity (pod-anti-affinity is soft via `maxSkew: 1`, so two pods may share an AZ before adding a 4th node). The doc-recommended production layout is **3 primaries + 3 replicas** in cluster mode; until upstream chart support lands, replication mode is the closest available.

## Deploy

```bash
cd data-stacks/valkey-on-eks
./deploy.sh
```

The script sources `infra/terraform/install.sh`, which:

1. Stages a working copy of the base infrastructure into `terraform/_local/`, then overlays `data-stacks/valkey-on-eks/terraform/` on top.
2. Runs `terraform init -upgrade`.
3. Applies in stages: `module.vpc` → `module.eks` → all remaining resources. Staged applies prevent cycles between provider auth (kubernetes/helm/kubectl) and cluster bootstrap.
4. Backs up `terraform.tfstate` to `terraform/terraform.tfstate.bak`.
5. Writes `kubeconfig.yaml` for `valkey-on-eks`.
6. Annotates every ArgoCD Application with `argocd.argoproj.io/refresh=normal` to force an immediate reconcile.

End-to-end runtime on a fresh AWS account is **25–30 minutes**: ~1 min VPC, ~12 min EKS control plane, ~10 min addons + ArgoCD + Valkey StatefulSet rollout.

## Verify

```bash
export KUBECONFIG=$(pwd)/kubeconfig.yaml

# 1. EKS reachable
kubectl get nodes -l NodeGroupType=valkey -o wide

# 2. ArgoCD synced and healthy
kubectl -n argocd get application valkey \
  -o jsonpath='{"sync="}{.status.sync.status}{"  health="}{.status.health.status}{"\n"}'
# Expected: sync=Synced  health=Healthy

# 3. Pods 2/2 Running (valkey + redis_exporter sidecar)
kubectl -n valkey get pods
# valkey-0   2/2     Running
# valkey-1   2/2     Running
# valkey-2   2/2     Running
# valkey-3   2/2     Running

# 4. Per-pod AZ placement
kubectl -n valkey get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}' | \
  while read p n; do
    az=$(kubectl get node "$n" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}')
    echo "$p  $az"
  done
# valkey-0  us-west-2a
# valkey-1  us-west-2b
# valkey-2  us-west-2c
# valkey-3  us-west-2a
```

Detailed verification (replication health, smoke test) is in [Replication Cluster](./replication.md).

## Configuration Surface

The only Terraform variable for this component is `enable_valkey`. All per-deployment configuration lives in `infra/terraform/helm-values/valkey.yaml` and is consumed by the chart through ArgoCD. Edit values directly there; ArgoCD picks up the next sync.

The Terraform `templatefile()` call injects exactly three placeholders: `${namespace}`, `${service_account_name}`, `${region}`. Everything else is a plain Helm value.

| Helm key | Default | Description |
|---|---|---|
| `image.tag` | `""` (chart's `appVersion`, currently `9.0.2`) | Pin to a specific Valkey version when needed |
| `replica.enabled` | `true` | Replication mode on |
| `replica.replicas` | `3` | Number of replica pods |
| `replica.minReplicasToWrite` | `1` | Reject writes when fewer than this many replicas are in sync |
| `replica.minReplicasMaxLag` | `10` | Maximum replica lag (seconds) to count as in-sync |
| `replica.persistence.size` | `50Gi` | Per-pod EBS gp3 PVC size |
| `replica.persistence.storageClass` | `gp3` | StorageClass; uses `WaitForFirstConsumer` |
| `auth.enabled` | `true` | ACL-based authentication |
| `auth.usersExistingSecret` | `valkey-auth` | K8s Secret holding ACL passwords (Terraform-generated) |
| `podDisruptionBudget.enabled` | `true` | Protect the replica pool during voluntary disruptions |
| `podDisruptionBudget.maxUnavailable` | `1` | At most one Valkey pod unavailable at a time |
| `metrics.enabled` | `true` | Bundled Prometheus exporter sidecar |
| `metrics.serviceMonitor.enabled` | `true` | Emit ServiceMonitor for `kube-prometheus-stack` |
| `terminationGracePeriodSeconds` | `30` | Grace period for replica handoff during pod restart |
| `topologySpreadConstraints[0].whenUnsatisfiable` | `DoNotSchedule` | Hard AZ spread; pods stay `Pending` if no AZ has spare capacity |
| `extraInitContainers[0].env.RESTORE_ENABLED` | `"false"` | Set to `"true"` to enable the migration restore initContainer |

## Cleanup

```bash
./cleanup.sh
```

The script destroys all Terraform-managed resources (Valkey, ArgoCD applications, addons, EKS cluster, VPC) in reverse order, then sweeps any orphan EBS volumes tagged with the deployment ID. Total runtime: 15–20 minutes. The S3 migration bucket is destroyed with everything else — copy out RDB snapshots first if you need them:

```bash
BUCKET=$(terraform -chdir=terraform/_local output -raw valkey_migration_bucket)
aws s3 sync "s3://${BUCKET}" ./valkey-migration-archive/
./cleanup.sh
```

