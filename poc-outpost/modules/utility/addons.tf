module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.2"

  cluster_name      = local.name
  cluster_endpoint  = local.cluster_endpoint
  cluster_version   = local.cluster_version
  oidc_provider_arn = local.oidc_provider_arn

  #---------------------------------------
  # Cluster Autoscaler
  #---------------------------------------
  enable_cluster_autoscaler = true
  cluster_autoscaler = {
    values = [templatefile("${path.module}/helm-values/cluster-autoscaler-values.yaml", {
      aws_region     = local.region,
      eks_cluster_id = local.name
    })]
  }

  # ---------------------------------------
  # Keda
  # ---------------------------------------
  helm_releases = {
    keda = {
      chart            = "keda"
      chart_version    = "2.16.0"
      repository       = "https://kedacore.github.io/charts"
      description      = "Keda helm Chart deployment"
      namespace        = "keda"
      create_namespace = true
    }
  }

  # ---------------------------------------
  # cert manager
  # ---------------------------------------
  enable_cert_manager = true
  cert_manager = {
    chart_version    = "v1.11.1"
    namespace        = local.cert_manager_namespace
    create_namespace = true
  }
}

resource "aws_cognito_user_pool" "main_pool" {
  name = "main-user-pool"
}

resource "aws_cognito_user_pool_domain" "main_domain" {
  domain       = local.cognito_custom_domain
  user_pool_id = aws_cognito_user_pool.main_pool.id
}
