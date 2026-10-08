# =============================================================================
# Apache Polaris (incubating) on EKS
#
# Deploys Apache Polaris as an Iceberg REST catalog via the OFFICIAL community
# Helm chart (apache/polaris), fronted by ArgoCD like every other addon in this
# repo. Polaris persists catalog metadata in an in-cluster Postgres and stores
# table data/metadata on a dedicated, private S3 warehouse bucket.
#
# Single Terraform variable: `var.enable_polaris`. When true this file creates:
#   - a private S3 warehouse bucket (SSE, all public access blocked)
#   - an IAM policy + EKS Pod Identity for the polaris-sa ServiceAccount
#     (read/write on the warehouse bucket only — no static keys)
#   - a Postgres metastore (manifests/polaris/postgres.yaml)
#   - a one-shot bootstrap Job (realm POLARIS + root principal)
#   - the Polaris ArgoCD Application (helm-values/polaris.yaml)
#   - a Job that creates the Iceberg catalog on S3 (stsUnavailable=true)
#   - Trino wiring: a 'polaris' Iceberg REST catalog + the OAuth credential
#     Secret, and a policy attachment giving Trino's existing role write access
#     to the warehouse bucket (Trino writes the data files; Polaris the metadata)
#
# The Polaris chart deploys ClusterIP services ONLY. Reach Polaris with
# `kubectl port-forward`. For production, front it with an INTERNAL load
# balancer scoped to your organization's network — never a public endpoint.
# =============================================================================

locals {
  polaris_namespace       = "polaris"
  polaris_service_account = "polaris-sa"
  polaris_catalog         = "demo"

  polaris_values_rendered = templatefile("${path.module}/helm-values/polaris.yaml", {
    namespace            = local.polaris_namespace
    service_account_name = local.polaris_service_account
    region               = local.region
  })

  polaris_postgres_manifests = provider::kubernetes::manifest_decode_multi(
    templatefile("${path.module}/manifests/polaris/postgres.yaml", {
      namespace = local.polaris_namespace
    })
  )
}

#---------------------------------------------------------------
# Polaris Namespace
#---------------------------------------------------------------
resource "kubectl_manifest" "polaris_namespace" {
  count = var.enable_polaris ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: ${local.polaris_namespace}
      labels:
        name: ${local.polaris_namespace}
  YAML

  depends_on = [module.eks]
}

#---------------------------------------------------------------
# S3 Warehouse Bucket — private, encrypted, no public access.
# Holds Iceberg table data + metadata under s3://<bucket>/<catalog>/.
#---------------------------------------------------------------
module "polaris_warehouse_bucket" {
  count = var.enable_polaris ? 1 : 0

  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.0"

  bucket_prefix = "${local.name}-polaris-warehouse-"

  # For example only - please evaluate for your environment
  force_destroy = true

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }
}

#---------------------------------------------------------------
# IAM — Polaris reads/writes Iceberg metadata on the warehouse bucket.
#---------------------------------------------------------------
data "aws_iam_policy_document" "polaris_warehouse_access" {
  count = var.enable_polaris ? 1 : 0

  statement {
    sid    = "PolarisWarehouseBucketAccess"
    effect = "Allow"
    resources = [
      module.polaris_warehouse_bucket[0].s3_bucket_arn,
      "${module.polaris_warehouse_bucket[0].s3_bucket_arn}/*",
    ]
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload",
    ]
  }
}

resource "aws_iam_policy" "polaris_warehouse" {
  count = var.enable_polaris ? 1 : 0

  name        = "${local.name}-polaris-warehouse-s3"
  description = "IAM policy for Apache Polaris to read/write Iceberg data on the warehouse bucket"
  policy      = data.aws_iam_policy_document.polaris_warehouse_access[0].json
  tags        = local.tags
}

#---------------------------------------------------------------
# Pod Identity — associates polaris-sa with the warehouse IAM policy.
# The chart creates the ServiceAccount (serviceAccount.create=true); this
# association binds it to the role. No SA annotation needed with Pod Identity.
#---------------------------------------------------------------
module "polaris_pod_identity" {
  count = var.enable_polaris ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name = "polaris"

  additional_policy_arns = {
    warehouse = aws_iam_policy.polaris_warehouse[0].arn
  }

  associations = {
    polaris = {
      cluster_name    = module.eks.cluster_name
      namespace       = local.polaris_namespace
      service_account = local.polaris_service_account
    }
  }
}

#---------------------------------------------------------------
# Secrets — generated once, stored in Kubernetes Secrets. Password literals
# never appear in helm-values or manifests.
#   - polaris-postgres-credentials: superuser + polaris DB role passwords
#   - polaris-credentials:          root principal client id/secret
#   - polaris-persistence:          JDBC url/user/pass consumed by the chart
#---------------------------------------------------------------
resource "random_password" "polaris_postgres_superuser" {
  count = var.enable_polaris ? 1 : 0

  length  = 24
  special = false
}

resource "random_password" "polaris_db" {
  count = var.enable_polaris ? 1 : 0

  length  = 24
  special = false
}

resource "random_password" "polaris_root_secret" {
  count = var.enable_polaris ? 1 : 0

  length  = 48
  special = false
}

resource "kubernetes_secret" "polaris_postgres_credentials" {
  count = var.enable_polaris ? 1 : 0

  metadata {
    name      = "polaris-postgres-credentials"
    namespace = local.polaris_namespace
  }

  data = {
    POSTGRES_PASSWORD   = random_password.polaris_postgres_superuser[0].result
    POLARIS_DB_PASSWORD = random_password.polaris_db[0].result
  }

  type = "Opaque"

  depends_on = [kubectl_manifest.polaris_namespace]
}

