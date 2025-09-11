locals {
  datahub_service_account = "datahub-sa"
  datahub_namespace = "datahub"
  
  datahub_prerequisites_values = templatefile("${path.module}/helm-values/datahub-prerequisites.yaml", {})
  
  datahub_values = templatefile("${path.module}/helm-values/datahub.yaml", {
    s3_bucket_name = module.s3_bucket.s3_bucket_id
    region = local.region
  })
}

#---------------------------------------------------------------
# DataHub Namespace
#---------------------------------------------------------------
resource "kubectl_manifest" "datahub_namespace" {
  yaml_body = templatefile("${path.module}/manifests/datahub/namespace.yaml", {
    namespace = local.datahub_namespace
  })
}

#---------------------------------------------------------------
# Database Secrets
#---------------------------------------------------------------
resource "kubernetes_secret" "mysql_secrets" {
  metadata {
    name      = "mysql-secrets"
    namespace = local.datahub_namespace
  }

  data = {
    mysql-root-password        = random_password.mysql_root.result
    mysql-replication-password = random_password.mysql_replication.result
    mysql-password            = random_password.mysql_user.result
  }

  type = "Opaque"
  
  depends_on = [kubectl_manifest.datahub_namespace]
}

resource "kubernetes_secret" "postgresql_secrets" {
  metadata {
    name      = "postgresql-secrets"
    namespace = local.datahub_namespace
  }

  data = {
    postgres-password    = random_password.postgres.result
    replication-password = random_password.postgres_replication.result
    password            = random_password.postgres_user.result
  }

  type = "Opaque"
  
  depends_on = [kubectl_manifest.datahub_namespace]
}

resource "random_password" "mysql_root" {
  length  = 16
  special = true
}

resource "random_password" "mysql_replication" {
  length  = 16
  special = true
}

resource "random_password" "mysql_user" {
  length  = 16
  special = true
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
  source = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "datahub"

  additional_policy_arns = {
    s3_access = aws_iam_policy.datahub_s3.arn
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
  name        = "datahub-s3-policy"
  description = "IAM Policy for DataHub S3 access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          module.s3_bucket.s3_bucket_arn,
          "${module.s3_bucket.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}

#---------------------------------------------------------------
# DataHub Prerequisites Application
#---------------------------------------------------------------
resource "kubectl_manifest" "datahub_prerequisites" {
  yaml_body = templatefile("${path.module}/argocd-applications/datahub-prerequisites.yaml", {
    user_values_yaml = indent(8, local.datahub_prerequisites_values)
  })

  depends_on = [
    helm_release.argocd,
    kubernetes_secret.mysql_secrets,
    kubernetes_secret.postgresql_secrets,
    kubectl_manifest.strimzi_kafka_operator
  ]
}

#---------------------------------------------------------------
# DataHub Application
#---------------------------------------------------------------
resource "kubectl_manifest" "datahub" {
  yaml_body = templatefile("${path.module}/argocd-applications/datahub.yaml", {
    user_values_yaml = indent(8, local.datahub_values)
  })

  depends_on = [
    helm_release.argocd,
    kubectl_manifest.datahub_prerequisites,
    module.datahub_pod_identity,
    aws_iam_policy.datahub_s3,
    kubectl_manifest.strimzi_kafka_operator
  ]
}
