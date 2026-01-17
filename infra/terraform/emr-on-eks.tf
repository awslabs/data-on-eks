#---------------------------------------------------------------
# EMR on EKS Virtual Clusters
# Creates EMR virtual clusters for running Spark jobs on EKS
# Module handles: namespace, IAM role, CloudWatch log group, RBAC
#---------------------------------------------------------------

locals {
  emr_teams = var.enable_emr_on_eks ? {
    emr-data-team-a = {
      name      = "emr-data-team-a"
      namespace = "emr-data-team-a"
    }
    emr-data-team-b = {
      name      = "emr-data-team-b"
      namespace = "emr-data-team-b"
    }
  } : {}
}

#---------------------------------------------------------------
# EMR Virtual Cluster Module
# The module creates: namespace, IAM role, CloudWatch log group,
# Kubernetes role and role binding
#---------------------------------------------------------------
module "emr_containers" {
  source  = "terraform-aws-modules/emr/aws//modules/virtual-cluster"
  version = "~> 3.2"

  for_each = local.emr_teams

  name             = "${local.name}-${each.key}"
  eks_cluster_name = module.eks.cluster_name

  # Namespace configuration - module creates the namespace
  create_namespace = true
  namespace        = each.value.namespace

  # IAM role configuration
  create_iam_role          = true
  eks_oidc_provider_arn    = module.eks.oidc_provider_arn
  role_name                = "${local.name}-${each.key}"
  iam_role_use_name_prefix = false
  iam_role_description     = "EMR Execution Role for ${each.key}"

  # S3 bucket access for job artifacts and logs
  s3_bucket_arns = [
    module.s3_bucket.s3_bucket_arn,
    "${module.s3_bucket.s3_bucket_arn}/*",
  ]

  # Additional IAM policies for EMR jobs
  iam_role_additional_policies = {
    AmazonS3FullAccess = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  }

  # CloudWatch logging configuration
  create_cloudwatch_log_group            = true
  cloudwatch_log_group_name              = "/emr-on-eks-logs/${local.name}/${each.key}"
  cloudwatch_log_group_retention_in_days = 7

  tags = merge(local.tags, {
    Name = each.key
    Team = each.key
  })

  depends_on = [module.eks]
}
