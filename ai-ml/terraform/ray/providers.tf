provider "aws" {
  region = local.region
}

provider "kubernetes" {
  host                   = module.eks_blueprints.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks_blueprints.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "grafana" {
  url  = var.eks_cluster_domain == null ? data.kubernetes_ingress_v1.ingress.status[0].load_balancer[0].ingress[0].hostname : "https://ray-demo.${var.eks_cluster_domain}/monitoring"
  auth = "admin:${aws_secretsmanager_secret_version.grafana.secret_string}"
}
