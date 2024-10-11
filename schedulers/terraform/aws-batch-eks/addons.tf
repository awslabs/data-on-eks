#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = ">= 5.44"

  role_name = join("_", [var.eks_cluster_name, "ebs-csi"])

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
# IRSA for CloudWatch EKS Managed Add-on
#---------------------------------------------------------------
module "cloudwatch_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = ">= 5.44"

  role_name = join("_", [var.eks_cluster_name, "cloudwatch"])

  attach_cloudwatch_observability_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cloudwatch-agent"]
    }
  }
}

#---------------------------------------------------------------
# EKS Blueprints Addons
#---------------------------------------------------------------
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
    vpc-cni = {
      version = "latest"
    }
    kube-proxy = {
      version = "latest"

    }
    coredns = {
      version = "latest"
    }
    aws-ebs-csi-driver = {
      version                  = "latest"
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn

    }
    amazon-cloudwatch-observability = {
      version                  = "latest"
      resolve_conflicts        = "OVERWRITE"
      service_account_role_arn = module.cloudwatch_irsa_role.iam_role_arn
      configuration_values = jsonencode(
        {
          "agent" : {
            "config" : {
              "logs" : {
                "metrics_collected" : {
                  "app_signals" : {},
                  "kubernetes" : {
                    "accelerated_compute_metrics" : false, "enhanced_container_insights" : false
                  }
                }
              },
              "containerLogs" : {
                "enabled" : true
              }
            }
          },
          "tolerations" : [{
            "key" : "batch.amazonaws.com/batch-node",
            "operator" : "Exists"
          }]
        }
      )
    }
  }
  tags = local.tags
}
