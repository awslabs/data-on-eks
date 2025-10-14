locals {
  celeborn_namespace       = "celeborn"
  celeborn_service_account = "celeborn"
  celeborn_values = yamldecode(templatefile("${path.module}/helm-values/celeborn.yaml", {
    s3_bucket = module.s3_bucket.s3_bucket_id
    s3_bucket_region = module.s3_bucket.s3_bucket_region
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

#---------------------------------------------------------------
# Pod Identity for Celeborn S3 Access
#---------------------------------------------------------------
module "celeborn_pod_identity" {
  count   = var.enable_celeborn ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "celeborn"

  additional_policy_arns = {
    s3_access = aws_iam_policy.celeborn_s3[0].arn
  }

  associations = {
    celeborn = {
      cluster_name    = module.eks.cluster_name
      namespace       = local.celeborn_namespace
      service_account = local.celeborn_service_account
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
          module.s3_bucket.s3_bucket_arn,
          "${module.s3_bucket.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}

#---------------------------------------------------------------
# Celeborn Manifests
#---------------------------------------------------------------
resource "kubectl_manifest" "celeborn_manifests" {
  count     = var.enable_celeborn ? 1 : 0
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
  count     = var.enable_celeborn ? 1 : 0
  yaml_body = templatefile("${path.module}/argocd-applications/celeborn.yaml", {
    user_values_yaml = indent(8, yamlencode(local.celeborn_values))
  })

  depends_on = [
    helm_release.argocd,
    kubernetes_namespace.celeborn[0],
    module.celeborn_pod_identity[0]
  ]
}
