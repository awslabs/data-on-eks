#---------------------------------------------------------------
# Data resources
#---------------------------------------------------------------

data "aws_availability_zones" "available" {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_eks_addon_version" "this" {
  addon_name         = "vpc-cni"
  kubernetes_version = var.eks_cluster_version
  most_recent        = true
}

# This data source can be used to get the latest AMI for Managed Node Groups
data "aws_ami" "x86" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["amazon-eks-node-${module.eks.cluster_version}-*"] # Update this for ARM ["amazon-eks-arm64-node-${module.eks.cluster_version}-*"]
  }
}

#---------------------------------------------------------------
# IAM policy for Fluent Bit
#---------------------------------------------------------------
data "aws_iam_policy_document" "fluent_bit" {
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${module.fluentbit_s3_bucket.s3_bucket_id}/*"]

    actions = [
      "s3:ListBucket",
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:GetObject",
      "s3:GetObjectAcl",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion"
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
      "logs:PutRetentionPolicy",
    ]
  }
}

#---------------------------------------------------------------
# Example IAM policy for Spark job execution
#---------------------------------------------------------------
data "aws_iam_policy_document" "spark_operator" {
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

#---------------------------------------------------------------
# Example IAM policy for Aiflow S3 logging
#---------------------------------------------------------------


data "aws_iam_policy_document" "airflow_s3_logs" {
  count = var.enable_airflow ? 1 : 0
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${module.airflow_s3_bucket[0].s3_bucket_id}"]

    actions = [
      "s3:ListBucket"
    ]
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${module.airflow_s3_bucket[0].s3_bucket_id}/*"]

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
  }
}
