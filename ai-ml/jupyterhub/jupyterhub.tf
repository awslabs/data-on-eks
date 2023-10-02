#-----------------------------------------------------------------------------------------
# JupyterHub Sinlgle User IRSA, maybe that block could be incorporated in add-on registry
#-----------------------------------------------------------------------------------------
resource "kubernetes_namespace" "jupyterhub" {
  metadata {
    name = "jupyterhub"
  }
}

module "jupyterhub_single_user_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name = "${module.eks.cluster_name}-jupyterhub-single-user-sa"

  role_policy_arns = {
    policy = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" # Policy needs to be defined based in what you need to give access to your notebook instances.
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${kubernetes_namespace.jupyterhub.metadata[0].name}:jupyterhub-single-user"]
    }
  }
}

resource "kubernetes_service_account_v1" "jupyterhub_single_user_sa" {
  metadata {
    name        = "${module.eks.cluster_name}-jupyterhub-single-user"
    namespace   = kubernetes_namespace.jupyterhub.metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.jupyterhub_single_user_irsa.iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "jupyterhub_single_user" {
  metadata {
    name      = "${module.eks.cluster_name}-jupyterhub-single-user-secret"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.jupyterhub_single_user_sa.metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace.jupyterhub.metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

#---------------------------------------------------------------
# EFS Filesystem for private volumes per user
# This will be repalced with Dynamic EFS provision using EFS CSI Driver
#---------------------------------------------------------------
resource "aws_efs_file_system" "efs" {
  encrypted = true

  tags = local.tags
}

resource "aws_efs_mount_target" "efs_mt" {
  count = length(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) : substr(cidr_block, 0, 4) == "100." ? subnet_id : null]))

  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = element(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) : substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), count.index)
  security_groups = [aws_security_group.efs.id]
}

resource "aws_security_group" "efs" {
  name        = "${local.name}-efs"
  description = "Allow inbound NFS traffic from private subnets of the VPC"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow NFS 2049/tcp"
    cidr_blocks = module.vpc.vpc_secondary_cidr_blocks
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
  }

  tags = local.tags
}

#---------------------------------------
# EFS Configuration
#---------------------------------------
module "efs_config" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.2"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  helm_releases = {
    efs = {
      name             = "efs"
      description      = "A Helm chart for storage configurations"
      namespace        = "jupyterhub"
      create_namespace = false
      chart            = "${path.module}/helm/efs"
      chart_version    = "0.0.1"
      values = [
        <<-EOT
          pv:
            name: efs-persist
            dnsName: ${aws_efs_file_system.efs.dns_name}
          pvc:
            name: efs-persist
        EOT
      ]
    }
    efs-shared = {
      name             = "efs-shared"
      description      = "A Helm chart for shared storage configurations"
      namespace        = "jupyterhub"
      create_namespace = false
      chart            = "${path.module}/helm/efs"
      chart_version    = "0.0.1"
      values = [
        <<-EOT
          pv:
            name: efs-persist-shared
            dnsName: ${aws_efs_file_system.efs.dns_name}
          pvc:
            name: efs-persist-shared
        EOT
      ]
    }
  }

  depends_on = [kubernetes_namespace.jupyterhub]
}

#---------------------------------------------------------------
# Cognito pool, domain and client creation.
# This can be used
# Auth integration later.
#----------------------------------------------------------------
resource "aws_cognito_user_pool" "pool" {
  count = var.jupyter_hub_auth_mechanism == "cognito" ? 1 : 0
  name  = "jupyterhub-userpool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
  }
}

resource "random_string" "random" {
  count   = var.jupyter_hub_auth_mechanism == "cognito" ? 1 : 0
  length  = 8
  special = false
  lower   = true
  upper   = false
}

resource "aws_cognito_user_pool_domain" "domain" {
  count        = var.jupyter_hub_auth_mechanism == "cognito" ? 1 : 0
  domain       = "${local.cognito_custom_domain}-${random_string.random[0].result}"
  user_pool_id = aws_cognito_user_pool.pool[0].id
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  count                                = var.jupyter_hub_auth_mechanism == "cognito" ? 1 : 0
  name                                 = "jupyter-client"
  callback_urls                        = ["https://${var.jupyterhub_domain}/hub/oauth_callback"]
  user_pool_id                         = aws_cognito_user_pool.pool[0].id
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email"]
  generate_secret                      = true
  supported_identity_providers = [
    "COGNITO"
  ]

  depends_on = [aws_cognito_user_pool_domain.domain]
}
