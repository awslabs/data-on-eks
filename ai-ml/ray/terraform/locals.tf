#---------------------------------------------------------------
# Local Variables
#---------------------------------------------------------------
locals {
  name   = var.name
  region = var.region

  vpc_cidr           = "10.0.0.0/16"
  secondary_vpc_cidr = "100.64.0.0/16"
  azs                = slice(data.aws_availability_zones.available.names, 0, 3)

  cluster_version = var.eks_cluster_version

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}
