locals {
  name = basename(path.cwd)
  # var.cluster_name is for Terratest
  cluster_name = coalesce(var.cluster_name, local.name)
  region       = "us-west-1"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 2)

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}