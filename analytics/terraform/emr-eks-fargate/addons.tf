################################################################################
# Kubernetes Addons
################################################################################
module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.25.0"

  eks_cluster_id        = module.eks.cluster_name
  eks_cluster_endpoint  = module.eks.cluster_endpoint
  eks_oidc_provider     = module.eks.oidc_provider
  eks_oidc_provider_arn = module.eks.oidc_provider_arn
  eks_cluster_version   = module.eks.cluster_version

  # Wait on the `kube-system` profile before provisioning addons
  data_plane_wait_arn = join(",", [for prof in module.eks.fargate_profiles : prof.fargate_profile_arn])

  # Enable Fargate logging
  enable_fargate_fluentbit = true

  tags = local.tags
}
