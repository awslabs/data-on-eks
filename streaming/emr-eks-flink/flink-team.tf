resource "kubernetes_namespace_v1" "flink_team_a" {
  metadata {
    name = "${local.flink_team}-ns"
  }
  timeouts {
    delete = "15m"
  }
}

#---------------------------------------------------------------
# Creates IAM policy for IRSA. Provides IAM permissions for flink pods
#---------------------------------------------------------------
resource "aws_iam_policy" "flink" {
  description = "IAM role policy for flink Job execution"
  name        = "${local.name}-flink-irsa"
  policy      = data.aws_iam_policy_document.flink_sample_job.json
}

#---------------------------------------------------------------
# IRSA for flink pods for "flink-team-a"
#---------------------------------------------------------------
module "flink_irsa_jobs" {
  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.0"

  # Disable helm release
  create_release = false
  # IAM role for service account (IRSA)
  create_role   = true
  role_name     = "${local.name}-${local.flink_team}"
  create_policy = false
  role_policies = {
    flink_team_a_policy = aws_iam_policy.flink.arn
  }
  assume_role_condition_test = "StringLike"
  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = "${local.flink_team}-ns"
      service_account = "emr-containers-sa-*-*-${data.aws_caller_identity.current.account_id}-*"
    }
  }
}

#---------------------------------------------------------------
# IRSA for flink pods for "flink-operator"
#---------------------------------------------------------------
module "flink_irsa_operator" {
  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.0"

  # Disable helm release
  create_release = false
  # IAM role for service account (IRSA)
  create_role   = true
  role_name     = "${local.name}-operator"
  create_policy = false
  role_policies = {
    flink_team_a_policy = aws_iam_policy.flink.arn
  }
  assume_role_condition_test = "StringLike"
  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = "${local.flink_operator}-ns"
      service_account = "emr-containers-sa-flink-operator"
    }
  }
}

#---------------------------------------------------------------
# Creates a log group
#---------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flink_team_a" {
  name              = "/aws/emr-flink/flink-team-a"
  retention_in_days = 7
}

#---------------------------------------------------------------
# Example IAM policy for Flink job execution
#---------------------------------------------------------------
data "aws_iam_policy_document" "flink_sample_job" {
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:GetBucketLocation",
      "s3:GetObjectVersion"
    ]
  }
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
  }
}

#---------------------------------------------------------------
# S3 bucket for Flink related data,logs and checkpoint
#---------------------------------------------------------------
module "s3_bucket" {
  source                           = "terraform-aws-modules/s3-bucket/aws"
  version                          = "~> 3.0"
  bucket_prefix                    = "${local.name}-"
  attach_require_latest_tls_policy = true
  block_public_acls                = true
  block_public_policy              = true
  ignore_public_acls               = true
  restrict_public_buckets          = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }
  tags = local.tags
}

resource "aws_s3_object" "checkpoints" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "checkpoints/"
  content_type = "application/x-directory"
}

resource "aws_s3_object" "savepoints" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "savepoints/"
  content_type = "application/x-directory"
}

resource "aws_s3_object" "jobmanager" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "jobmanager/"
  content_type = "application/x-directory"
}

resource "aws_s3_object" "logs" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "logs/"
  content_type = "application/x-directory"
}
