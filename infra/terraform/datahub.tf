locals {
  datahub_service_account = "datahub-sa"
  datahub_namespace = "datahub"
  
  datahub_values = templatefile("${path.module}/helm-values/datahub.yaml", {
    s3_bucket_name = module.s3_bucket.s3_bucket_id
    region = local.region
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
  yaml_body = templatefile("${path.module}/manifests/datahub/namespace.yaml", {
    namespace = local.datahub_namespace
  })
}

#---------------------------------------------------------------
# Database Secrets
#---------------------------------------------------------------

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
          "s3:ListBucket",
          "s3:GetObjectVersion"
        ]
        Resource = [
          module.s3_bucket.s3_bucket_arn,
          "${module.s3_bucket.s3_bucket_arn}/*"
        ]
      },
      {
      Effect ="Allow",
      Action =[
        "glue:GetDatabases",
        "glue:GetDatabase",
        "glue:GetTables", 
        "glue:GetTable"],
      Resource =  ["*"]
      }
    ]
  })
}

#---------------------------------------------------------------
# PostgreSQL StatefulSet and Service
#---------------------------------------------------------------
resource "kubectl_manifest" "postgresql" {
  for_each = { for idx, manifest in local.postgresql_manifests : idx => manifest }
  
  yaml_body = yamlencode(each.value)
  
  depends_on = [
    kubectl_manifest.datahub_namespace,
    kubernetes_secret.postgresql_secrets
  ]
}

#---------------------------------------------------------------
# OpenSearch Application
#---------------------------------------------------------------
resource "kubectl_manifest" "opensearch" {
  yaml_body = templatefile("${path.module}/argocd-applications/opensearch.yaml", {
    user_values_yaml = indent(8, local.opensearch_values)
  })

  depends_on = [
    helm_release.argocd,
    kubectl_manifest.datahub_namespace
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
    kubectl_manifest.postgresql,
    kubectl_manifest.opensearch,
    module.datahub_pod_identity,
    aws_iam_policy.datahub_s3,
    kubectl_manifest.strimzi_kafka_operator
  ]
}

# Need glue a database as a Iceberg Catalog until https://github.com/datahub-project/datahub/issues/14849 is addressed

#---------------------------------------------------------------
# Glue Database for Iceberg Tables
#---------------------------------------------------------------
resource "aws_glue_catalog_database" "data_on_eks" {
  name        = "data-on-eks"
  description = "Database for Data on EKS Iceberg tables"
}

#---------------------------------------------------------------
# IAM Role for Glue Crawler
#---------------------------------------------------------------
resource "aws_iam_role" "glue_crawler_role" {
  name = "${local.name}-glue-crawler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })

  tags = local.tags
}

#---------------------------------------------------------------
# IAM Policy for Glue Crawler S3 Access
#---------------------------------------------------------------
resource "aws_iam_policy" "glue_crawler_s3_policy" {
  name        = "${local.name}-glue-crawler-s3-policy"
  description = "IAM Policy for Glue Crawler S3 access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${module.s3_bucket.s3_bucket_arn}/iceberg-warehouse/*"
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceAccount" = local.account_id
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          module.s3_bucket.s3_bucket_arn
        ]
      }
    ]
  })
}

#---------------------------------------------------------------
# Attach Policies to Glue Crawler Role
#---------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue_crawler_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "glue_crawler_s3_policy" {
  role       = aws_iam_role.glue_crawler_role.name
  policy_arn = aws_iam_policy.glue_crawler_s3_policy.arn
}

#---------------------------------------------------------------
# Glue Crawler for Iceberg Tables
#---------------------------------------------------------------
resource "aws_glue_crawler" "iceberg_crawler" {
  database_name = aws_glue_catalog_database.data_on_eks.name
  name          = "${local.name}-iceberg-crawler"
  role          = aws_iam_role.glue_crawler_role.arn

  iceberg_target {
    paths                     = ["s3://${module.s3_bucket.s3_bucket_id}/iceberg-warehouse/"]
    maximum_traversal_depth   = 10
  }

  schedule = "cron(0 * * * ? *)"  # Every hour

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  tags = local.tags
}
