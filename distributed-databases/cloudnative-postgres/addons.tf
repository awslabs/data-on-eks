module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0" #ensure to update this to the latest/desired version

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
  enable_kube_prometheus_stack = true
  helm_releases = {
    kube_prometheus_stack = {
      namespace        = "monitoring"
      name             = "prometheus"
      create_namespace = true
      chart            = "kube-prometheus-stack"
      repository       = "https://prometheus-community.github.io/helm-charts"

      values = [
        file("${path.module}/monitoring/kube-stack-config.yaml")
      ]
    }
  }
  tags = local.tags
}
#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "eks_data_addons" {
  #source  = "aws-ia/eks-data-addons/aws"
  source = "/Users/mselj/terraform-aws-eks-data-addons"

  #version = "~> 1.0" # ensure to update this to the latest/desired version

  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------------------------------
  # CloudNative PG Add-on
  #---------------------------------------------------------------
  enable_cnpg_operator = false
  cnpg_operator_helm_config = {
    namespace   = "cnpg-system"
    description = "CloudNativePG Operator Helm chart deployment configuration"
    set = [
      {
        name  = "resources.limits.memory"
        value = "200Mi"
      },
      {
        name  = "resources.limits.cpu"
        value = "100m"
      },
      {
        name  = "resources.requests.cpu"
        value = "100m"
      },
      {
        name  = "resources.memory.memory"
        value = "100Mi"
      }
    ]
  }
}
# resource "kubectl_manifest" "cnpg_prometheus_rule" {
#   yaml_body = file("${path.module}/monitoring/cnpg-prometheusrule.yaml")

#   depends_on = [
#     module.eks_blueprints_addons.kube_prometheus_stack
#   ]
# }

# resource "kubectl_manifest" "cnpg_grafana_cm" {
#   yaml_body = file("${path.module}/monitoring/grafana-configmap.yaml")

#   depends_on = [
#     module.eks_blueprints_addons.kube_prometheus_stack
#   ]
# }
