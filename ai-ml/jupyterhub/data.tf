data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_availability_zones" "available" {}

data "aws_acm_certificate" "issued" {
  domain   = var.acm_certificate_domain
  statuses = ["ISSUED"]
}

data "kubernetes_service" "elb" {
  metadata {
    name = "proxy-public"
    namespace = "k8-jupyterhub"
  }
  depends_on = [helm_release.jupyterhub]
}
