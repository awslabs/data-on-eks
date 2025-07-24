data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_eks_cluster_auth" "this" {
  name = local.name
}
data "aws_region" "current" {}
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}


locals {
  name   = var.name
  region = var.region
  cluster_version = var.cluster_version
  cluster_endpoint = var.cluster_endpoint
  oidc_provider_arn = var.oidc_provider_arn
  karpenter_node_iam_role_name = var.karpenter_node_iam_role_name

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  tags = var.tags
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

#---------------------------------------------------------------------
# Example IAM policy for s3 Tables access from Spark Jobs.
# Please modify this policy according to your security requirements.
#---------------------------------------------------------------------
data "aws_iam_policy_document" "s3tables_policy" {
  version = "2012-10-17"

  statement {
    sid    = "VisualEditor0"
    effect = "Allow"

    actions = [
      "s3tables:CreateTableBucket",
      "s3tables:ListTables",
      "s3tables:CreateTable",
      "s3tables:GetNamespace",
      "s3tables:DeleteTableBucket",
      "s3tables:CreateNamespace",
      "s3tables:ListNamespaces",
      "s3tables:ListTableBuckets",
      "s3tables:GetTableBucket",
      "s3tables:DeleteNamespace",
      "s3tables:GetTableBucketMaintenanceConfiguration",
      "s3tables:PutTableBucketMaintenanceConfiguration",
      "s3tables:GetTableBucketPolicy"
    ]

    resources = ["arn:aws:s3tables:*:${data.aws_caller_identity.current.account_id}:bucket/*"]
  }

  statement {
    sid    = "VisualEditor1"
    effect = "Allow"

    actions = [
      "s3tables:GetTableMaintenanceJobStatus",
      "s3tables:GetTablePolicy",
      "s3tables:GetTable",
      "s3tables:GetTableMetadataLocation",
      "s3tables:UpdateTableMetadataLocation",
      "s3tables:DeleteTable",
      "s3tables:PutTableData",
      "s3tables:RenameTable",
      "s3tables:PutTableMaintenanceConfiguration",
      "s3tables:GetTableData",
      "s3tables:GetTableMaintenanceConfiguration"
    ]

    resources = ["arn:aws:s3tables:*:${data.aws_caller_identity.current.account_id}:bucket/*/table/*"]
  }

  statement {
    sid    = "VisualEditor2"
    effect = "Allow"

    actions = ["s3tables:ListTableBuckets"]

    resources = ["*"]
  }
}
