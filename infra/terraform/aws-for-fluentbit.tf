locals {
  aws_for_fluentbit_service_account = "aws-for-fluent-bit-sa"
  aws_for_fluentbit_namespace       = "kube-system"

  aws_for_fluentbit_values = templatefile("${path.module}/helm-values/aws-for-fluentbit.yaml", {
    cluster_name         = module.eks.cluster_name
    cloudwatch_log_group = aws_cloudwatch_log_group.aws_for_fluentbit.name
    s3_bucket_name       = module.s3_bucket.s3_bucket_id
    region               = local.region
    enable_ipv6          = var.enable_ipv6
    fluent_bit_irsa_arn  = module.aws_for_fluentbit_irsa.arn
  })
}

#---------------------------------------------------------------
# CloudWatch Log Group
#---------------------------------------------------------------
resource "aws_cloudwatch_log_group" "aws_for_fluentbit" {
  name              = "/aws/eks/${module.eks.cluster_name}/aws-fluentbit-logs"
  retention_in_days = 30
  tags              = var.tags
}

#---------------------------------------------------------------
# IRSA for AWS for Fluent Bit
#---------------------------------------------------------------
# We need to us IRSA for this because of problems with IPv6 and Pod Identity in Fluent bit. This needs to be resolved: https://github.com/aws/aws-for-fluent-bit/issues/983
module "aws_for_fluentbit_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"
  name    = "${module.eks.cluster_name}-fluent-bit"

  policies = {
    fluent_bit_policy = aws_iam_policy.aws_for_fluentbit.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${local.aws_for_fluentbit_namespace}:${local.aws_for_fluentbit_service_account}"]
    }
  }
}

data "aws_s3_bucket" "logs" {
  bucket = module.s3_bucket.s3_bucket_id
}

#---------------------------------------------------------------
# IAM Policy for CloudWatch Logs and S3
#---------------------------------------------------------------
resource "aws_iam_policy" "aws_for_fluentbit" {
  name        = "${local.name}-fluent-bit-policy"
  description = "IAM Policy for AWS Fluentbit"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PutLogEvents"
        Effect = "Allow"
        Resource = [
          "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${aws_cloudwatch_log_group.aws_for_fluentbit.name}:log-stream:*"
        ]
        Action = [
          "logs:PutLogEvents"
        ]
      },
      {
        Sid    = "CreateCWLogs"
        Effect = "Allow"
        Resource = [
          "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${aws_cloudwatch_log_group.aws_for_fluentbit.name}:*"
        ]
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutRetentionPolicy"
        ]
      },
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:GetObjectAcl",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion"
        ]
        Resource = [
          data.aws_s3_bucket.logs.arn,
          "${data.aws_s3_bucket.logs.arn}/*"
        ]
      }
    ]
  })
}

#---------------------------------------------------------------
# AWS for Fluent Bit ConfigMap
#---------------------------------------------------------------
resource "kubectl_manifest" "aws_for_fluentbit_configmap" {
  yaml_body = templatefile("${path.module}/manifests/aws-for-fluentbit/cm.yaml", {
    # Add template variables as needed
  })
}

#---------------------------------------------------------------
# AWS for Fluent Bit Application
#---------------------------------------------------------------
resource "kubectl_manifest" "aws_for_fluentbit" {
  yaml_body = templatefile("${path.module}/argocd-applications/aws-for-fluentbit.yaml", {
    user_values_yaml = indent(8, local.aws_for_fluentbit_values)
  })

  depends_on = [
    helm_release.argocd,
    module.aws_for_fluentbit_irsa,
    aws_iam_policy.aws_for_fluentbit,
    aws_cloudwatch_log_group.aws_for_fluentbit
  ]
}
