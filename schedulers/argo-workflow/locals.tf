#-------------------------------------------------
# Argo Workflows Helm Add-on
#-------------------------------------------------
locals {

  default_helm_config = {
    name             = "argo-workflows"
    chart            = "argo-workflows"
    repository       = "https://argoproj.github.io/argo-helm"
    version          = "v0.20.1"
    namespace        = "argo-workflows"
    create_namespace = true
    description      = "Argo workflows Helm chart deployment configuration"
  }



  irsa_config = {
    kubernetes_namespace              = local.default_helm_config["namespace"]
    kubernetes_service_account        = local.name
    create_kubernetes_namespace       = try(local.default_helm_config["create_namespace"], true)
    create_kubernetes_service_account = false
    irsa_iam_policies                 = []
  }

  eks_oidc_issuer_url = replace(data.aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer, "https://", "")
}

#-------------------------------------------------
# EKS cluster 
#-------------------------------------------------
locals {
  name          = var.name
  region        = var.region
  azs           = slice(data.aws_availability_zones.available.names, 0, 3)
  vpc_endpoints = ["autoscaling", "ecr.api", "ecr.dkr", "ec2", "ec2messages", "elasticloadbalancing", "sts", "kms", "logs", "ssm", "ssmmessages"]

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}