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
  name   = var.name
  region = var.region
  oidc_provider_arn    = var.oidc_provider_arn
  cluster_version = var.cluster_version
  cluster_endpoint = var.cluster_endpoint
  kubernetes_storage_class_default_id = var.kubernetes_storage_class_default_id

  grafana_manager_name        = "aws-observability-accelerator"
  grafana_manager_description = "Amazon Managed Grafana workspace for ${local.name}"


  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = var.tags
}

