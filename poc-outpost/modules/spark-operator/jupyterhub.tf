#-----------------------------------------------------------------------------------------
# JupyterHub Single User IRSA Configuration
#-----------------------------------------------------------------------------------------
resource "kubernetes_namespace" "jupyterhub" {
  metadata {
    name = "jupyterhub"
  }
}

module "jupyterhub_single_user_irsa" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "~> 5.52.0"
  role_name = "${local.name}-jupyterhub-single-user-sa"

  role_policy_arns = {
    policy          = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" # Policy needs to be defined based in what you need to give access to your notebook instances.
    s3tables_policy = aws_iam_policy.s3tables.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = local.oidc_provider_arn
      namespace_service_accounts = ["${kubernetes_namespace.jupyterhub.metadata[0].name}:${local.name}-jupyterhub-single-user"]
    }
  }
}

resource "kubernetes_service_account_v1" "jupyterhub_single_user_sa" {
  metadata {
    name        = "${local.name}-jupyterhub-single-user"
    namespace   = kubernetes_namespace.jupyterhub.metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.jupyterhub_single_user_irsa.iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "jupyterhub_single_user" {
  metadata {
    name      = "${local.name}-jupyterhub-single-user-secret"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.jupyterhub_single_user_sa.metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace.jupyterhub.metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}
