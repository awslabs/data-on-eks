################################################################################
# VPC
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = ">= 4.0.0"

  name            = local.name
  cidr            = local.vpc_cidr
  azs             = local.azs
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    #Tags for External ELB
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    # Tags for Internal ELB
    "kubernetes.io/role/internal-elb" = 1
    # Tags subnets for Karpenter auto-discovery
    "karpenter.sh/discovery" = local.name
  }

  tags = local.tags
}
