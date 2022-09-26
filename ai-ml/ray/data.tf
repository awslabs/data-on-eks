data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}

data "aws_acm_certificate" "issued" {
  count = var.acm_certificate_domain == null ? 0 : 1

  domain   = var.acm_certificate_domain
  statuses = ["ISSUED"]
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks_blueprints.eks_cluster_id
}

data "kubernetes_ingress_v1" "ingress" {
  metadata {
    name      = "ray-cluster-ingress"
    namespace = local.namespace
  }
  depends_on = [
    kubectl_manifest.cluster_provisioner
  ]
}

data "aws_iam_policy_document" "irsa_policy" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = ["${module.s3_bucket.s3_bucket_arn}"]
  }
  statement {
    actions   = ["s3:*Object"]
    resources = ["${module.s3_bucket.s3_bucket_arn}/*"]
  }
  statement {
    actions = [
      "ssm:PutParameter",
      "ssm:DeleteParameter",
      "ssm:GetParameterHistory",
      "ssm:GetParametersByPath",
      "ssm:GetParameters",
      "ssm:GetParameter",
      "ssm:DeleteParameters",
      "ssm:DescribeParameters"
    ]
    resources = ["arn:aws:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/ray-*"]
  }

  statement {
    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt"
    ]
    resources = [aws_kms_key.objects.arn]
  }
}
