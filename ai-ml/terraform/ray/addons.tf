#---------------------------------------------------------------
# EKS Blueprints AddOns
#---------------------------------------------------------------
module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.15.0"

  eks_cluster_id       = module.eks_blueprints.eks_cluster_id
  eks_cluster_endpoint = module.eks_blueprints.eks_cluster_endpoint
  eks_oidc_provider    = module.eks_blueprints.oidc_provider
  eks_cluster_version  = module.eks_blueprints.eks_cluster_version
  eks_cluster_domain   = var.eks_cluster_domain

  # Add-Ons
  enable_kuberay_operator             = true
  enable_ingress_nginx                = true
  enable_aws_load_balancer_controller = true
  enable_external_dns                 = var.eks_cluster_domain == "" ? false : true
  enable_kube_prometheus_stack        = true

  # Add-on customizations
  ingress_nginx_helm_config = {
    values = [templatefile("${path.module}/helm-values/nginx-values.yaml", {
      hostname     = var.eks_cluster_domain
      ssl_cert_arn = var.acm_certificate_domain == null ? null : data.aws_acm_certificate.issued[0].arn
    })]
  }
  kube_prometheus_stack_helm_config = {
    values = [templatefile("${path.module}/helm-values/kube-stack-prometheus-values.yaml", {
      hostname = var.eks_cluster_domain
    })]
    set_sensitive = [
      {
        name  = "grafana.adminPassword"
        value = aws_secretsmanager_secret_version.grafana.secret_string
      }
    ]
  }

  tags = local.tags
}
