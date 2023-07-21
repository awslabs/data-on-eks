module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints-addons?ref=08650f"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider     = module.eks.oidc_provider
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

resource "helm_release" "trino" {
  name             = local.name
  chart            = "trino"
  repository       = "https://trinodb.github.io/charts"
  version          = "0.11.0"
  namespace        = local.trino_namespace
  create_namespace = true
  description      = "Trino Helm Chart deployment"

  set {
    name  = "serviceAccount.create"
    value = true
  }

  set {
    name  = "serviceAccount.name"
    value = local.trino_sa
  }

  set {
    name = "additionalCatalogs.hive"
    value = <<EOT
      connector.name=hive
      hive.metastore=glue
      hive.metastore.glue.region=${local.region}
      hive.metastore.glue.default-warehouse-dir=s3://${module.trino_s3_bucket.s3_bucket_id}
      hive.metastore.glue.iam-role=${module.trino_s3_irsa.irsa_iam_role_arn}
      hive.s3.iam-role=${module.trino_s3_irsa.irsa_iam_role_arn}   
    EOT
    type="string"
  }
}