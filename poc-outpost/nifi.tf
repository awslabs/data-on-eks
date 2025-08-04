#---------------------------------------------------------------
# Module de déploiement Nifi 
#---------------------------------------------------------------
module "nifi" {
  count  = 0
  source = "./modules/nifi"
  # Variables
  region           = local.region
  eks_cluster_name = local.name
  tags             = local.tags

  depends_on = [
    module.eks,
    module.vpc
  ]
}
