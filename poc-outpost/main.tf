# data "aws_eks_cluster_auth" "this" {
#   name = local.name
# }
# Read AZ for current region
data "aws_availability_zones" "available" {}
# Read Outpost informations
data "aws_outposts_outpost" "default" {
  name = var.outpost_name
}
# data "aws_caller_identity" "current" {}
# data "aws_partition" "current" {}

# data "aws_ecrpublic_authorization_token" "token" {
#   provider = aws.virginia
# }

locals {
  name   = var.name
  region = var.region

  cluster_version = var.eks_cluster_version

  # Calcul des azs
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
  outpost_az = data.aws_outposts_outpost.default.availability_zone
  non_outpost_azs = [for az in local.azs : az if az != local.outpost_az]

  # Calcul des CIDR associés
  // CIDR 10.0.0.0/24
  private_subnets_cidr = [cidrsubnet(var.vpc_cidr, 8, 0)]
  // CIDR 10.0.254.0/24
  factice_private_subnets_cidr = [cidrsubnet(var.vpc_cidr, 8, 254)]
  # Public subnets: seulement pour les non-Outpost AZs (10.0.1.0/24, 10.0.2.0/24)
  public_subnets_cidr = [for k, az in local.non_outpost_azs : cidrsubnet(var.vpc_cidr, 8, k + 1)]

  # account_id = data.aws_caller_identity.current.account_id
  # partition  = data.aws_partition.current.partition

  tags = {
    Blueprint  = local.name
    Terraform = "True"
  }
}