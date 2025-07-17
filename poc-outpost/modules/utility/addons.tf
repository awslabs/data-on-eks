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

resource "kubernetes_service_account" "cert_manager_sa" {
  metadata {
    name      = "${local.cert_service_account}"
    namespace = "${local.cert_manager_namespace}"

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.cert_manager_irsa_role.arn
    }
  }
}

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.2"

  cluster_name      = local.name
  cluster_endpoint  = local.cluster_endpoint
  cluster_version   = local.cluster_version
  oidc_provider_arn = local.oidc_provider_arn

  # ---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  # ---------------------------------------
  # enable_karpenter = true
  # karpenter = {
  #   chart_version       = "1.0.5"
  #   repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  #   repository_password = data.aws_ecrpublic_authorization_token.token.password
  # }
  # karpenter_enable_spot_termination          = true
  # karpenter_enable_instance_profile_creation = true
  # karpenter_node = {
  #   iam_role_use_name_prefix = false
  #   iam_role_additional_policies = {
  #     AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  #   }
  # }

  #---------------------------------------
  # Cluster Autoscaler
  #---------------------------------------
  enable_cluster_autoscaler = false
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

##
# Create a wildcard ACM certificate for the domain
##
resource "aws_acm_certificate" "cert" {
  domain_name       = "*.${local.main_domain}"
  validation_method = "DNS"

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Ajouter automatiquement l'enregistrement DNS de validation
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

# Attendre que la validation soit terminée
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

resource "aws_cognito_user_pool" "main_pool" {
  name = "main-user-pool"
}

resource "aws_cognito_user_pool_domain" "main_domain" {
  domain       = local.cognito_custom_domain
  user_pool_id = aws_cognito_user_pool.main_pool.id
}
