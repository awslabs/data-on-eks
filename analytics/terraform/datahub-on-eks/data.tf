data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

data "aws_availability_zones" "available" {}

data "aws_caller_identity" "current" {}


data "aws_eks_addon_version" "this" {
  addon_name         = "vpc-cni"
  kubernetes_version = var.eks_cluster_version
  most_recent        = true
}

data "kubernetes_ingress_v1" "datahub-datahub-frontend" {
  depends_on = [module.datahub]
  metadata {
    name      = "datahub-datahub-frontend"
    namespace = "datahub"
  }
}
