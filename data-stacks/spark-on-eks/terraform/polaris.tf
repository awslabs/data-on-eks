# The Polaris chart creates ClusterIP services only. Use `kubectl port-forward`
# to connect. For production, use an internal load balancer. Do not use a public endpoint.

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

module "polaris_warehouse_bucket" {
  count = var.enable_polaris ? 1 : 0

  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.17.0"

  bucket_prefix = "${local.name}-polaris-warehouse-"

  # This value is for test stacks. Examine it before you use it in your environment.
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

# The chart creates the ServiceAccount. Pod Identity needs no ServiceAccount annotation.
module "polaris_pod_identity" {
  count = var.enable_polaris ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.9.0"

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

# Terraform generates the passwords so that helm-values and manifests contain no passwords.
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

# The relational-jdbc persistence of the chart reads the keys username, password,
# and jdbcUrl from this Secret. Refer to helm-values/polaris.yaml.
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

resource "kubectl_manifest" "polaris_postgres" {
  for_each = { for idx, manifest in local.polaris_postgres_manifests : idx => manifest if var.enable_polaris }

  yaml_body = yamlencode(each.value)

  depends_on = [
    kubectl_manifest.polaris_namespace,
    kubernetes_secret.polaris_postgres_credentials,
  ]
}

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

# The wait-bootstrap init container stops the server start until the bootstrap Job completes.
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

# Trino writes the Parquet data files and Polaris writes the Iceberg metadata.
# Thus Trino also needs write access to the warehouse bucket.
resource "aws_iam_role_policy_attachment" "trino_polaris_warehouse" {
  count = var.enable_polaris ? 1 : 0

  role       = module.trino_pod_identity.iam_role_name
  policy_arn = aws_iam_policy.polaris_warehouse[0].arn
}

# The 'polaris' catalog in helm-values/trino.yaml reads this credential with ${ENV:...}.
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

output "polaris_warehouse_bucket_id" {
  description = "Apache Polaris S3 warehouse bucket ID. Empty when enable_polaris is false."
  value       = try(module.polaris_warehouse_bucket[0].s3_bucket_id, "")
}

output "polaris_catalog_name" {
  description = "Apache Polaris Iceberg catalog name (also the Trino catalog name). Empty when enable_polaris is false."
  value       = var.enable_polaris ? local.polaris_catalog : ""
}
