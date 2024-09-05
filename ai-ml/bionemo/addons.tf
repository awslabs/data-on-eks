#---------------------------------------------------------------
# EKS Blueprints Kubernetes Addons
#---------------------------------------------------------------
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.3"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
  eks_addons = {
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
  # CloudWatch metrics for EKS
  #---------------------------------------
  enable_aws_cloudwatch_metrics = false
  aws_cloudwatch_metrics = {
    values = [templatefile("${path.module}/helm-values/aws-cloudwatch-metrics-values.yaml", {})]
  }

  #---------------------------------------
  # Kubernetes Metrics Server
  #---------------------------------------
  enable_metrics_server = true
  

  #---------------------------------------
  # Enable FSx for Lustre CSI Driver
  #---------------------------------------
  enable_aws_fsx_csi_driver = true

  tags = local.tags

}

#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "eks_data_addons" {
  source  = "aws-ia/eks-data-addons/aws"
  version = "~> 1.30" # ensure to update this to the latest/desired version

  oidc_provider_arn           = module.eks.oidc_provider_arn
  enable_nvidia_device_plugin = true

}
