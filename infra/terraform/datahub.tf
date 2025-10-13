locals {
  datahub_service_account = "datahub-sa"
  datahub_namespace       = "datahub"

  datahub_values = templatefile("${path.module}/helm-values/datahub.yaml", {
    s3_bucket_name = module.s3_bucket.s3_bucket_id
    region         = local.region
  })

  opensearch_values = templatefile("${path.module}/helm-values/opensearch.yaml", {})

  postgresql_manifests = provider::kubernetes::manifest_decode_multi(
    templatefile("${path.module}/manifests/datahub/postgresql.yaml", {
      namespace = local.datahub_namespace
    })
  )
}

#---------------------------------------------------------------
# DataHub Namespace
#---------------------------------------------------------------
resource "kubectl_manifest" "datahub_namespace" {
  count = var.enable_datahub ? 1 : 0

  yaml_body = templatefile("${path.module}/manifests/datahub/namespace.yaml", {
    namespace = local.datahub_namespace
  })
}

#---------------------------------------------------------------
# Database Secrets
#---------------------------------------------------------------

resource "kubernetes_secret" "postgresql_secrets" {
  count = var.enable_datahub ? 1 : 0

  metadata {
    name      = "postgresql-secrets"
    namespace = local.datahub_namespace
  }

  data = {
    postgres-password    = random_password.postgres.result
    replication-password = random_password.postgres_replication.result
    password             = random_password.postgres_user.result
  }

  type = "Opaque"

  depends_on = [kubectl_manifest.datahub_namespace[0]]
}

resource "random_password" "postgres" {
  length  = 16
  special = true
}

resource "random_password" "postgres_replication" {
  length  = 16
  special = true
}

resource "random_password" "postgres_user" {
  length  = 16
  special = true
}

#---------------------------------------------------------------
# Pod Identity for DataHub S3 Access
#---------------------------------------------------------------
module "datahub_pod_identity" {
  count   = var.enable_datahub ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "datahub"

  additional_policy_arns = {
    s3_access = aws_iam_policy.datahub_s3[0].arn
  }

  associations = {
    datahub = {
      cluster_name    = module.eks.cluster_name
      namespace       = local.datahub_namespace
      service_account = local.datahub_service_account
    }
  }
}

#---------------------------------------------------------------
# IAM Policy for S3 Read Access
#---------------------------------------------------------------
resource "aws_iam_policy" "datahub_s3" {
  count       = var.enable_datahub ? 1 : 0
  name        = "datahub-s3-policy"
  description = "IAM Policy for DataHub S3 access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetObjectVersion"
        ]
        Resource = [
          module.s3_bucket.s3_bucket_arn,
          "${module.s3_bucket.s3_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "glue:GetDatabases",
          "glue:GetDatabase",
          "glue:GetTables",
        "glue:GetTable"],
        Resource = ["*"]
      }
    ]
  })
}

#---------------------------------------------------------------
# PostgreSQL StatefulSet and Service
#---------------------------------------------------------------
resource "kubectl_manifest" "postgresql" {
  for_each = { for idx, manifest in local.postgresql_manifests : idx => manifest if var.enable_datahub }

  yaml_body = yamlencode(each.value)

  depends_on = [
    kubectl_manifest.datahub_namespace[0],
    kubernetes_secret.postgresql_secrets[0]
  ]
}

#---------------------------------------------------------------
# OpenSearch Application
#---------------------------------------------------------------
resource "kubectl_manifest" "opensearch" {
  count = var.enable_datahub ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/opensearch.yaml", {
    user_values_yaml = indent(8, local.opensearch_values)
  })

  depends_on = [
    helm_release.argocd,
    kubectl_manifest.datahub_namespace[0]
  ]
}

#---------------------------------------------------------------
# DataHub Application
#---------------------------------------------------------------
resource "kubectl_manifest" "datahub" {
  count = var.enable_datahub ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/datahub.yaml", {
    user_values_yaml = indent(8, local.datahub_values)
  })

  depends_on = [
    helm_release.argocd,
    kubectl_manifest.postgresql,
    kubectl_manifest.opensearch[0],
    module.datahub_pod_identity[0],
    aws_iam_policy.datahub_s3[0],
    kubectl_manifest.strimzi_kafka_operator
  ]
}