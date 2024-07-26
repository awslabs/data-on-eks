data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

data "aws_availability_zones" "available" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

#---------------------------------------------------------------
# IAM policy for Spark job execution
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

data "template_file" "s3_express_pv" {
  template = file("${path.module}/resources/s3_express_pv.tpl")

  vars = {
    region                 = var.region
    s3_express_bucket_name = aws_s3_directory_bucket.spark_data_bucket_express.id
    s3express_bucket_zone  = local.s3_express_zone_name
  }
}

data "aws_iam_policy_document" "kms_policy" {
  # checkov:skip=CKV_AWS_109: This key policy is required for the management of the key.
  # checkov:skip=CKV_AWS_111: This key policy is required for the management of the key.
  # checkov:skip=CKV_AWS_356: This key policy is required for the management of the key.
  statement {
    sid       = "AllowRootKeyManagement"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"] //creates cyclic dependency if we specify the KMS arn
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}