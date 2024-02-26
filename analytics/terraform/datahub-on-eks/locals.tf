locals {
  name   = var.name
  region = var.region

  vpc_cidr = var.vpc_cidr
  azs      = slice(data.aws_availability_zones.available.names, 0, 2)

  tags = merge(var.tags, {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  })

  vpc_id          = var.create_vpc ? module.vpc.vpc_id : var.vpc_id
  private_subnets = var.create_vpc ? module.vpc.private_subnets : var.private_subnet_ids
}
