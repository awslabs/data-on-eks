---
title: Semantic on EKS
sidebar_position: 0
---

# Semantic on EKS Stack

Foundation stack for the **[Apache Ossie (incubating) / Open Semantic Interchange (OSI)](https://github.com/[ORG PLACEHOLDER]/semantic-operator)** `semantic-operator`. It stands up the query engine, catalogs, and cache that the operator's [`datahub-polaris-trino`](https://github.com/[ORG PLACEHOLDER]/semantic-operator/blob/main/website/src/content/docs/examples/datahub-polaris-trino.md) example expects to already exist — deploy this stack once, then install the operator on top.

:::note
This stack provisions the semantic layer's **dependencies** — it does not deploy the semantic-operator itself. Install the operator afterwards with its own Helm chart (see [Next steps](#next-steps)).
:::

## Architecture Overview

On top of the shared base infrastructure (EKS + VPC + Karpenter + ArgoCD), this stack enables a Trino query engine, an Apache Polaris Iceberg REST catalog, DataHub for metadata/lineage, and an optional Valkey cache.

### Components

| Component | Role for the semantic layer | Chart / source |
|---|---|---|
| **[Trino](https://trino.io/)** | Distributed SQL engine the operator queries. Always deployed by the base infra with a Glue-backed `iceberg` catalog. | community `trinodb/charts` |
| **[Apache Polaris](https://polaris.apache.org/) (incubating)** | Iceberg **REST catalog** (`polaris`) the `SemanticModel` binds to. Backed by an in-cluster Postgres metastore and a dedicated private S3 warehouse bucket. | official `apache/polaris` Helm chart |
| **[DataHub](https://datahubproject.io/)** | Metadata catalog / lineage. Used by `ossiectl` during model authoring. | community `datahubproject.io` chart |
| **[Valkey](https://valkey.io/)** | Optional result cache for the semantic server. | official `valkey-io` chart |

Every service runs as a **ClusterIP** — see [Security posture](#security-posture).

### Catalog topology

Trino exposes two Iceberg catalogs after deploy:

- **`iceberg`** — Glue-backed (base infra default). The `datahub-polaris-trino` example uses this as the *source* it copies demo data **from**.
- **`polaris`** — Apache Polaris REST catalog on a dedicated S3 warehouse. The example copies data **into** this, and the `SemanticModel` binds to `polaris.osi_demo.*`.

Polaris is created with `stsUnavailable=true`: it never vends credentials. Trino writes the Parquet data files with its own EKS Pod Identity role; Polaris writes the Iceberg metadata with its own. No static keys anywhere.

## Prerequisites

| Requirement | Version | Purpose |
|---|---|---|
| AWS CLI | v2.x | AWS resource management |
| Terraform | ≥ 1.0 | Infrastructure as Code |
| kubectl | ≥ 1.28 | Kubernetes management |
| Helm | ≥ 3.x | Chart installs (OCI pulls) |

:::warning Docker credential helper
Helm pulls some charts (e.g. Karpenter) from public OCI registries such as `oci://public.ecr.aws`. If `~/.docker/config.json` sets a `credsStore` / `credHelpers` whose `docker-credential-*` binary is **not on your PATH** (common when Docker Desktop is not installed/running), those anonymous pulls fail and the deploy stalls. `deploy.sh` runs a preflight check that detects this and disables the broken helper for the deployment (a backup is written to `~/.docker/config.json.doeks-bak`).
:::

## Deployment

```bash
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/data-stacks/semantic-on-eks

export AWS_REGION=us-west-2   # default; must match data-stack.tfvars
./deploy.sh
```

`deploy.sh` sources the shared engine (`infra/terraform/install.sh`), which copies the base `infra/terraform/` into a local `terraform/_local/` working directory, overlays this stack's files, then applies the infrastructure in dependency order: **VPC → EKS → Karpenter → workloads**. Bringing Karpenter up before the workloads guarantees compute capacity exists when Polaris, Trino, DataHub, and Valkey pods schedule. The kubeconfig is written to `kubeconfig.yaml`.

To change which components deploy, edit `terraform/data-stack.tfvars`:

```hcl
enable_polaris = true
enable_datahub = true
enable_valkey  = true
```

When the deploy finishes, it prints a **deployment summary** listing the provisioned nodes (by NodeGroupType), ArgoCD application health, the core stack pods, and the port-forward access endpoints.

## Verify

```bash
export KUBECONFIG=$PWD/kubeconfig.yaml

# Polaris server + its metastore + the bootstrap/catalog jobs
kubectl -n polaris get pods,job

# Trino sees both catalogs (expect: iceberg, polaris, system, tpcds, tpch)
POD=$(kubectl -n trino get pods -o name | grep coordinator | head -1 | cut -d/ -f2)
kubectl -n trino exec "$POD" -c trino-coordinator -- trino --execute "SHOW CATALOGS"

# DataHub GMS + frontend
kubectl -n datahub get pods
```

End-to-end check against the Polaris catalog through Trino:

```bash
kubectl -n trino exec "$POD" -c trino-coordinator -- trino --execute "
CREATE SCHEMA IF NOT EXISTS polaris.demo_check;
CREATE TABLE polaris.demo_check.t (id int, name varchar);
INSERT INTO polaris.demo_check.t VALUES (1,'hello'),(2,'world');
SELECT count(*) FROM polaris.demo_check.t;
DROP TABLE polaris.demo_check.t;
DROP SCHEMA polaris.demo_check;
"
```

This exercises the full chain: Trino writes Parquet to the S3 warehouse while Polaris writes the Iceberg metadata. The catalog is created with `polaris.config.drop-with-purge.enabled=true` and the `catalog_admin` role is granted `CATALOG_MANAGE_CONTENT`, so `DROP TABLE` (which Trino issues with `purgeRequested=true`) succeeds.

Reach any UI/endpoint by port-forward:

```bash
kubectl -n polaris port-forward svc/polaris 8181:8181                        # Iceberg REST API
kubectl -n trino   port-forward svc/trino 8080:8080                          # Trino UI at :8080/ui
kubectl -n datahub port-forward svc/datahub-datahub-frontend 9002:9002       # DataHub UI
```

## Next steps

Install the semantic-operator against this stack (from the `semantic-operator` repo):

```bash
helm upgrade --install semantic-operator charts/semantic-operator \
  --namespace semantic-system --create-namespace \
  --set server.auth.allowInsecureHeaderAuth=true \
  --set engine.type=trino \
  --set engine.host=trino.trino.svc.cluster.local \
  --set image.repository=<acct>.dkr.ecr.<region>.amazonaws.com/semantic-operator \
  --set image.tag=<tag>
```

Then follow the example's data-load and model steps. This stack already provides the Polaris catalog, S3 warehouse, Pod Identity roles, and DataHub the example's scripts assume — you do not need to run its `eks-up.sh` / `trino-catalog.sh` (those are already wired here by Terraform).

## Security posture

- **No public endpoints.** Every service is `ClusterIP`; access is via `kubectl port-forward`. The semantic server must never be exposed externally (it trusts an `X-Semantic-Role` header). For production, front services with an **internal** load balancer scoped to your organization's network — never a public/internet-facing one.
- **No public S3.** The Polaris warehouse bucket blocks all public access and is SSE-encrypted.
- **No static credentials.** AWS access uses EKS Pod Identity; database and Polaris root secrets are generated by Terraform into Kubernetes Secrets and never appear in any manifest or values file.

## Teardown

```bash
cd data-stacks/semantic-on-eks
./cleanup.sh
```

:::caution
The Polaris warehouse and Trino buckets are created with `force_destroy = true` for example convenience — evaluate this for your environment before using in production.
:::
