# #---------------------------------------------------------------
# # Supporting Network Resources
# #---------------------------------------------------------------
# module "vpc" {
#   source  = "terraform-aws-modules/vpc/aws"
#   version = "~> 3.0"

#   name           = local.name
#   cidr           = local.vpc_cidr
#   azs            = local.azs
#   public_subnets = var.public_subnets

#   #  Use This to leverage Secondary CIDR block
#   #  secondary_cidr_blocks = "100.64.0.0/16"
#   #  private_subnets = concat(var.private_subnets, [var.secondary_cidr_blocks])
#   private_subnets = var.private_subnets

#   enable_nat_gateway   = true
#   single_nat_gateway   = true
#   enable_dns_hostnames = true

#   # Manage so we can name
#   manage_default_network_acl    = true
#   default_network_acl_tags      = { Name = "${local.name}-default" }
#   manage_default_route_table    = true
#   default_route_table_tags      = { Name = "${local.name}-default" }
#   manage_default_security_group = true
#   default_security_group_tags   = { Name = "${local.name}-default" }

#   public_subnet_tags = {
#     "kubernetes.io/role/elb" = 1
#   }

#   private_subnet_tags = {
#     "kubernetes.io/role/internal-elb" = 1
#     # Tags subnets for Karpenter auto-discovery
#     "karpenter.sh/discovery" = local.name
#   }

#   tags = local.tags
# }
