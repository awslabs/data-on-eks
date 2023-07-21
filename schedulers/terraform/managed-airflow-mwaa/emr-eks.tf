#----------------------------------------------------------------------------
# EMR on EKS
#----------------------------------------------------------------------------
module "emr_containers" {
  source  = "terraform-aws-modules/emr/aws//modules/virtual-cluster"
  version = "~> 1.0"

  eks_cluster_id    = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn

  name                         = format("%s-%s", module.eks.cluster_name, "emr-mwaa-team")
  namespace                    = "emr-mwaa"
  iam_role_description         = "EMR execution role emr-eks-mwaa-team"
  iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"]

  tags = merge(local.tags, { Name = "emr-mwaa" })
}
