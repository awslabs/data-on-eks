#---------------------------------------------------------------
# Module de déploiement Istio en mode ambiant
#---------------------------------------------------------------
module "istio" {
  source = "./modules/istio"
  # Variables
  region           = local.region
  eks_cluster_name = local.name
  tags             = local.tags

  depends_on = [
    module.eks,
    module.vpc
  ]
}
