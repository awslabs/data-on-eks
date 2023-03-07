module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.25.0"

  eks_cluster_id       = module.eks_blueprints.eks_cluster_id
  eks_cluster_endpoint = module.eks_blueprints.eks_cluster_endpoint
  eks_oidc_provider    = module.eks_blueprints.oidc_provider
  eks_cluster_version  = module.eks_blueprints.eks_cluster_version

  # EKS Managed Add-ons
  enable_amazon_eks_vpc_cni            = true
  enable_amazon_eks_coredns            = true
  enable_amazon_eks_kube_proxy         = true
  enable_amazon_eks_aws_ebs_csi_driver = true
  enable_kube_prometheus_stack         = true
  kube_prometheus_stack_helm_config = {
      name       = "kube-prometheus-stack"
      chart      = "kube-prometheus-stack"
      namespace  = "monitoring"
      values =  [
        file("${path.module}/monitoring/kube-stack-config.yaml")
        ]
      description = "kube-prometheus-stack helm Chart deployment configuration"
      repository = "https://prometheus-community.github.io/helm-charts"
      version    = "45.6.0"
    }
    
  
  tags = local.tags
}

resource "kubectl_manifest" "cnpg_prometheusrule" {
  yaml_body = file("${path.module}/monitoring/cnpg-prometheusrule.yaml")

  depends_on = [
    module.eks_blueprints.kube_prometheus_stack
  ]
}
