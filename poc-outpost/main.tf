locals {
  name   = var.name
  region = var.region

  cluster_version = var.eks_cluster_version

  # Calcul des azs
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  outpost_az      = data.aws_outposts_outpost.default.availability_zone
  non_outpost_azs = [for az in local.azs : az if az != local.outpost_az]

  # Calcul des CIDR associés
  // CIDR 10.0.32.0/19
  private_subnets_cidr = [cidrsubnet(var.vpc_cidr, 3, 1)]
  // CIDR 10.0.64.0/19
  # factice_private_subnets_cidr = [cidrsubnet(var.vpc_cidr, 8, 254)]
  factice_private_subnets_cidr = [cidrsubnet(var.vpc_cidr, 3, 2)]
  # Public subnets: seulement pour les non-Outpost AZs (10.0.1.0/24, 10.0.2.0/24)
  public_subnets_cidr = [for k, az in local.non_outpost_azs : cidrsubnet(var.vpc_cidr, 8, k + 1)]

  cognito_custom_domain = local.name
  main_domain           = var.main_domain


  tags = {
    Blueprint = local.name
    Terraform = "True"
  }
}

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

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Retrieves the IAM session context, including the ARN of the currently logged-in user/role.
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

# Used for download oci Karpenter Helm chart
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

#---------------------------------------------------------------
# Module contenant prometheus, grafana
#---------------------------------------------------------------
module "utility" {
  source = "./modules/utility"

  name              = local.name
  region            = local.region
  cluster_version   = var.eks_cluster_version
  cluster_endpoint  = module.eks.cluster_endpoint
  oidc_provider_arn = module.eks.oidc_provider_arn

  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password

  cognito_custom_domain = local.cognito_custom_domain
  cluster_issuer_name   = var.cluster_issuer_name
  main_domain           = var.main_domain
  zone_id               = local.zone_id

  tags = local.tags

  depends_on = [
    # module.eks,
    # module.vpc,
    # module.istio,
    # module.eks_blueprints_addons
  ]
}

#---------------------------------------------------------------
# Module contenant prometheus, grafana
#---------------------------------------------------------------
module "supervision" {
  source = "./modules/supervision"

  name                                = local.name
  region                              = local.region
  oidc_provider_arn                   = module.eks.oidc_provider_arn
  cluster_version                     = var.eks_cluster_version
  cluster_endpoint                    = module.eks.cluster_endpoint
  kubernetes_storage_class_default_id = "gp2"

  enable_amazon_grafana    = var.enable_amazon_grafana
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
  count  = var.enable_airflow ? 1 : 0
  source = "./modules/airflow"

  name                  = local.name
  region                = local.region
  oidc_provider_arn     = module.eks.oidc_provider_arn
  private_subnets_cidr  = local.private_subnets_cidr
  vpc_id                = module.vpc.vpc_id
  db_subnets_group_name = aws_db_subnet_group.private.name
  enable_airflow        = var.enable_airflow
  cluster_issuer_name   = var.cluster_issuer_name
  main_domain           = var.main_domain
  outpost_name          = var.outpost_name
  output_subnet_id = module.outpost_subnet.subnet_id[0]

  tags = local.tags

  depends_on = [
    #module.supervision,  # A utiliser uniquement si installation full, sinon en patch il faut laisser commenté
  ]
}

#---------------------------------------------------------------
# Module trino
#---------------------------------------------------------------
module "trino" {
  count  = var.enable_trino ? 1 : 0
  source = "./modules/trino"

  cluster_name            = local.name
  region                  = local.region
  oidc_provider_arn       = module.eks.oidc_provider_arn
  private_subnets_cidr    = local.private_subnets_cidr
  vpc_id                  = module.vpc.vpc_id
  db_subnets_group_name   = aws_db_subnet_group.private.name
  default_node_group_type = var.default_node_group_type
  outpost_name = var.outpost_name
  output_subnet_id = module.outpost_subnet.subnet_id[0]

  karpenter_node_iam_role_name = module.utility.karpenter_node_iam_role_name
  tags                         = local.tags

  cognito_user_pool_id  = module.utility.cognito_user_pool_id
  cognito_custom_domain = local.cognito_custom_domain
  cluster_issuer_name   = var.cluster_issuer_name
  zone_id               = local.zone_id
  main_domain           = var.main_domain

  depends_on = [
    #module.supervision,  # A utiliser uniquement si installation full, sinon en patch il faut laisser commenté
  ]

}

module "kafka" {
  count  = var.enable_kafka ? 1 : 0
  source = "./modules/kafka"

  name                         = local.name
  region                       = local.region
  oidc_provider_arn            = module.eks.oidc_provider_arn
  cluster_version              = var.eks_cluster_version
  cluster_endpoint             = module.eks.cluster_endpoint
  karpenter_node_iam_role_name = module.utility.karpenter_node_iam_role_name

  tags = local.tags

  depends_on = [
    module.utility,  # A utiliser uniquement si installation full, sinon en patch il faut laisser commenté
  ]
}