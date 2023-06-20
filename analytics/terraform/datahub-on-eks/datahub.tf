module "datahub" {
  depends_on          = [module.eks, module.eks_blueprints_kubernetes_addons]
  source              = "./datahub-addon"
  prefix              = local.name
  vpc_id              = module.vpc.vpc_id
  vpc_cidr            = local.vpc_cidr
  vpc_private_subnets = module.vpc.private_subnets

  create_iam_service_linked_role_es = var.create_iam_service_linked_role_es
}
