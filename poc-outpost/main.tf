# Récupération des informations pour la connexion au cluster EKS
# Utilise en particulier pour les modules helm et kubectl
data "aws_eks_cluster_auth" "this" {
  name = local.name
}
# Read AZ for current region
data "aws_availability_zones" "available" {}
# Read Outpost informations
data "aws_outposts_outpost" "default" {
  name = var.outpost_name
}

#data "aws_lbs" "all" {}


data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# data "aws_ecrpublic_authorization_token" "token" {
#   provider = aws.virginia
# }

# Retrieves the IAM session context, including the ARN of the currently logged-in user/role.
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

#---------------------------------------------------------------
# Module contenant prometheus, grafana
#---------------------------------------------------------------
module "utility" {
  source = "./modules/utility"

  name           = local.name
  region         = local.region
  cluster_version = var.eks_cluster_version
  cluster_endpoint = module.eks.cluster_endpoint
  oidc_provider_arn = module.eks.oidc_provider_arn

  tags = local.tags

  depends_on = [
    module.eks,
    module.vpc,
    module.eks_blueprints_addons
  ]
}

#---------------------------------------------------------------
# Module contenant prometheus, grafana
#---------------------------------------------------------------
module "supervision" {
  source = "./modules/supervision"

  name           = local.name
  region         = local.region
  oidc_provider_arn = module.eks.oidc_provider_arn
  cluster_version   = var.eks_cluster_version
  cluster_endpoint  = module.eks.cluster_endpoint
  kubernetes_storage_class_default_id = "gp2"

  enable_amazon_grafana = var.enable_amazon_grafana
  enable_amazon_prometheus = var.enable_amazon_prometheus

  tags = local.tags

  depends_on = [
    #module.utility,  # A utiliser uniquement si installation full, sinon en patch il faut laisser commenté
  ]
}

#---------------------------------------------------------------
# Module airflow
#---------------------------------------------------------------
module "airflow" {
  source = "./modules/airflow"

  name           = local.name
  region         = local.region
  oidc_provider_arn = module.eks.oidc_provider_arn
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = var.eks_cluster_version
  private_subnets_cidr = local.private_subnets_cidr
  vpc_id = module.vpc.vpc_id
  db_subnets_group_name = aws_db_subnet_group.private.name
  enable_airflow = var.enable_airflow

  tags = local.tags

  depends_on = [
    #module.supervision,  # A utiliser uniquement si installation full, sinon en patch il faut laisser commenté
  ]

}

locals {
  name   = var.name
  region = var.region

  cluster_version = var.eks_cluster_version

  # Calcul des azs
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
  outpost_az = data.aws_outposts_outpost.default.availability_zone
  non_outpost_azs = [for az in local.azs : az if az != local.outpost_az]

  # Calcul des CIDR associés
  // CIDR 10.0.0.0/24
  private_subnets_cidr = [cidrsubnet(var.vpc_cidr, 8, 0)]
  // CIDR 10.0.254.0/24
  factice_private_subnets_cidr = [cidrsubnet(var.vpc_cidr, 8, 254)]
  # Public subnets: seulement pour les non-Outpost AZs (10.0.1.0/24, 10.0.2.0/24)
  public_subnets_cidr = [for k, az in local.non_outpost_azs : cidrsubnet(var.vpc_cidr, 8, k + 1)]

  # account_id = data.aws_caller_identity.current.account_id
  # partition  = data.aws_partition.current.partition

  tags = {
    Blueprint  = local.name
    Terraform = "True"
  }
}