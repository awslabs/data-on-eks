locals {
  name   = var.name
  region = var.region

  vpc_cidr = data.aws_vpc.eks_vpc.cidr_block
  azs      = slice(data.aws_availability_zones.available.names, 0, 2)

  tags = merge(var.tags, {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  })
}
