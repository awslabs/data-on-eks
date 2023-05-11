locals {
  name   = var.name
  region = var.region
  cog_domain_name    = var.cognito_domain
  azs    = slice(data.aws_availability_zones.available.names, 0, 3)
  efs_storage_class             = "efs-sc"
  efs_pvc                       = "efs-pvc"
  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}
