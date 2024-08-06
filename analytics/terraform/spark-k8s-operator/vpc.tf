#---------------------------------------------------------------
# Supporting Network Resources
#---------------------------------------------------------------
# WARNING: This VPC module includes the creation of an Internet Gateway and NAT Gateway, which simplifies cluster deployment and testing, primarily intended for sandbox accounts.
# IMPORTANT: For preprod and prod use cases, it is crucial to consult with your security team and AWS architects to design a private infrastructure solution that aligns with your security requirements

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = var.vpc_cidr
  azs  = local.azs

  # Enable IPv6, unused unless the EKS cluster is also IPv6
  enable_ipv6            = var.enable_ipv6
  create_egress_only_igw = var.enable_ipv6

  # Secondary CIDR block attached to VPC for EKS Control Plane ENI + Nodes + Pods
  secondary_cidr_blocks = var.secondary_cidr_blocks

  # ------------------------------
  # Optional Public Subnets for NAT and IGW for PoC/Dev/Test environments
  # Public Subnets can be disabled while deploying to Production and use Private NAT + TGW
  public_subnets     = var.public_subnets
  enable_nat_gateway = true
  # single_nat_gateway = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true
  # if IPv6 is enabled, assign two prefixes and enable ipv6 addresses
  public_subnet_ipv6_prefixes                   = var.enable_ipv6 ? [0, 1] : []
  public_subnet_assign_ipv6_address_on_creation = var.enable_ipv6
  public_subnet_enable_dns64                    = false
  #-------------------------------

  # ------------------------------
  # Private subnets across two AZs for EKS Control Plane ENI, TGW attachments and Private ELBs
  private_subnets = var.private_subnets
  # if IPv6 is enabled, assign two prefixes and enable ipv6 addresses
  private_subnet_ipv6_prefixes                   = var.enable_ipv6 ? [3, 4] : []
  private_subnet_assign_ipv6_address_on_creation = var.enable_ipv6
  private_subnet_enable_dns64                    = false
  #-------------------------------

  # ------------------------------
  # Private subnets across two AZs for EKS worker nodes and pods
  database_subnets             = var.eks_data_plane_subnet_secondary_cidr
  create_database_subnet_group = false
  database_subnet_suffix       = "eks"
  # if IPv6 is enabled, assign two prefixes and enable ipv6 addresses
  database_subnet_ipv6_prefixes                   = var.enable_ipv6 ? [5, 6] : []
  database_subnet_assign_ipv6_address_on_creation = var.enable_ipv6
  database_subnet_enable_dns64                    = false
  #-------------------------------

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  database_subnet_tags = {
    # Tags subnets for Karpenter auto-discovery
    "karpenter.sh/discovery" = local.name
  }
  tags = local.tags

}

# CIDR Reservations for Prefix Delegation to avoid IP space fragmentation
# Subnetting /64 into /80s gives 65536 subnets
# we want to use the majority of the /64 for EKS prefix delegation so we will create three reservations per subnet:
#    <vpc IPv6>/65, <vpc IPv6>/66, <vpc IPv6>/67
#
# leaving a single /67 subnet (~8k /80 subnets) for single IP assignments
# TODO: this can probably be a loop in some way

resource "aws_ec2_subnet_cidr_reservation" "eks_cidr_reservation_0_65" {
  count            = var.enable_ipv6 ? 1 : 0
  cidr_block       = cidrsubnet(module.vpc.database_subnets_ipv6_cidr_blocks[0], 1, 0)
  reservation_type = "prefix"
  subnet_id        = module.vpc.database_subnets[0]
}

resource "aws_ec2_subnet_cidr_reservation" "eks_cidr_reservation_0_66" {
  count            = var.enable_ipv6 ? 1 : 0
  cidr_block       = cidrsubnet(module.vpc.database_subnets_ipv6_cidr_blocks[0], 2, 2)
  reservation_type = "prefix"
  subnet_id        = module.vpc.database_subnets[0]
}

resource "aws_ec2_subnet_cidr_reservation" "eks_cidr_reservation_0_67" {
  count            = var.enable_ipv6 ? 1 : 0
  cidr_block       = cidrsubnet(module.vpc.database_subnets_ipv6_cidr_blocks[0], 3, 6)
  reservation_type = "prefix"
  subnet_id        = module.vpc.database_subnets[0]
}

resource "aws_ec2_subnet_cidr_reservation" "eks_cidr_reservation_1_65" {
  count            = var.enable_ipv6 ? 1 : 0
  cidr_block       = cidrsubnet(module.vpc.database_subnets_ipv6_cidr_blocks[1], 1, 0)
  reservation_type = "prefix"
  subnet_id        = module.vpc.database_subnets[1]
}

resource "aws_ec2_subnet_cidr_reservation" "eks_cidr_reservation_1_66" {
  count            = var.enable_ipv6 ? 1 : 0
  cidr_block       = cidrsubnet(module.vpc.database_subnets_ipv6_cidr_blocks[1], 2, 2)
  reservation_type = "prefix"
  subnet_id        = module.vpc.database_subnets[1]
}

resource "aws_ec2_subnet_cidr_reservation" "eks_cidr_reservation_1_67" {
  count            = var.enable_ipv6 ? 1 : 0
  cidr_block       = cidrsubnet(module.vpc.database_subnets_ipv6_cidr_blocks[1], 3, 6)
  reservation_type = "prefix"
  subnet_id        = module.vpc.database_subnets[1]
}

module "vpc_endpoints_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  create = var.enable_vpc_endpoints

  name        = "${local.name}-vpc-endpoints"
  description = "Security group for VPC endpoint access"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      rule        = "https-443-tcp"
      description = "VPC CIDR HTTPS"
      cidr_blocks = join(",", [module.vpc.vpc_cidr_block], module.vpc.vpc_secondary_cidr_blocks)
    }
  ]
  egress_with_cidr_blocks = [
    {
      rule        = "https-443-tcp"
      description = "All egress HTTPS"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
  # IPv6 rules
  ingress_with_ipv6_cidr_blocks = var.enable_ipv6 ? [
    {
      rule             = "https-443-tcp"
      description      = "VPC IPv6 CIDR HTTPS"
      ipv6_cidr_blocks = module.vpc.vpc_ipv6_cidr_block
    }
  ] : []
  egress_with_ipv6_cidr_blocks = var.enable_ipv6 ? [
    {
      rule             = "https-443-tcp"
      description      = "All egress v4 HTTPS"
      ipv6_cidr_blocks = "::/0"
    }
  ] : []

  tags = local.tags
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 5.0"

  create = var.enable_vpc_endpoints

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [module.vpc_endpoints_sg.security_group_id]

  endpoints = merge({
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = concat(module.vpc.public_route_table_ids, module.vpc.private_route_table_ids, module.vpc.database_route_table_ids)
      tags = {
        Name = "${local.name}-s3"
      }
    }
    },
    { for service in toset(["autoscaling", "ecr.api", "ecr.dkr", "ec2", "ec2messages", "elasticloadbalancing", "sts", "kms", "logs", "ssm", "ssmmessages"]) :
      replace(service, ".", "_") =>
      {
        service             = service
        subnet_ids          = module.vpc.private_subnets
        private_dns_enabled = true
        tags                = { Name = "${local.name}-${service}" }
      }
  })

  tags = local.tags
}
