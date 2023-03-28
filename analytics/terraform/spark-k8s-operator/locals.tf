locals {
  name     = var.name
  region   = var.region
  vpc_cidr = var.vpc_cidr
  azs      = slice(data.aws_availability_zones.available.names, 0, 2)

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

}
