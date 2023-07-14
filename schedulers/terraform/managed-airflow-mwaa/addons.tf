#------------------------------------------------------------------------
# EKS Addons
#------------------------------------------------------------------------
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

  enable_metrics_server = true
  enable_cluster_autoscaler = true
  enable_cloudwatch_metrics = true

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

#---------------------------------------------------------------
# Example IAM policies for EMR job execution
#---------------------------------------------------------------
resource "aws_iam_policy" "emr_on_eks" {
  name        = format("%s-%s", local.name, "emr-job-iam-policies")
  description = "IAM policy for EMR on EKS Job execution"
  path        = "/"
  policy      = data.aws_iam_policy_document.emr_on_eks.json
}

#----------------------------------------------------------------------------
# EMR on EKS
#----------------------------------------------------------------------------
module "emr_containers" {
  depends_on = [module.eks_blueprints_kubernetes_addons]
  source = "../../../workshop/modules/emr-eks-containers"

  eks_cluster_id        = module.eks.cluster_name
  eks_oidc_provider_arn = module.eks.oidc_provider_arn

  emr_on_eks_config = {
    # Example of all settings
    emr-mwaa-team = {
      name = format("%s-%s", module.eks.cluster_name, "emr-mwaa-team")
      namespace               = "emr-mwaa"
      execution_iam_role_description      = "EMR execution role emr-eks-mwaa-team"
      execution_iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"]
      create_namespace = true
    }
  }
}

