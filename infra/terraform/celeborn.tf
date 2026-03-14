locals {
  celeborn_namespace       = "celeborn"
  celeborn_service_account = "celeborn"
  celeborn_values = yamldecode(templatefile("${path.module}/helm-values/celeborn.yaml", {
    s3_bucket        = module.data_bucket.s3_bucket_id
    s3_bucket_region = module.data_bucket.s3_bucket_region
    az               = local.s3_express_zone_name # does NOT need to be the same as local express zone. This is done for convenience only.
    celeborn_role = module.celeborn_irsa.arn
  }))
}

#---------------------------------------------------------------
# Celeborn Namespace
#---------------------------------------------------------------
resource "kubernetes_namespace" "celeborn" {
  count = var.enable_celeborn ? 1 : 0

  metadata {
    name = local.celeborn_namespace
  }
}

# we need to use IRSA because celeborn does not support pod identity yet (java sdk 1.x)
#---------------------------------------------------------------
# IRSA for Celeborn
#---------------------------------------------------------------

module "celeborn_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"
  name    = "${module.eks.cluster_name}-celeborn"

  policies = {
    s3_access = aws_iam_policy.celeborn_s3[0].arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${local.celeborn_namespace}:${local.celeborn_service_account}"]
    }
  }
}

#---------------------------------------------------------------
# IAM Policy for S3 Read/Write Access
#---------------------------------------------------------------
resource "aws_iam_policy" "celeborn_s3" {
  count       = var.enable_celeborn ? 1 : 0
  name        = "celeborn-s3-policy"
  description = "IAM Policy for Celeborn S3 read/write access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          module.data_bucket.s3_bucket_arn,
          "${module.data_bucket.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}

#---------------------------------------------------------------
# Celeborn Manifests
#---------------------------------------------------------------
resource "kubectl_manifest" "celeborn_manifests" {
  count = var.enable_celeborn ? 1 : 0
  yaml_body = templatefile("${path.module}/manifests/celeborn/storageclass.yaml", {
    deployment_id = var.deployment_id
  })

  depends_on = [
    kubernetes_namespace.celeborn[0]
  ]
}

#---------------------------------------------------------------
# Celeborn Application
#---------------------------------------------------------------
resource "kubectl_manifest" "celeborn" {
  count = var.enable_celeborn ? 1 : 0
  yaml_body = templatefile("${path.module}/argocd-applications/celeborn.yaml", {
    user_values_yaml = indent(8, yamlencode(local.celeborn_values))
  })

  depends_on = [
    helm_release.argocd,
    kubernetes_namespace.celeborn[0],
    module.celeborn_irsa[0]
  ]
}
