module "eks_blueprints_kubernetes_addons" {
  source = "aws-ia/eks-blueprints-addons/aws"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
  eks_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    coredns = {
      preserve = true
    }
    vpc-cni = {
      preserve = true
    }
    kube-proxy = {
      preserve = true
    }
  }

  #---------------------------------------
  # Karpenter Add-ons
  #---------------------------------------
  # enable_karpenter                  = true
  # karpenter_enable_spot_termination = true
  # karpenter = {
  #   repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  #   repository_password = data.aws_ecrpublic_authorization_token.token.password
  # }
  
  tags = local.tags
}

#---------------------------------------
# Karpenter Provisioners
#---------------------------------------
# data "kubectl_path_documents" "karpenter_provisioners" {
#   pattern = "${path.module}/karpenter-provisioners/provisioner.yaml"
#   vars = {
#     azs            = local.region
#     eks_cluster_id = module.eks.cluster_name
#   }
# }

# resource "kubectl_manifest" "karpenter_provisioner" {
#   for_each  = toset(data.kubectl_path_documents.karpenter_provisioners.documents)
#   yaml_body = each.value

#   depends_on = [module.eks_blueprints_kubernetes_addons]
# }

#---------------------------------------
# Trino Helm Add-on
#---------------------------------------
# resource "helm_release" "trino" {
#   name             = local.name
#   chart            = "trino"
#   repository       = "https://trinodb.github.io/charts"
#   version          = "0.11.0"
#   namespace        = local.trino_namespace
#   create_namespace = true
#   description      = "Trino Helm Chart deployment"

#   values = [
#     templatefile("${path.module}/trino.yaml", 
#     {
#       sa        = local.trino_sa
#       region    = local.region
#       bucket_id = module.trino_s3_bucket.s3_bucket_id
#       irsa_arn  = module.trino_s3_irsa.irsa_iam_role_arn
#     })
#   ]

#   depends_on=[module.trino_s3_irsa]
# }