module "fsx-for-lustre" {
  source = "./modules/fsx-for-lustre"

  count = var.enable_aws_fsx_csi_driver ? 1 : 0

  private_subnet              = module.vpc.private_subnets[0]
  cluster_name                = module.eks.cluster_name
  tags                        = local.tags
  vpc_id                      = module.vpc.vpc_id
  private_subnets_cidr_blocks = module.vpc.private_subnets_cidr_blocks
}
