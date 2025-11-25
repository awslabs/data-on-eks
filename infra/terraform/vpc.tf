data "aws_availability_zones" "available" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

#---------------------------------------------------------------
# VPC
#---------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.name
  cidr = var.vpc_cidr

  azs = local.azs

  # Secondary CIDR - Private subnets for EKS pods and nodes
  secondary_cidr_blocks = var.secondary_cidrs

  # Primary CIDR - Private and public subnets + Secondary CIDR subnets
  private_subnets = concat(
    [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)],
    [for k, v in local.azs : cidrsubnet(var.secondary_cidrs[0], 2, k)]
  )
  public_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  private_subnet_names = concat(
    [for k, v in local.azs : "${var.name}-private-${v}"],
    [for k, v in local.azs : "${var.name}-private-secondary-${v}"]
  )
  public_subnet_names = [for k, v in local.azs : "${var.name}-public-${v}"]

  enable_nat_gateway = true
  single_nat_gateway = true

  # IPv6 Settings
  enable_ipv6            = true
  create_egress_only_igw = true

  public_subnet_ipv6_prefixes  = [for k, v in local.azs : k]
  private_subnet_ipv6_prefixes = [for i in range(length(local.azs) * 2) : i + length(local.azs)] # Start after public prefixes

  public_subnet_assign_ipv6_address_on_creation  = true
  private_subnet_assign_ipv6_address_on_creation = true

  public_subnet_tags = merge(var.public_subnet_tags, {
    "kubernetes.io/role/elb" = 1
  })

  private_subnet_tags = merge(var.private_subnet_tags, {
    "kubernetes.io/role/internal-elb" = 1
    # Karpenter discovery tag will be added by the blueprint
    "karpenter.sh/discovery" = var.name
  })

}
