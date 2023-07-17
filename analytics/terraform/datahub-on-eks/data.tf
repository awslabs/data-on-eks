data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_availability_zones" "available" {}

data "kubernetes_ingress_v1" "datahub_datahub_frontend" {
  depends_on = [module.datahub]
  metadata {
    name      = "datahub-datahub-frontend"
    namespace = "datahub"
  }
}
