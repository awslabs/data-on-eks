provider "aws" {
  region = local.region
}

# ECR always authenticates with `us-east-1` region
# Docs -> https://docs.aws.amazon.com/AmazonECR/latest/public/public-registries.html
provider "aws" {
  alias  = "ecr"
  region = "us-east-1"
}

# Removed exec plugin as this doesn't work with Terraform Cloud and TOFU controller plugin with backstage
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubectl" {
  apply_retry_count      = 10
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  token                  = data.aws_eks_cluster_auth.this.token
}

locals {
  name   = var.name
  region = var.region
  azs    = slice(data.aws_availability_zones.available.names, 0, 2)

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # Ray Data configuration
  s3_prefix        = "${local.name}/spark-application-logs/spark-team-a"
  iceberg_database = "raydata_spark_logs"

  s3_express_supported_az_ids = [
    "use1-az4", "use1-az5", "use1-az6", "usw2-az1", "usw2-az3", "usw2-az4", "apne1-az1", "apne1-az4", "eun1-az1", "eun1-az2", "eun1-az3"
  ]

  s3_express_az_ids = [
    for az_id in data.aws_availability_zones.available.zone_ids :
    az_id if contains(local.s3_express_supported_az_ids, az_id)
  ]

  s3_express_azs = [for zone_id in local.s3_express_az_ids : [
    for az in data.aws_availability_zones.available.zone_ids :
    data.aws_availability_zones.available.names[index(data.aws_availability_zones.available.zone_ids, az)] if az == zone_id
  ][0]]

  s3_express_zone_id   = local.s3_express_az_ids[0]
  s3_express_zone_name = local.s3_express_azs[0]

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

data "aws_availability_zones" "available" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
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
