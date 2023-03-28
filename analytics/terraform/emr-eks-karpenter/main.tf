
#---------------------------------------
# Karpenter IAM instance profile
#---------------------------------------

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 19.9"

  cluster_name                 = data.aws_eks_cluster.cluster.name
  irsa_oidc_provider_arn       = data.aws_iam_openid_connect_provider.eks_oidc.arn
  create_irsa                  = false # EKS Blueprints add-on module creates IRSA
  enable_spot_termination      = false # EKS Blueprints add-on module adds this feature
  tags                         = local.tags
  iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
}
