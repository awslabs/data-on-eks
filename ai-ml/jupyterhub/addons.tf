data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

# Use this data source to get the ARN of a certificate in AWS Certificate Manager (ACM)
data "aws_acm_certificate" "issued" {
  count    = var.jupyter_hub_auth_mechanism == "cognito" ? 1 : 0
  domain   = var.acm_certificate_domain
  statuses = ["ISSUED"]
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

locals {
  cognito_custom_domain = var.cognito_custom_domain
}
#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.20"
  role_name_prefix      = format("%s-%s", local.name, "ebs-csi-driver-")
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  tags = local.tags
}

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.2"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn
  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
  eks_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    coredns = {
      preserve = true
    }
    vpc-cni = {
      preserve = true
    }
    kube-proxy = {
      preserve = true
    }
  }

  #---------------------------------------
  # Kubernetes Add-ons
  #---------------------------------------
  #---------------------------------------------------------------
  # CoreDNS Autoscaler helps to scale for large EKS Clusters
  #   Further tuning for CoreDNS is to leverage NodeLocal DNSCache -> https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/
  #---------------------------------------------------------------
  enable_cluster_proportional_autoscaler = true
  cluster_proportional_autoscaler = {
    timeout = "300"
    values = [templatefile("${path.module}/helm-values/coredns-autoscaler-values.yaml", {
      target = "deployment/coredns"
    })]
    description = "Cluster Proportional Autoscaler for CoreDNS Service"
  }

  #---------------------------------------
  # Metrics Server
  #---------------------------------------
  enable_metrics_server = true
  metrics_server = {
    timeout = "300"
    values  = [templatefile("${path.module}/helm-values/metrics-server-values.yaml", {})]
  }

  #---------------------------------------
  # Cluster Autoscaler
  #---------------------------------------
  enable_cluster_autoscaler = true
  cluster_autoscaler = {
    timeout     = "300"
    create_role = true
    values = [templatefile("${path.module}/helm-values/cluster-autoscaler-values.yaml", {
      aws_region     = var.region,
      eks_cluster_id = module.eks.cluster_name
    })]
  }

  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
  enable_karpenter                  = true
  karpenter_enable_spot_termination = true
  karpenter = {
    timeout             = "300"
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

  #---------------------------------------
  # CloudWatch metrics for EKS
  #---------------------------------------
  enable_aws_cloudwatch_metrics = true
  aws_cloudwatch_metrics = {
    timeout = "300"
    values  = [templatefile("${path.module}/helm-values/aws-cloudwatch-metrics-values.yaml", {})]
  }

  enable_aws_load_balancer_controller = true

  tags = local.tags
}

#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "eks_data_addons" {
  source  = "aws-ia/eks-data-addons/aws"
  version = "~> 1.0" # ensure to update this to the latest/desired version

  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------------------------------
  # Enable GPU operator
  #---------------------------------------------------------------
  enable_nvidia_gpu_operator = var.jupyter_notebook_support == "gpu" ? true : false
  nvidia_gpu_operator_helm_config = {
    values = [templatefile("${path.module}/helm-values/nvidia-values.yaml", {})]
  }
  #---------------------------------------------------------------
  # JupyterHub Add-on
  #---------------------------------------------------------------
  enable_jupyterhub = true
  jupyterhub_helm_config = {
    values = [templatefile("${path.module}/helm-values/jupyterhub-values-${var.jupyter_hub_auth_mechanism}-${var.jupyter_notebook_support}.yaml", {
      ssl_cert_arn                = try(data.aws_acm_certificate.issued[0].arn, "")
      jupyterdomain               = try("https://${var.jupyterhub_domain}/hub/oauth_callback", "")
      authorize_url               = try("https://${local.cognito_custom_domain}.auth.${local.region}.amazoncognito.com/oauth2/authorize", "")
      token_url                   = try("https://${local.cognito_custom_domain}.auth.${local.region}.amazoncognito.com/oauth2/token", "")
      userdata_url                = try("https://${local.cognito_custom_domain}.auth.${local.region}.amazoncognito.com/oauth2/userInfo", "")
      client_id                   = try(aws_cognito_user_pool_client.user_pool_client[0].id, "")
      client_secret               = try(aws_cognito_user_pool_client.user_pool_client[0].client_secret, "")
      jupyter_single_user_sa_name = kubernetes_service_account_v1.jupyterhub_single_user_sa.metadata[0].name
    })]
  }
}
