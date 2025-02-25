#---------------------------------------------------------------
# Locals
#---------------------------------------------------------------

locals {
  name   = var.name
  region = var.region

  # Routable Private subnets only for Private NAT Gateway -> Transit Gateway -> Second VPC for overlapping CIDRs
  # e.g., var.vpc_cidr = "10.1.0.0/21" => output: ["10.1.0.0/24", "10.1.1.0/24"] => 256-2 = 254 usable IPs per subnet/AZ
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 3, k)]
  # Routable Public subnets with NAT Gateway and Internet Gateway
  # e.g., var.vpc_cidr = "10.1.0.0/21" => output: ["10.1.2.0/26", "10.1.2.64/26"] => 64-2 = 62 usable IPs per subnet/AZ
  public_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 5, k + 8)]
  # RFC6598 range 100.64.0.0/16 for EKS Data Plane for two subnets(32768 IPs per Subnet) across two AZs for EKS Control Plane ENI + Nodes + Pods
  # e.g., var.secondary_cidr_blocks = "100.64.0.0/16" => output: ["100.64.0.0/17", "100.64.128.0/17"] => 32768-2 = 32766 usable IPs per subnet/AZ
  secondary_ip_range_private_subnets = [for k, v in local.azs : cidrsubnet(element(var.secondary_cidr_blocks, 0), 1, k)]

  # Trn1 and Inf2 instances are available in specific AZs in us-east-1,
  # us-east-2, and us-west-2. For Trn1, the first AZ id (below) should be used.
  az_mapping = {
    "us-west-2" = ["usw2-az4", "usw2-az1"],
    "us-east-1" = ["use1-az6", "use1-az5"],
    "us-east-2" = ["use2-az3", "use2-az1"]
  }

  azs = local.az_mapping[var.region]
  
  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}
