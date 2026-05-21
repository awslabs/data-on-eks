---
title: Valkey on EKS
sidebar_position: 6
---

import '@site/src/css/datastack-tiles.css';

# Valkey on EKS Stack

[Valkey](https://valkey.io) is an open-source, in-memory key/value datastore — a Linux Foundation–maintained fork of Redis 7.2.4 that continues the BSD-licensed lineage. Wire-compatible with Redis: same protocol, same client libraries (Lettuce, Jedis, ioredis, redis-py, go-redis), same data structures (strings, hashes, lists, sets, sorted sets, streams).

This data stack delivers a production-grade Valkey deployment on Amazon EKS using the **official `valkey-io/valkey-helm` chart** as the default (replication mode), fronted by a dedicated Karpenter NodePool of Graviton (`r7g`/`r8g`) on-demand instances spread across three Availability Zones. **Cluster mode** (sharded with gossip) is also supported via plain Kubernetes manifests — see the [Cluster Mode guide](./cluster-mode.md). The cluster-mode manifest design will be replaced by the official chart's native support once [valkey-helm #18](https://github.com/valkey-io/valkey-helm/issues/18) ships.

## Why this stack

- **Official chart only.** No vendor-licensing risk. Chart and image versions pinned in Git.
- **Multi-AZ by default.** Pods are hard-spread across AZs (`whenUnsatisfiable: DoNotSchedule`) on EBS gp3 PVCs with `WaitForFirstConsumer` binding.
- **ACL authentication.** Two-user setup (`default` for applications, `replication-user` for inter-pod replication) with passwords sourced from a Terraform-generated `kubernetes_secret`.
- **Pod Identity for AWS access.** The restore initContainer reads from the migration S3 bucket via the `valkey-sa` ServiceAccount associated with a least-privilege IAM role — no AWS keys in pod specs or Helm values.
- **Single Terraform variable.** `enable_valkey = true` flips on the entire component; everything else lives in `infra/terraform/helm-values/valkey.yaml`.


<div className="showcase-grid">

<div className="showcase-card featured">
<div className="showcase-header">
<div className="showcase-icon">🏗️</div>
<div className="showcase-content">
<h3>Infrastructure Deployment</h3>
<p className="showcase-description">EKS, VPC across 3 AZs, Graviton Karpenter NodePool, ArgoCD, and the official Valkey Helm release. End-to-end via <code>./deploy.sh</code>.</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag infrastructure">Infrastructure</span>
<span className="tag">EKS</span>
<span className="tag">Karpenter</span>
<span className="tag">ArgoCD</span>
<span className="tag">Graviton</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/databases/valkey-on-eks/infra" className="showcase-link">
<span>Deploy Infrastructure</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">🔁</div>
<div className="showcase-content">
<h3>Replication Cluster Verification</h3>
<p className="showcase-description">Confirm the 1-primary + N-replicas StatefulSet is healthy, run the smoke-test workload, and verify the read/write split end-to-end.</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag guide">Topology</span>
<span className="tag">Read/Write Split</span>
<span className="tag">HA</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/databases/valkey-on-eks/replication" className="showcase-link">
<span>View Guide</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">🧩</div>
<div className="showcase-content">
<h3>Cluster Mode (Self-Managed)</h3>
<p className="showcase-description">3 primaries × 1 replica with hash-slot sharding and gossip-based failover. Plain Kubernetes manifests — no Helm chart, no operator. Based on <a href="https://github.com/valkey-io/valkey-helm/pull/51">valkey-helm PR #51</a>.</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag performance">Sharding</span>
<span className="tag">Gossip</span>
<span className="tag">Multi-AZ</span>
<span className="tag">No Operator</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/databases/valkey-on-eks/cluster-mode" className="showcase-link">
<span>View Guide</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">⬆️</div>
<div className="showcase-content">
<h3>Upgrades</h3>
<p className="showcase-description">Chart bumps, Valkey minor/patch upgrades, Karpenter AMI rollovers — all PDB-protected with rolling pod restarts and an ArgoCD-driven rollback path.</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag guide">Runbook</span>
<span className="tag">ArgoCD</span>
<span className="tag">Rolling Update</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/databases/valkey-on-eks/upgrades" className="showcase-link">
<span>View Runbook</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

<div className="showcase-card">
<div className="showcase-header">
<div className="showcase-icon">📦</div>
<div className="showcase-content">
<h3>EC2 → EKS Migration</h3>
<p className="showcase-description">Move a self-managed Valkey or Redis instance from EC2 onto EKS via offline RDB snapshot through S3 and a restore initContainer.</p>
</div>
</div>
<div className="showcase-tags">
<span className="tag guide">Runbook</span>
<span className="tag">Migration</span>
<span className="tag">S3</span>
</div>
<div className="showcase-footer">
<a href="/data-on-eks/docs/datastacks/databases/valkey-on-eks/ec2-migration" className="showcase-link">
<span>View Runbook</span>
<svg className="arrow-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
<path d="M6 3l5 5-5 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
</svg>
</a>
</div>
</div>

</div>

{/* End of showcase grid */}

## Topology Support Matrix

| Mode | Architecture | HA | Write scale | Use when | Status (this stack) |
|---|---|---|---|---|---|
| Standalone | 1 pod | ✗ | ✗ | Dev / test, ephemeral cache | Available — set `replica.enabled: false` |
| **Primary + Replica** | 1 primary + N replicas | Manual failover | ✗ | Read-heavy, < 25 GB dataset, Lua scripts, multi-key ops | **Default deployment** (official chart) |
| Sentinel | Primary + replicas + Sentinel | ✓ | ✗ | HA without sharding | Not yet in official chart |
| **Cluster Mode** | 3+ primaries × 1+ replica each | ✓ | ✓ | Large datasets, write throughput | **Self-managed manifests** — see [Cluster Mode guide](./cluster-mode.md). Will switch to official chart when [valkey-helm #18](https://github.com/valkey-io/valkey-helm/issues/18) lands. |

## Quick Reference

| Knob | Default | Notes |
|---|---|---|
| Pods | 4 (1 primary + 3 replicas) | Set via `replica.replicas` in `helm-values/valkey.yaml` |
| Nodes | 3+ (one per AZ) | Karpenter provisions on demand from `r7g`/`r8g` family |
| Instance type | `r7g.large` (sized for 12 GiB workload memory) | Bump `resources.requests.memory` and let Karpenter pick a larger size for production |
| Storage | 50 GiB `gp3` EBS PVC per pod | Resizable; uses `volumeBindingMode: WaitForFirstConsumer` |
| Client port | `6379` | Application connects here |
| Metrics port | `9121` | Prometheus exporter sidecar (`oliver006/redis_exporter`) |
| Per-pod DNS | `valkey-N.valkey-headless.valkey.svc.cluster.local` | Stable across pod restarts |
| Endpoints | `valkey` (write) · `valkey-read` (replicas, read) · `valkey-headless` (per-pod) | Two-Service read/write split |
