module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints-addons?ref=ed27abc"

  eks_cluster_id       = module.eks.cluster_name
  eks_cluster_endpoint = module.eks.cluster_endpoint
  eks_oidc_provider    = module.eks.oidc_provider
  eks_cluster_version  = module.eks.cluster_version

  # EKS Managed Add-ons
  enable_amazon_eks_vpc_cni            = true
  enable_amazon_eks_coredns            = true
  enable_amazon_eks_kube_proxy         = true
  enable_amazon_eks_aws_ebs_csi_driver = true
  enable_kube_prometheus_stack         = true
  kube_prometheus_stack_helm_config = {
    name      = "kube-prometheus-stack"
    chart     = "kube-prometheus-stack"
    namespace = "monitoring"
    values = [
      file("${path.module}/monitoring/kube-stack-config.yaml")
    ]
    description = "kube-prometheus-stack helm Chart deployment configuration"
    repository  = "https://prometheus-community.github.io/helm-charts"
    version     = "45.6.0"
  }


  tags = local.tags
}

resource "kubectl_manifest" "cnpg_prometheus_rule" {
  yaml_body = file("${path.module}/monitoring/cnpg-prometheusrule.yaml")

  depends_on = [
    module.eks_blueprints_kubernetes_addons.kube_prometheus_stack
  ]
}

resource "helm_release" "cloudnative_pg" {
  name             = local.name
  chart            = "cloudnative-pg"
  repository       = "https://cloudnative-pg.github.io/charts"
  version          = "0.17.0"
  namespace        = "${local.name}-system"
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
