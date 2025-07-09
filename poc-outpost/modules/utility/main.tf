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


locals {
  name   = var.name
  region = var.region
  cluster_version = var.cluster_version
  cluster_endpoint = var.cluster_endpoint
  oidc_provider_arn = var.oidc_provider_arn

  tags = var.tags
}

