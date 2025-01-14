#-----------------------------------------------------------------------------------------
# JupyterHub Single User IRSA Configuration
#-----------------------------------------------------------------------------------------
resource "kubernetes_namespace" "jupyterhub" {
  count = var.enable_jupyterhub ? 1 : 0
  metadata {
    name = "jupyterhub"
  }
}

module "jupyterhub_single_user_irsa" {
  count     = var.enable_jupyterhub ? 1 : 0
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "~> 5.52.0"
  role_name = "${module.eks.cluster_name}-jupyterhub-single-user-sa"

  role_policy_arns = {
    policy          = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" # Policy needs to be defined based in what you need to give access to your notebook instances.
    s3tables_policy = aws_iam_policy.s3tables.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${kubernetes_namespace.jupyterhub[0].metadata[0].name}:${module.eks.cluster_name}-jupyterhub-single-user"]
    }
  }
}

resource "kubernetes_service_account_v1" "jupyterhub_single_user_sa" {
  count = var.enable_jupyterhub ? 1 : 0
  metadata {
    name        = "${module.eks.cluster_name}-jupyterhub-single-user"
    namespace   = kubernetes_namespace.jupyterhub[0].metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.jupyterhub_single_user_irsa[0].iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "jupyterhub_single_user" {
  count = var.enable_jupyterhub ? 1 : 0
  metadata {
    name      = "${module.eks.cluster_name}-jupyterhub-single-user-secret"
    namespace = kubernetes_namespace.jupyterhub[0].metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.jupyterhub_single_user_sa[0].metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace.jupyterhub[0].metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}
