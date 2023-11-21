locals {
  name   = var.name
  region = var.region

  trino_namespace = var.namespace
  trino_sa        = var.trino_sa

  catalog_type    = var.catalog_type

  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}
