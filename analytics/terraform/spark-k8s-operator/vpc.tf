#---------------------------------------------------------------
# Supporting Network Resources
#---------------------------------------------------------------
# WARNING: This VPC module includes the creation of an Internet Gateway and NAT Gateway, which simplifies cluster deployment and testing, primarily intended for sandbox accounts.
# IMPORTANT: For preprod and prod use cases, it is crucial to consult with your security team and AWS architects to design a private infrastructure solution that aligns with your security requirements
#
# ╔═══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                              VPC SUBNET ALLOCATION TABLE                                      ║
# ╠═══════════════════════════════════════════════════════════════════════════════════════════════╣
# ║ AZ Count │ Private Primary (/20)    │ Private Secondary CIDR (/18)  │ Public (/24)            ║
# ║          │ from 10.1.0.0/16         │ from 100.64.0.0/16            │ from 10.1.0.0/16        ║
# ╠═══════════════════════════════════════════════════════════════════════════════════════════════╣
# ║    2     │ 10.1.0.0/20   (4096 IPs) │ 100.64.0.0/18  (16384)        │ 10.1.128.0/24 (256)     ║
# ║          │ 10.1.16.0/20  (4096 IPs) │ 100.64.64.0/18 (16384)        │ 10.1.129.0/24 (256)     ║
# ╠═══════════════════════════════════════════════════════════════════════════════════════════════╣
# ║    3     │ 10.1.0.0/20   (4096 IPs) │ 100.64.0.0/18   (16384)       │ 10.1.128.0/24 (256)     ║
# ║          │ 10.1.16.0/20  (4096 IPs) │ 100.64.64.0/18  (16384)       │ 10.1.129.0/24 (256)     ║
# ║          │ 10.1.32.0/20  (4096 IPs) │ 100.64.128.0/18 (16384)       │ 10.1.130.0/24 (256)     ║
# ╠═══════════════════════════════════════════════════════════════════════════════════════════════╣
# ║    4     │ 10.1.0.0/20   (4096 IPs) │ 100.64.0.0/18   (16384)       │ 10.1.128.0/24 (256)     ║
# ║          │ 10.1.16.0/20  (4096 IPs) │ 100.64.64.0/18  (16384)       │ 10.1.129.0/24 (256)     ║
# ║          │ 10.1.32.0/20  (4096 IPs) │ 100.64.128.0/18 (16384)       │ 10.1.130.0/24 (256)     ║
# ║          │ 10.1.48.0/20  (4096 IPs) │ 100.64.192.0/18 (16384)       │ 10.1.131.0/24 (256)     ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝

locals {

  private_primary_subnets = [
    for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i)
  ]

  private_secondary_subnets = [
    for i, az in local.azs : cidrsubnet(var.secondary_cidr_blocks[0], 2, i)
  ]

  public_subnets = [
    for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, 128 + i)
  ]

  # Combine all private subnets
  all_private_subnets = concat(local.private_primary_subnets, local.private_secondary_subnets)

  # Generate subnet names
  private_subnet_names = concat(
    [for az in local.azs : "${var.name}-private-${az}"],          # Primary CIDR for EKS Control Plane ENI + Load Balancers etc
    [for az in local.azs : "${var.name}-private-secondary-${az}"] # Secondary CIDR for workload pods
  )

  public_subnet_names = [for az in local.azs : "${var.name}-public-${az}"]

}

#---------------------------------------------------------------
# VPC
#---------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.19"

  name = local.name
  cidr = var.vpc_cidr

  azs = local.azs

  # Secondary CIDR block attached to VPC for EKS Control Plane ENI + Nodes + Pods
  secondary_cidr_blocks = var.secondary_cidr_blocks

  # Subnet configuration
  private_subnets      = local.all_private_subnets
  private_subnet_names = local.private_subnet_names
  public_subnets       = local.public_subnets
  public_subnet_names  = local.public_subnet_names

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    # Tags subnets for Karpenter auto-discovery
    "karpenter.sh/discovery" = local.name
  }

  tags = local.tags
}

module "vpc_endpoints_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.3"

  create = var.enable_vpc_endpoints

  name        = "${local.name}-vpc-endpoints"
  description = "Security group for VPC endpoint access"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      rule        = "https-443-tcp"
      description = "VPC CIDR HTTPS"
      cidr_blocks = join(",", [module.vpc.vpc_cidr_block], module.vpc.vpc_secondary_cidr_blocks)
    },
  ]

  egress_with_cidr_blocks = [
    {
      rule        = "https-443-tcp"
      description = "All egress HTTPS"
      cidr_blocks = "0.0.0.0/0"
    },
  ]

  tags = local.tags
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 5.21"

  create = var.enable_vpc_endpoints

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [module.vpc_endpoints_sg.security_group_id]

  endpoints = merge({
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = concat(module.vpc.public_route_table_ids, module.vpc.private_route_table_ids)
      tags = {
        Name = "${local.name}-s3"
      }
    }
    },
    { for service in toset(["autoscaling", "ecr.api", "ecr.dkr", "ec2", "ec2messages", "eks", "eks-auth", "elasticloadbalancing", "sts", "kms", "logs", "ssm", "ssmmessages"]) :
      replace(service, ".", "_") =>
      {
        service = service
        # Filter for only the private subnets in the 10.x CIDR to avoid DuplicateSubnetsInSameZone exception
        subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
          substr(cidr_block, 0, 3) == "10." ? subnet_id : null]
        )
        private_dns_enabled = true
        tags                = { Name = "${local.name}-${service}" }
      }
  })

  tags = local.tags
}
