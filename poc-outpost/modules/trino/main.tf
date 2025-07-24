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



#---------------------------------------------------------------

locals {
  name   = var.cluster_name
  region = var.region
  oidc_provider_arn    = var.oidc_provider_arn
  vpc_id = var.vpc_id
  private_subnets_cidr = var.private_subnets_cidr
  db_subnet_group_name = var.db_subnets_group_name
  karpenter_node_iam_role_name = var.karpenter_node_iam_role_name
  default_node_group_type = var.default_node_group_type

  trino_namespace = "trino"
  trino_name = "trinoalb4"
  trino_sa        = "trino-sa-alb4"
  trino_tls = "${local.trino_name}-tls"

  cognito_user_pool_id = var.cognito_user_pool_id
  cognito_custom_domain = var.cognito_custom_domain
  cluster_issuer_name = var.cluster_issuer_name
  main_domain = var.main_domain
  zone_id = var.zone_id

  outpost_name = var.outpost_name
  output_subnet_id = var.output_subnet_id

  tags = var.tags
}

