#---------------------------------------------------------------
# GP3 Encrypted Storage Class
#---------------------------------------------------------------
resource "kubernetes_annotations" "default_gp2" {
  annotations = {
    "storageclass.kubernetes.io/is-default-class" : "true"
    "allow_volume_expansion" : "true"
  }
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }
  force = true

  depends_on = [module.eks]
}

#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.34"
  role_name_prefix      = format("%s-%s-", local.name, "ebs-csi-driver")
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
  # AWS Load Balancer Controller Add-on
  #---------------------------------------
  enable_aws_load_balancer_controller = true
  # turn off the mutating webhook for services because we are using
  # service.beta.kubernetes.io/aws-load-balancer-type: external
  aws_load_balancer_controller = {
    set = [
      {
        name  = "enableServiceMutatorWebhook"
        value = "false"
      }
    ]
  }

  #---------------------------------------
  # AWS for FluentBit
  #---------------------------------------
  #   enable_aws_for_fluentbit = true
  #   aws_for_fluentbit_cw_log_group = {
  #     use_name_prefix   = false
  #     name              = "/${local.name}/aws-fluentbit-logs" # Add-on creates this log group
  #     retention_in_days = 30
  #   }
  #   aws_for_fluentbit = {
  #     values = [templatefile("${path.module}/helm/aws-for-fluentbit/values.yaml", {
  #       region               = local.region,
  #       cloudwatch_log_group = "/${local.name}/aws-fluentbit-logs"
  #       cluster_name         = module.eks.cluster_name
  #     })]
  #   }
  tags = local.tags
}
