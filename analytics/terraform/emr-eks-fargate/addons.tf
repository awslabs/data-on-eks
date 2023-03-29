################################################################################
# Kubernetes Addons
################################################################################
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
    coredns = {
      preserve = true
      configuration_values = jsonencode({
        computeType = "Fargate"
        # Ensure that the we fully utilize the minimum amount of resources that are supplied by
        # Fargate https://docs.aws.amazon.com/eks/latest/userguide/fargate-pod-configuration.html
        # Fargate adds 256 MB to each pod's memory reservation for the required Kubernetes
        # components (kubelet, kube-proxy, and containerd). Fargate rounds up to the following
        # compute configuration that most closely matches the sum of vCPU and memory requests in
        # order to ensure pods always have the resources that they need to run.
        resources = {
          limits = {
            cpu = "0.25"
            # We are targetting the smallest Task size of 512Mb, so we subtract 256Mb from the
            # request/limit to ensure we can fit within that task
            memory = "256M"
          }
          requests = {
            cpu = "0.25"
            # We are targetting the smallest Task size of 512Mb, so we subtract 256Mb from the
            # request/limit to ensure we can fit within that task
            memory = "256M"
          }
        }
      })
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
  # Fargate FluentBit
  #---------------------------------------
  enable_fargate_fluentbit = true

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
