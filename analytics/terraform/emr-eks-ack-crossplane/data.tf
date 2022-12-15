data "aws_eks_cluster_auth" "this" {
  name = module.eks_blueprints.eks_cluster_id
}

data "aws_availability_zones" "available" {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# Equivalent of aws ecr get-login
data "aws_ecr_authorization_token" "ecr_token" {}
# Multiple docker push commands can be run against a single token
resource "null_resource" "renew_ecr_token" {
  triggers = {
    token_expired = data.aws_ecr_authorization_token.ecr_token.expires_at
  }

  provisioner "local-exec" {
    command = "echo ${data.aws_ecr_authorization_token.ecr_token.password} | docker login --username ${data.aws_ecr_authorization_token.ecr_token.user_name} --password-stdin ${data.aws_ecr_authorization_token.ecr_token.proxy_endpoint}"
  }
}


data "aws_iam_policy_document" "emr_on_eks" {
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::*"]

    actions = [
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
    ]
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:*"]

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
  }
}
