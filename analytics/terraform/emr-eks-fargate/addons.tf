################################################################################
# Kubernetes Addons
################################################################################
module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.23.0"

  eks_cluster_id        = module.eks.cluster_name
  eks_cluster_endpoint  = module.eks.cluster_endpoint
  eks_oidc_provider     = module.eks.oidc_provider
  eks_oidc_provider_arn = module.eks.oidc_provider_arn
  eks_cluster_version   = module.eks.cluster_version

  # Wait on the `kube-system` profile before provisioning addons
  data_plane_wait_arn = join(",", [for prof in module.eks.fargate_profiles : prof.fargate_profile_arn])

  # Enable Fargate logging
  enable_fargate_fluentbit = true

  #  Please be informed that the method of creating EMR on EKS clusters has changed and is now done as a Kubernetes add-on.
  #  This differs from previous blueprints which deployed EMR on EKS as part of the EKS Cluster module.
  #  Our team is working towards simplifying both deployment approaches and will soon create a standalone Terraform module for this purpose.
  #  Additionally, all blueprints will be updated with this new dedicated EMR on EKS Terraform module.

  enable_emr_on_eks = true
  emr_on_eks_config = {
    # Default settings
    emr-containers = {
      namespace = "emr-default"
    }
    # Example of all settings
    custom = {
      name = "emr-custom"

      create_namespace = true
      namespace        = "emr-custom"

      create_iam_role               = true
      role_name                     = "emr-custom-role"
      iam_role_use_name_prefix      = false
      iam_role_path                 = "/"
      iam_role_description          = "EMR custom Role"
      iam_role_permissions_boundary = null
      iam_role_additional_policies  = []

      tags = {
        AdditionalTags = "sure"
      }
    }
  }

  tags = local.tags
}
