#---------------------------------------------------------------
# Supporting Network Resources
#---------------------------------------------------------------
# WARNING: This VPC module includes the creation of an Internet Gateway and NAT Gateway, which simplifies cluster deployment and testing, primarily intended for sandbox accounts.
# IMPORTANT: For preprod and prod use cases, it is crucial to consult with your security team and AWS architects to design a private infrastructure solution that aligns with your security requirements
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.1"

  name                 = local.name
  cidr                 = "10.0.0.0/16"
  azs                  = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  public_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/elb"              = 1
  }
  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/internal-elb"     = 1
  }
}
