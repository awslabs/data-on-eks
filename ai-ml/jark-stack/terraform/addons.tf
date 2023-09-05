#---------------------------------------------------------------
# GP3 Encrypted Storage Class
#---------------------------------------------------------------
resource "kubernetes_annotations" "disable_gp2" {
  annotations = {
    "storageclass.kubernetes.io/is-default-class" : "false"
  }
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }
  force = true

  depends_on = [module.eks.eks_cluster_id]
}

resource "kubernetes_storage_class" "default_gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" : "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = {
    fsType    = "xfs"
    encrypted = true
    type      = "gp3"
  }

  depends_on = [kubernetes_annotations.disable_gp2]
}

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
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    coredns = {
      preserve = true
    }
    kube-proxy = {
      preserve = true
    }
    # VPC CNI uses worker node IAM role policies
    vpc-cni = {
      preserve = true
    }
  }

  #---------------------------------------
  # AWS Load Balancer Controller Add-on
  #---------------------------------------
  enable_aws_load_balancer_controller = true

  #---------------------------------------
  # Ingress Nginx Add-on
  #---------------------------------------
  enable_ingress_nginx = true
  ingress_nginx = {
    values = [templatefile("${path.module}/helm-values/ingress-nginx-values.yaml", {})]
  }

  helm_releases = {
    #---------------------------------------
    # NVIDIA Device Plugin Add-on
    #---------------------------------------
    nvidia-device-plugin = {
      description      = "A Helm chart for NVIDIA Device Plugin"
      namespace        = "nvidia-device-plugin"
      create_namespace = true
      chart            = "nvidia-device-plugin"
      chart_version    = "0.14.0"
      repository       = "https://nvidia.github.io/k8s-device-plugin"
      values           = [file("${path.module}/helm-values/nvidia-values.yaml")]
    }
  }
}

#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "data_addons" {
  source  = "aws-ia/eks-data-addons/aws"
  version = "~> 1.1" # ensure to update this to the latest/desired version

  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------------------------------
  # JupyterHub Add-on
  #---------------------------------------------------------------
  enable_jupyterhub = true
  jupyterhub_helm_config = {
    version          = "3.0.3"
    namespace        = kubernetes_namespace_v1.jupyterhub.id
    create_namespace = false
    values           = [file("${path.module}/helm-values/jupyterhub-values.yaml")]
  }

  #---------------------------------------------------------------
  # KubeRay Operator Add-on
  #---------------------------------------------------------------
  enable_kuberay_operator = true

  depends_on = [
    kubernetes_secret_v1.huggingface_token,
    kubernetes_config_map_v1.notebook
  ]
}


#---------------------------------------------------------------
# Additional Resources
#---------------------------------------------------------------

resource "kubernetes_namespace_v1" "jupyterhub" {
  metadata {
    name = "jupyterhub"
  }
}


resource "kubernetes_secret_v1" "huggingface_token" {
  metadata {
    name      = "hf-token"
    namespace = kubernetes_namespace_v1.jupyterhub.id
  }

  data = {
    token = var.huggingface_token
  }
}

resource "kubernetes_config_map_v1" "notebook" {
  metadata {
    name      = "notebook"
    namespace = kubernetes_namespace_v1.jupyterhub.id
  }

  data = {
    "dogbooth.ipynb" = file("${path.module}/src/notebook/dogbooth.ipynb")
  }
}
