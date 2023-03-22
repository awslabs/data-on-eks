
module "eks_blueprints_kubernetes_addons" {
  # Users should pin the version to the latest available release
  # tflint-ignore: terraform_module_pinned_source
  source = "github.com/aws-ia/terraform-aws-eks-blueprints-addons?ref=08650fd2b4bc894bde7b51313a8dc9598d82e925"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider     = module.eks.cluster_oidc_issuer_url
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
      service_account_role_arn = module.vpc_cni_irsa.iam_role_arn
      preserve                 = true
    }
    kube-proxy = {
      preserve = true
    }
  }

  #---------------------------------------
  # Kubernetes Add-ons
  #---------------------------------------
  #---------------------------------------
  # Metrics Server
  #---------------------------------------
  enable_metrics_server = true

  #---------------------------------------
  # Cluster Autoscaler
  #---------------------------------------
  enable_cluster_autoscaler = true

  #---------------------------------------
  # CloudWatch metrics for EKS
  #---------------------------------------
  enable_cloudwatch_metrics = true

  #---------------------------------------
  # AWS for FluentBit - DaemonSet
  #---------------------------------------
  enable_aws_for_fluentbit                 = true
  aws_for_fluentbit_cw_log_group_name      = "/${var.name}/fluentbit-logs" # Add-on creates this log group
  aws_for_fluentbit_cw_log_group_retention = 30
  aws_for_fluentbit_helm_config = {
    name       = "aws-for-fluent-bit"
    chart      = "aws-for-fluent-bit"
    repository = "https://aws.github.io/eks-charts"
    version    = "0.1.21"
    namespace  = "aws-for-fluent-bit"
    values = [templatefile("${path.module}/helm-values/aws-for-fluentbit-values.yaml", {
      region               = var.region,
      cloudwatch_log_group = "/${var.name}/fluentbit-logs"
    })]
  }

  tags = local.tags
}


#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.14"
  role_name             = format("%s-%s", local.name, "ebs-csi-driver")
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  tags = local.tags
}

#---------------------------------------------------------------
# IRSA for VPC CNI
#---------------------------------------------------------------
module "vpc_cni_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.14"
  role_name             = format("%s-%s", local.name, "vpc-cni")
  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }
  tags = local.tags
}
