locals {
  trino_namespace = "trino"
  trino_sa        = "trino-sa"
}

#---------------------------------------------------------------
# S3 Buckets for Trino
#---------------------------------------------------------------
module "trino_s3_bucket" {
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
}

module "trino_exchange_bucket" {
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
}

#---------------------------------------------------------------
# IAM Policies
#---------------------------------------------------------------
data "aws_iam_policy_document" "trino_s3_access" {

  statement {
    sid    = "TrinoDataBucketAccess"
    effect = "Allow"
    resources = [
      "arn:aws:s3:::${module.trino_s3_bucket.s3_bucket_id}",
      "arn:aws:s3:::${module.trino_s3_bucket.s3_bucket_id}/*"
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

  statement {
    sid    = "TrinoExchangeBucketAccess"
    effect = "Allow"
    resources = [
      "arn:aws:s3:::${module.trino_exchange_bucket.s3_bucket_id}",
      "arn:aws:s3:::${module.trino_exchange_bucket.s3_bucket_id}/*"
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
# Pod Identity for Trino
#---------------------------------------------------------------
resource "aws_iam_policy" "trino_s3_policy" {
  name        = "${local.name}-trino-s3-policy"
  description = "IAM policy for Trino to access S3 data bucket"
  policy      = data.aws_iam_policy_document.trino_s3_access.json
  tags        = local.tags
}

resource "aws_iam_policy" "trino_exchange_policy" {
  name        = "${local.name}-trino-exchange-policy"
  description = "IAM policy for Trino to access S3 exchange bucket"
  policy      = data.aws_iam_policy_document.trino_exchange_access.json
  tags        = local.tags
}

#---------------------------------------------------------------
# Pod Identity for Trino
#---------------------------------------------------------------
module "trino_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "trino"

  additional_policy_arns = {
    s3_policy       = aws_iam_policy.trino_s3_policy.arn
    exchange_policy = aws_iam_policy.trino_exchange_policy.arn
    glue_policy     = "arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess"
  }

  associations = {
    trino = {
      cluster_name    = module.eks.cluster_name
      namespace       = local.trino_namespace
      service_account = local.trino_sa
    }
  }
}

#---------------------------------------------------------------
# Trino ArgoCD Application
#---------------------------------------------------------------
resource "kubectl_manifest" "trino" {

  yaml_body = templatefile("${path.module}/argocd-applications/trino.yaml", {
    user_values_yaml = indent(8, yamlencode(yamldecode(templatefile("${path.module}/helm-values/trino.yaml", {
      region             = local.region
      trino_s3_bucket_id = module.trino_s3_bucket.s3_bucket_id
      exchange_bucket_id = module.trino_exchange_bucket.s3_bucket_id
      trino_irsa_arn     = module.trino_pod_identity.iam_role_arn
      trino_sa           = local.trino_sa
      trino_namespace    = local.trino_namespace
    }))))
  })

  depends_on = [
    helm_release.argocd,
    module.trino_pod_identity,
    module.trino_s3_bucket,
    module.trino_exchange_bucket
  ]
}

#---------------------------------------------------------------
# KEDA Operator for Trino Autoscaling (Optional)
#---------------------------------------------------------------
resource "kubectl_manifest" "keda_operator" {

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
  value       = module.trino_s3_bucket.s3_bucket_id
}

output "trino_exchange_bucket_id" {
  description = "Trino S3 exchange bucket ID"
  value       = module.trino_exchange_bucket.s3_bucket_id
}
