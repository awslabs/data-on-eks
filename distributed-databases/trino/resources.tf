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

module "trino_s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket = "${random_string.random.result}-trino-bucket"

  # For example only - please evaluate for your environment
  force_destroy = true

  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

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
# IRSA for S3 Bucket
#---------------------------------------------------------------
module "trino_s3_irsa" {
  source                            = "github.com/aws-ia/terraform-aws-eks-blueprints-addons?ref=ed27abc//modules/irsa"
  eks_cluster_id                    = module.eks.cluster_name
  eks_oidc_provider_arn             = module.eks.oidc_provider_arn
  irsa_iam_policies                 = [
                                        aws_iam_policy.trino_s3_bucket_policy.arn, 
                                        data.aws_iam_policy.glue_full_access.arn,
                                        aws_iam_policy.trino_glue_s3_bucket_policy.arn
                                      ]
  kubernetes_namespace              = local.trino_namespace
  kubernetes_service_account        = local.trino_sa
  create_kubernetes_service_account = false
  create_kubernetes_namespace       = false
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
# Creates IAM policy for Trino to access the S3 bucket with Glue
#---------------------------------------------------------------
resource "aws_iam_policy" "trino_glue_s3_bucket_policy" {
  description = "IAM role policy for Trino to use Glue to access the S3 Bucket"
  name        = "${local.name}-s3-glue-irsa-policy"
  policy      = data.aws_iam_policy_document.trino_glue_s3_access.json
}