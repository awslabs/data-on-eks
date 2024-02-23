#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.20"
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
  # EFS CSI driver
  #---------------------------------------
  enable_aws_efs_csi_driver = true

  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
  enable_karpenter                  = true
  karpenter_enable_spot_termination = true
  karpenter = {
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

  tags = local.tags

}


#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "eks_data_addons" {
  source  = "aws-ia/eks-data-addons/aws"
  version = "~> 1.2.3" # ensure to update this to the latest/desired version

  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------------------------------
  # NVIDIA GPU Operator Add-on
  #---------------------------------------------------------------
  enable_nvidia_gpu_operator = true
  nvidia_gpu_operator_helm_config = {
    values = [templatefile("${path.module}/helm-values/nvidia-values.yaml", {})]
  }

}

#---------------------------------------
# Karpenter Provisioners for workloads
#---------------------------------------
data "kubectl_path_documents" "karpenter_provisioners" {
  pattern = "${path.module}/karpenter-provisioners/*.yaml"
  vars = {
    cluster_name = module.eks.cluster_name
  }
}

resource "kubectl_manifest" "karpenter_provisioner" {
  for_each  = toset(data.kubectl_path_documents.karpenter_provisioners.documents)
  yaml_body = each.value

  depends_on = [module.eks_blueprints_addons]
}

#---------------------------------------------------------------
# MPI Operator
#---------------------------------------------------------------
data "http" "mpi_operator_yaml" {
  url = "https://raw.githubusercontent.com/kubeflow/mpi-operator/v0.4.0/deploy/v2beta1/mpi-operator.yaml"
}

data "kubectl_file_documents" "mpi_operator_yaml" {
  content = data.http.mpi_operator_yaml.response_body
}

resource "kubectl_manifest" "mpi_operator" {
  for_each   = data.kubectl_file_documents.mpi_operator_yaml.manifests
  yaml_body  = each.value
  depends_on = [module.eks.eks_cluster_id]
}