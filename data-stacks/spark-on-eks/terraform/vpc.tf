data "aws_availability_zones" "available" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  # Private subnets in the VPC module (core layout, one per AZ):
  #   [0 .. 2]  primary CIDR: core (EKS control plane ENIs, core node group, spark-operator node)
  #   [3 .. 5]  secondary1 (var.secondary_cidrs): data workloads (Karpenter)
  private_subnet_cidrs = concat(
    [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)],
    [for k in range(length(local.azs)) : var.secondary_cidrs[k]]
  )

  private_subnet_names = concat(
    [for k, v in local.azs : "${var.name}-private-${v}"],
    [for k, v in local.azs : "${var.name}-private-secondary1-${v}"]
  )

  # Extra secondary CIDRs for data node subnets: secondary2 to secondary8 (7 per AZ).
  # With secondary1, each AZ has 8 /16 data subnets.
  # Sizing: 10,000 nodes in one AZ. Each node uses 2 /28 prefixes + 1 node IP.
  additional_node_cidrs = [for i in range(21) : "100.${67 + i}.0.0/16"]

  # These subnets are created outside the VPC module (see "Data subnets" below), so each
  # subnet depends on its own CIDR association. Map key = subnet Name tag.
  data_subnets = {
    for i, cidr in local.additional_node_cidrs :
    "${var.name}-private-secondary${floor(i / length(local.azs)) + 2}-${local.azs[i % length(local.azs)]}" => {
      cidr = cidr
      az   = local.azs[i % length(local.azs)]
      # IPv6 /64 prefix numbers: public 0-2, module private 3-8, data subnets 9 and up.
      # Same numbers as before the move out of the module, so the IPv6 CIDRs do not change.
      ipv6_prefix = length(local.azs) + length(local.private_subnet_cidrs) + i
    }
  }
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

  # Secondary CIDR (secondary1) - Private subnets for data workloads.
  # The other data CIDRs and subnets are outside the module (see "Data subnets" below).
  secondary_cidr_blocks = var.secondary_cidrs

  # Private subnets: see local.private_subnet_cidrs for the order.
  # The module assigns AZs by index (azs[index % 3]).
  private_subnets = local.private_subnet_cidrs
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  private_subnet_names = local.private_subnet_names
  public_subnet_names  = [for k, v in local.azs : "${var.name}-public-${v}"]

  enable_nat_gateway = true
  single_nat_gateway = true

  # IPv6 Settings
  enable_ipv6            = true
  create_egress_only_igw = true

  public_subnet_ipv6_prefixes = [for k, v in local.azs : k]
  # Public subnets use prefixes 0-2. Module private subnets use 3-8, in the same order as
  # local.private_subnet_cidrs. Data subnets use 9 and up (local.data_subnets).
  private_subnet_ipv6_prefixes = [for i in range(length(local.private_subnet_cidrs)) : i + length(local.azs)]

  public_subnet_assign_ipv6_address_on_creation = true
  # The cluster is IPv4 (var.enable_ipv6 = false), so nodes do not need IPv6 addresses.
  # Each IPv6 address uses 1 NAU, so this saves 1 NAU per node.
  # Set this to true if you change the cluster to IPv6 (var.enable_ipv6 = true).
  private_subnet_assign_ipv6_address_on_creation = false

  public_subnet_tags = merge(var.public_subnet_tags, {
    "kubernetes.io/role/elb" = 1
  })

  private_subnet_tags = merge(var.private_subnet_tags, {
    "kubernetes.io/role/internal-elb" = 1
    # Karpenter discovery tag will be added by the blueprint
    "karpenter.sh/discovery" = var.name
  })

}

#---------------------------------------------------------------
# Data subnets (secondary2 to secondary8)
#---------------------------------------------------------------
resource "aws_vpc_ipv4_cidr_block_association" "data" {
  for_each = local.data_subnets

  vpc_id     = module.vpc.vpc_id
  cidr_block = each.value.cidr
}

resource "aws_subnet" "data" {
  for_each = local.data_subnets

  # Dependency on this subnet's own CIDR association.
  vpc_id            = aws_vpc_ipv4_cidr_block_association.data[each.key].vpc_id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  ipv6_cidr_block = cidrsubnet(module.vpc.vpc_ipv6_cidr_block, 8, each.value.ipv6_prefix)
  ipv6_native     = false
  # The cluster is IPv4: nodes do not get IPv6 addresses (saves 1 NAU per node).
  assign_ipv6_address_on_creation                = false
  enable_dns64                                   = true
  enable_resource_name_dns_aaaa_record_on_launch = true
  enable_resource_name_dns_a_record_on_launch    = false

  tags = merge(
    { Name = each.key },
    var.private_subnet_tags,
    {
      "kubernetes.io/role/internal-elb" = 1
      # Karpenter EC2NodeClasses select data subnets with Name "<name>-private-secondary*".
      "karpenter.sh/discovery" = var.name
    }
  )
}

resource "aws_route_table_association" "data" {
  for_each = aws_subnet.data

  subnet_id = each.value.id
  # single_nat_gateway = true: the module has one private route table.
  route_table_id = module.vpc.private_route_table_ids[0]
}

#---------------------------------------------------------------
# VPC Endpoints
#---------------------------------------------------------------
resource "aws_security_group" "vpc_endpoint_s3" {
  name_prefix = "${var.name}-vpc-endpoint-s3"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = concat([module.vpc.vpc_cidr_block], var.secondary_cidrs, local.additional_node_cidrs)
  }

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    ipv6_cidr_blocks = [module.vpc.vpc_ipv6_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.name}-vpc-endpoint-s3"
  }
}

module "vpc_endpoints" {
  source = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"

  vpc_id = module.vpc.vpc_id

  endpoints = {
    s3 = {
      service            = "s3"
      subnet_ids         = slice(module.vpc.private_subnets, 0, length(local.azs))
      security_group_ids = [aws_security_group.vpc_endpoint_s3.id]
      route_table_ids = concat(
        module.vpc.private_route_table_ids,
        module.vpc.public_route_table_ids
      )
      ip_address_type = "dualstack"
      dns_options = {
        dns_record_ip_type = var.enable_ipv6 ? "dualstack" : "ipv4"
      }
      private_dns_enabled = true
    }
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
