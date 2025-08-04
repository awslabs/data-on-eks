#---------------------------------------------------------------
# Module de déploiement Nifi 
#---------------------------------------------------------------
module "nifi2" {
  count = var.apply_nifi2 ? 1 : 0
  source = "./modules/nifi2"
  # Variables
  region           = local.region
  eks_cluster_name = local.name
  tags             = local.tags

  keycloak_url = var.keycloak_url
  client_keycloak = var.client_keycloak_nifi
  secret_keycloak = var.secret_keycloak_nifi
}