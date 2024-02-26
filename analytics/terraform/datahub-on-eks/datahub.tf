module "datahub" {
  depends_on          = [module.eks, module.eks_blueprints_addons]
  source              = "./datahub-addon"
  prefix              = local.name
  vpc_id              = local.vpc_id
  vpc_cidr            = local.vpc_cidr
  vpc_private_subnets = local.private_subnets

}
