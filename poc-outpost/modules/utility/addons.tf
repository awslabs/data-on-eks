data "aws_iam_openid_connect_provider" "oidc" {
  arn = local.oidc_provider_arn
}

data "aws_route53_zone" "main" {
  name         = local.main_domain
  private_zone = false
}

resource "aws_iam_policy" "cert_manager_dns01" {
  name = "cert-manager-dns01-route53"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "route53:GetChange",
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ],
        Resource = "arn:aws:route53:::hostedzone/${local.zone_id}"
      },
      {
        Effect = "Allow",
        Action = [
          "route53:ListHostedZones",
          "route53:ListHostedZonesByName"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "cert_manager_irsa_role" {
  name = "CertManagerIRSA"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.oidc.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_iam_openid_connect_provider.oidc.url, "https://", "")}:sub" = "system:serviceaccount:${local.cert_manager_namespace}:${local.cert_service_account}"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cert_manager_route53_attach" {
  role       = aws_iam_role.cert_manager_irsa_role.name
  policy_arn = aws_iam_policy.cert_manager_dns01.arn
}



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
    set = [
      {
        name  = "serviceAccount.name"
        value = "${local.cert_service_account}"
      },
      {
        name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
        value = aws_iam_role.cert_manager_irsa_role.arn
      }
    ]

  }

}

resource "kubernetes_service_account" "cert_manager_sa" {
  metadata {
    name      = "${local.cert_service_account}"
    namespace = "${local.cert_manager_namespace}"

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.cert_manager_irsa_role.arn
    }
  }
  depends_on = [module.eks_blueprints_addons]
}


### Create a Cognito User Pool and Domain

resource "aws_cognito_user_pool" "main_pool" {
  name = "main-user-pool"
}

resource "aws_cognito_user_pool_domain" "main_domain" {
  domain       = local.cognito_custom_domain
  user_pool_id = aws_cognito_user_pool.main_pool.id
}
