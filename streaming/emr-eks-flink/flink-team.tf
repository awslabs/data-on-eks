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

#create a log group
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
