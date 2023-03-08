locals {
  name   = var.name
  region = var.region
  azs    = slice(data.aws_availability_zones.available.names, 0, 2)

  vpc_cidr        = "10.1.0.0/16"
  public_subnets  = ["10.1.255.128/26", "10.1.255.192/26"]
  private_subnets = ["10.1.0.0/17", "10.1.128.0/18"]

  tags = merge(var.tags, {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  })

}
