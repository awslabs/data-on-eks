#---------------------------------------------------------------
# Local variables
#---------------------------------------------------------------
locals {
  name         = var.name
  region       = var.region
  cluster_name = format("%s-%s", local.name, "cluster")

  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}