resource "kubernetes_secret" "polaris_credentials" {
  count = var.enable_polaris ? 1 : 0

  metadata {
    name      = "polaris-credentials"
    namespace = local.polaris_namespace
  }

  data = {
    ROOT_CLIENT_ID     = "root"
    ROOT_CLIENT_SECRET = random_password.polaris_root_secret[0].result
  }

  type = "Opaque"

  depends_on = [kubectl_manifest.polaris_namespace]
}

# The Polaris chart's relational-jdbc persistence reads connection details from
# this Secret (keys: username / password / jdbcUrl — see helm-values/polaris.yaml).
resource "kubernetes_secret" "polaris_persistence" {
  count = var.enable_polaris ? 1 : 0

  metadata {
    name      = "polaris-persistence"
    namespace = local.polaris_namespace
  }

  data = {
    username = "polaris"
    password = random_password.polaris_db[0].result
    jdbcUrl  = "jdbc:postgresql://polaris-postgres.${local.polaris_namespace}.svc.cluster.local:5432/polaris"
  }

  type = "Opaque"

  depends_on = [kubectl_manifest.polaris_namespace]
}

#---------------------------------------------------------------
# Postgres metastore (Deployment + PVC + Service + init ConfigMap)
#---------------------------------------------------------------
resource "kubectl_manifest" "polaris_postgres" {
  for_each = { for idx, manifest in local.polaris_postgres_manifests : idx => manifest if var.enable_polaris }

  yaml_body = yamlencode(each.value)

  depends_on = [
    kubectl_manifest.polaris_namespace,
    kubernetes_secret.polaris_postgres_credentials,
  ]
}

#---------------------------------------------------------------
# Bootstrap Job — realm POLARIS + root principal into the metastore.
#---------------------------------------------------------------
resource "kubectl_manifest" "polaris_bootstrap" {
  count = var.enable_polaris ? 1 : 0

  yaml_body = templatefile("${path.module}/manifests/polaris/bootstrap-job.yaml", {
    namespace = local.polaris_namespace
  })

  depends_on = [
    kubectl_manifest.polaris_postgres,
    kubernetes_secret.polaris_postgres_credentials,
    kubernetes_secret.polaris_credentials,
  ]
}

#---------------------------------------------------------------
# Polaris ArgoCD Application — official apache/polaris chart, ClusterIP only.
# The server's wait-bootstrap init container gates startup on the bootstrap Job.
#---------------------------------------------------------------
resource "kubectl_manifest" "polaris" {
  count = var.enable_polaris ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/polaris.yaml", {
    user_values_yaml = indent(8, local.polaris_values_rendered)
  })

  depends_on = [
    helm_release.argocd,
    kubectl_manifest.polaris_namespace,
    kubectl_manifest.polaris_bootstrap,
    kubernetes_secret.polaris_persistence,
    module.polaris_pod_identity,
    module.polaris_warehouse_bucket,
  ]
}

#---------------------------------------------------------------
# Catalog-create Job — creates the '${catalog}' Iceberg catalog on S3.
#---------------------------------------------------------------
resource "kubectl_manifest" "polaris_catalog_create" {
  count = var.enable_polaris ? 1 : 0

  yaml_body = templatefile("${path.module}/manifests/polaris/catalog-job.yaml", {
    namespace        = local.polaris_namespace
    catalog          = local.polaris_catalog
    warehouse_bucket = module.polaris_warehouse_bucket[0].s3_bucket_id
    region           = local.region
  })

  depends_on = [
    kubectl_manifest.polaris,
    kubernetes_secret.polaris_credentials,
  ]
}

#---------------------------------------------------------------
# Trino integration
#
# 1. Give Trino's existing Pod Identity role write access to the warehouse
#    bucket. Trino writes the Parquet data files; Polaris writes the Iceberg
#    metadata. Both need read/write on the same bucket.
# 2. Publish the Polaris OAuth2 client credential (root:<secret>) into the trino
#    namespace so the templated 'polaris' catalog can read it via ${ENV:...}.
#    The catalog itself is wired in helm-values/trino.yaml (gated on the same
#    variable) and consumed via Trino's chart-level envFrom.
#---------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "trino_polaris_warehouse" {
  count = var.enable_polaris ? 1 : 0

  role       = module.trino_pod_identity.iam_role_name
  policy_arn = aws_iam_policy.polaris_warehouse[0].arn
}

resource "kubernetes_secret" "trino_polaris_credentials" {
  count = var.enable_polaris ? 1 : 0

  metadata {
    name      = "trino-polaris-credentials"
    namespace = local.trino_namespace
  }

  data = {
    POLARIS_OAUTH2_CREDENTIAL = "root:${random_password.polaris_root_secret[0].result}"
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace.trino]
}

#---------------------------------------------------------------
# Outputs
#---------------------------------------------------------------
output "polaris_warehouse_bucket_id" {
  description = "Apache Polaris S3 warehouse bucket ID. Empty when enable_polaris is false."
  value       = try(module.polaris_warehouse_bucket[0].s3_bucket_id, "")
}

output "polaris_catalog_name" {
  description = "Apache Polaris Iceberg catalog name (also the Trino catalog name). Empty when enable_polaris is false."
  value       = var.enable_polaris ? local.polaris_catalog : ""
}
