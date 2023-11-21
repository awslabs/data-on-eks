resource "random_string" "random" {
  length  = 4
  special = false
  upper   = false
}

#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.14"
  role_name             = format("%s-%s", local.name, "ebs-csi-driver")
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  tags = local.tags
}

#---------------------------------------------------------------
# Trino S3 Bucket
#---------------------------------------------------------------
module "trino_s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket = "trino-data-bucket-${random_string.random.result}"

  # For example only - please evaluate for your environment
  force_destroy = true

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}

#---------------------------------------------------------------
# Creates IAM policy for accessing s3 bucket
#---------------------------------------------------------------
resource "aws_iam_policy" "trino_s3_bucket_policy" {
  description = "IAM role policy for Trino to access the S3 Bucket"
  name        = "${local.name}-s3-irsa-policy"
  policy      = data.aws_iam_policy_document.trino_s3_access.json
}

#---------------------------------------------------------------
# Trino Exchange Manager S3 Bucket
#---------------------------------------------------------------
module "trino_exchange_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket = "trino-exchange-bucket-${random_string.random.result}"

  # For example only - please evaluate for your environment
  force_destroy = true

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}

#---------------------------------------------------------------
# Creates IAM policy for accessing exchange bucket
#---------------------------------------------------------------
resource "aws_iam_policy" "trino_exchange_bucket_policy" {
  description = "IAM role policy for Trino to access the S3 Bucket"
  name        = "${local.name}-exchange-bucket-policy"
  policy      = data.aws_iam_policy_document.trino_exchange_access.json
}