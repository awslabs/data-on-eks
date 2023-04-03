module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints-addons?ref=08650f"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider     = module.eks.oidc_provider
  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
  eks_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
      preserve                 = true
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
  enable_kube_prometheus_stack = true
  kube_prometheus_stack_helm_config = {
    namespace = "monitoring"
    values = [
      file("${path.module}/monitoring/kube-stack-config.yaml")
    ]
  }
  tags = local.tags
}

resource "kubectl_manifest" "cnpg_prometheus_rule" {
  yaml_body = file("${path.module}/monitoring/cnpg-prometheusrule.yaml")

  depends_on = [
    module.eks_blueprints_kubernetes_addons.kube_prometheus_stack
  ]
}

resource "kubectl_manifest" "cnpg_grafana_cm" {
  yaml_body = file("${path.module}/monitoring/grafana-configmap.yaml")

  depends_on = [
    module.eks_blueprints_kubernetes_addons.kube_prometheus_stack
  ]
}

resource "helm_release" "cloudnative_pg" {
  name             = local.name
  chart            = "cloudnative-pg"
  repository       = "https://cloudnative-pg.github.io/charts"
  version          = "0.17.0"
  namespace        = "cnpg-system"
  create_namespace = true
  description      = "CloudNativePG Operator Helm chart deployment configuration"

  set {
    name  = "resources.limits.cpu"
    value = "100m"
  }

  set {
    name  = "resources.limits.memory"
    value = "200Mi"
  }

  set {
    name  = "resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resources.memory.memory"
    value = "100Mi"
  }

}
