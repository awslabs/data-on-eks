locals {
  trino_namespace = "trino"
  trino_sa       = "trino-sa"
}

#---------------------------------------------------------------
# S3 Buckets for Trino
#---------------------------------------------------------------
module "trino_s3_bucket" {
  count   = var.enable_trino ? 1 : 0
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  bucket_prefix = "${local.name}-trino-data-"

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

  tags = local.tags
}

module "trino_exchange_bucket" {
  count   = var.enable_trino ? 1 : 0
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  bucket_prefix = "${local.name}-trino-exchange-"

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

  tags = local.tags
}

#---------------------------------------------------------------
# IAM Policy Documents
#---------------------------------------------------------------
data "aws_iam_policy_document" "trino_s3_access" {
  count = var.enable_trino ? 1 : 0

  statement {
    sid    = "TrinoDataBucketAccess"
    effect = "Allow"
    resources = [
      "arn:aws:s3:::${module.trino_s3_bucket[0].s3_bucket_id}",
      "arn:aws:s3:::${module.trino_s3_bucket[0].s3_bucket_id}/*"
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
      "s3:AbortMultipartUpload"
    ]
  }

  statement {
    sid       = "TrinoGeneralS3Access"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "s3:ListAllMyBuckets",
      "s3:GetBucketLocation"
    ]
  }
}

data "aws_iam_policy_document" "trino_exchange_access" {
  count = var.enable_trino ? 1 : 0

  statement {
    sid    = "TrinoExchangeBucketAccess"
    effect = "Allow"
    resources = [
      "arn:aws:s3:::${module.trino_exchange_bucket[0].s3_bucket_id}",
      "arn:aws:s3:::${module.trino_exchange_bucket[0].s3_bucket_id}/*"
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
      "s3:AbortMultipartUpload"
    ]
  }
}

#---------------------------------------------------------------
# IAM Policies
#---------------------------------------------------------------
resource "aws_iam_policy" "trino_s3_policy" {
  count       = var.enable_trino ? 1 : 0
  name        = "${local.name}-trino-s3-policy"
  description = "IAM policy for Trino to access S3 data bucket"
  policy      = data.aws_iam_policy_document.trino_s3_access[0].json
  tags        = local.tags
}

resource "aws_iam_policy" "trino_exchange_policy" {
  count       = var.enable_trino ? 1 : 0
  name        = "${local.name}-trino-exchange-policy"
  description = "IAM policy for Trino to access S3 exchange bucket"
  policy      = data.aws_iam_policy_document.trino_exchange_access[0].json
  tags        = local.tags
}

#---------------------------------------------------------------
# IRSA for Trino
#---------------------------------------------------------------
module "trino_irsa" {
  count   = var.enable_trino ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.52"

  role_name = "${module.eks.cluster_name}-trino"

  role_policy_arns = {
    s3_policy       = aws_iam_policy.trino_s3_policy[0].arn
    exchange_policy = aws_iam_policy.trino_exchange_policy[0].arn
    glue_policy     = "arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess"
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${local.trino_namespace}:${local.trino_sa}"]
    }
  }

  tags = local.tags
}

#---------------------------------------------------------------
# Trino ArgoCD Application
#---------------------------------------------------------------
resource "kubectl_manifest" "trino" {
  count = var.enable_trino ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/trino.yaml", {
    user_values_yaml = indent(8, yamlencode(yamldecode(templatefile("${path.module}/helm-values/trino.yaml", {
      region              = local.region
      trino_s3_bucket_id  = module.trino_s3_bucket[0].s3_bucket_id
      exchange_bucket_id  = module.trino_exchange_bucket[0].s3_bucket_id
      trino_irsa_arn      = module.trino_irsa[0].iam_role_arn
      trino_sa            = local.trino_sa
      trino_namespace     = local.trino_namespace
    }))))
  })

  depends_on = [
    helm_release.argocd,
    module.trino_irsa,
    module.trino_s3_bucket,
    module.trino_exchange_bucket
  ]
}

#---------------------------------------------------------------
# KEDA Operator for Trino Autoscaling (Optional)
#---------------------------------------------------------------
resource "kubectl_manifest" "keda_operator" {
  count = var.enable_trino && var.enable_trino_keda ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/keda.yaml", {
    user_values_yaml = indent(8, yamlencode(yamldecode(templatefile("${path.module}/helm-values/keda.yaml", {}))))
  })

  depends_on = [
    helm_release.argocd,
  ]
}

#---------------------------------------------------------------
# Trino KEDA Autoscaling ScaledObject (Optional)
#---------------------------------------------------------------
resource "kubectl_manifest" "trino_keda_scaledobject" {
  count = var.enable_trino && var.enable_trino_keda ? 1 : 0

  yaml_body = templatefile("${path.module}/manifests/trino/keda-scaledobject.yaml", {
    trino_namespace = local.trino_namespace
  })

  depends_on = [
    kubectl_manifest.trino,
    kubectl_manifest.keda_operator
  ]
}

#---------------------------------------------------------------
# Outputs
#---------------------------------------------------------------
output "trino_s3_bucket_id" {
  description = "Trino S3 data bucket ID"
  value       = var.enable_trino ? module.trino_s3_bucket[0].s3_bucket_id : null
}

output "trino_exchange_bucket_id" {
  description = "Trino S3 exchange bucket ID"
  value       = var.enable_trino ? module.trino_exchange_bucket[0].s3_bucket_id : null
}

output "trino_irsa_arn" {
  description = "IAM Role ARN for Trino IRSA"
  value       = var.enable_trino ? module.trino_irsa[0].iam_role_arn : null
}