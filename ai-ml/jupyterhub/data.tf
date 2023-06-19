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
    namespace = var.name
  }
  depends_on = [module.kubernetes_data_addons]
}
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}
data "aws_caller_identity" "current" {}
data "aws_eks_addon_version" "this" {
  addon_name         = "vpc-cni"
  kubernetes_version = var.eks_cluster_version
  most_recent        = true
}
# This data source can be used to get the latest AMI for Managed Node Groups 
data "aws_ami" "x86" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["amazon-eks-node-${module.eks.cluster_version}-*"] # Update this for ARM ["amazon-eks-arm64-node-${module.eks.cluster_version}-*"]
  }
}
