data "aws_availability_zones" "available" {
  # Local Zones and Wavelength Zones are also "available" when the account opted in.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = data.aws_availability_zones.available.names

  # EKS rejects control plane subnets in use1-az3, and many current instance types are not
  # offered there. Karpenter can still use the data subnets in these AZs.
  core_excluded_az_ids = ["use1-az3"]
  az_ids               = zipmap(data.aws_availability_zones.available.names, data.aws_availability_zones.available.zone_ids)

  # One /16 per AZ. IPv6 nodes use 1 IPv4 address each, so a /16 holds about 65,000 nodes.
  secondary_cidrs = [for k in range(length(local.azs)) : "100.${64 + k}.0.0/16"]

  # Private subnets in the VPC module, one per AZ in each group:
  #   [0 .. n-1]   primary CIDR: core (EKS control plane ENIs, core node group, spark-operator nodes)
  #   [n .. 2n-1]  secondary1 (local.secondary_cidrs): data workloads (Karpenter)
  private_subnet_cidrs = concat(
    [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)],
    local.secondary_cidrs
  )

  private_subnet_names = concat(
    [for k, v in local.azs : "${var.name}-private-${v}"],
    [for k, v in local.azs : "${var.name}-private-secondary1-${v}"]
  )

  # Primary CIDR private subnets for the EKS control plane and the core node group.
  core_subnet_ids = [
    for k, v in local.azs : module.vpc.private_subnets[k]
    if !contains(local.core_excluded_az_ids, local.az_ids[v])
  ]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = var.name
  cidr = var.vpc_cidr

  azs = local.azs

  secondary_cidr_blocks = local.secondary_cidrs

  # The module assigns AZs by index (azs[index % n]).
  private_subnets = local.private_subnet_cidrs
  # Above the private /20 subnets, which have room for 15 AZs.
  public_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 240)]

  private_subnet_names = local.private_subnet_names
  public_subnet_names  = [for k, v in local.azs : "${var.name}-public-${v}"]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_ipv6            = true
  create_egress_only_igw = true

  # IPv6 /64 numbers: public subnets 0 to n-1, private subnets n to 3n-1.
  public_subnet_ipv6_prefixes  = [for k, v in local.azs : k]
  private_subnet_ipv6_prefixes = [for i in range(length(local.private_subnet_cidrs)) : i + length(local.azs)]

  public_subnet_assign_ipv6_address_on_creation = true
  # IPv6 clusters register nodes by IPv6 address. Off for IPv4 saves 1 NAU per node.
  private_subnet_assign_ipv6_address_on_creation = var.enable_ipv6

  public_subnet_tags = merge(var.public_subnet_tags, {
    "kubernetes.io/role/elb" = 1
  })

  private_subnet_tags = merge(var.private_subnet_tags, {
    "kubernetes.io/role/internal-elb" = 1
    # The EC2NodeClass selects subnets by the Name tag, not by this tag.
    "karpenter.sh/discovery" = var.name
  })

}

# Free, and no per-endpoint bandwidth limit, unlike an S3 interface endpoint.
resource "aws_vpc_endpoint" "s3_gateway" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  tags = {
    Name = "${var.name}-s3-gateway"
  }
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "6.7.3"

  vpc_id = module.vpc.vpc_id

  endpoints = {
    s3express = {
      service      = "s3express"
      service_type = "Gateway"
      route_table_ids = concat(
        module.vpc.private_route_table_ids
      )
    }
  }

  tags = {
    Name = "${var.name}-vpc-endpoints"
  }
}
