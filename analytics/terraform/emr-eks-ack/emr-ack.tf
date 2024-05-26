module "emr_ack" {
  source = "./modules/emr-ack"

  eks_cluster_id                 = module.eks.cluster_name
  eks_oidc_provider_arn          = module.eks.oidc_provider_arn
  ecr_public_repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  ecr_public_repository_password = data.aws_ecrpublic_authorization_token.token.password
}
