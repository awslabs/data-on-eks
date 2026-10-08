data "aws_availability_zones" "available" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  # Extra secondary CIDRs for data node subnets. With secondary1 (var.secondary_cidrs),
  # each AZ has 8 /16 data subnets: secondary1 to secondary8.
  # Sizing: 10,000 nodes in one AZ. Each node uses 2 /28 prefixes + 1 node IP. In the worst
  # case (node IPs fragment the /28 space) one /16 holds about 1,365 nodes, so 8 subnets
  # hold about 10,900 nodes per AZ.
  # 21 CIDRs: 100.67.0.0/16 to 100.87.0.0/16. AZs are assigned in order (AZ1, AZ2, AZ3, AZ1, ...).
  # Karpenter selects these subnets with the "<name>-private-secondary*" Name tag.
  # Only append to this list. Removing or reordering entries replaces subnets.
  # VPC quota "IPv4 CIDR blocks per VPC" must be >= 25 (1 primary + 3 + 21).
  additional_node_cidrs = [for i in range(21) : "100.${67 + i}.0.0/16"]

  # Private subnet list order. Only append, so existing subnet indexes do not change:
  #   [0 .. 2]  primary CIDR, one per AZ: core (EKS control plane ENIs, core node group)
  #   [3 .. 5]  secondary1 (var.secondary_cidrs), one per AZ: data workloads (Karpenter)
  #   [6 .. ]   secondary2 to secondary8 (local.additional_node_cidrs), AZ1, AZ2, AZ3, AZ1, ...: data workloads
  private_subnet_cidrs = concat(
    [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)],
    [for k in range(length(local.azs)) : var.secondary_cidrs[k]],
    local.additional_node_cidrs
  )

  private_subnet_names = concat(
    [for k, v in local.azs : "${var.name}-private-${v}"],
    [for k, v in local.azs : "${var.name}-private-secondary1-${v}"],
    [for i in range(length(local.additional_node_cidrs)) :
    "${var.name}-private-secondary${floor(i / length(local.azs)) + 2}-${local.azs[i % length(local.azs)]}"]
  )
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

  # Secondary CIDRs - Private subnets for EKS pods and nodes.
  # local.additional_node_cidrs is appended, so the existing associations keep their index.
  secondary_cidr_blocks = concat(var.secondary_cidrs, local.additional_node_cidrs)

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
  # Public subnets use prefixes 0-2. Private subnets start after them (3, 4, ...), in the
  # same order as local.private_subnet_cidrs. Existing subnets keep their prefixes.
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
