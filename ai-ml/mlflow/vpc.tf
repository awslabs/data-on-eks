module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr
  azs  = local.azs

  # Three private Subnets with RFC1918 private IPv4 address range for Private NAT + NLB
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  
  # ------------------------------
  # Optional Public Subnets for NAT and IGW for PoC/Dev/Test environments
  # Public Subnets can be disabled while deploying to Production and use Private NAT + TGW
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 10)]

  # ------------------------------
  # Private Subnets for MLflow backend store
  database_subnets                   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 20)]
  create_database_subnet_group       = true
  create_database_subnet_route_table = true
  
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}
