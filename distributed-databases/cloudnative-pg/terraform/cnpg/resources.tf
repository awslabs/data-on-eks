module "barman_s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket = "cnpg-barman-backup-bucket"
  acl    = "private"

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
# IRSA for Airflow S3 logging
#---------------------------------------------------------------
module "barman_irsa" {
  source                     = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/irsa?ref=v4.23.0"
  eks_cluster_id             = module.eks_blueprints.eks_cluster_id
  eks_oidc_provider_arn      = module.eks_blueprints.eks_oidc_provider_arn
  irsa_iam_policies          = [aws_iam_policy.cnpg_buckup_policy.arn]
  kubernetes_namespace       = "demo"
  kubernetes_service_account = "cluster"
  create_kubernetes_service_account = false
  create_kubernetes_namespace = false
}

#---------------------------------------------------------------
# Creates IAM policy for accessing s3 bucket
#---------------------------------------------------------------
resource "aws_iam_policy" "cnpg_buckup_policy" {
  description = "IAM role policy for CloudNativePG Barman Tool"
  name        = "${local.name}-cnpg-barman-irsa"
  policy      = data.aws_iam_policy_document.cnpg_backup.json
}