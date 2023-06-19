module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints-addons?ref=90a70ba"

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
      preserve                 = true
      most_recent              = true
    }
    coredns = {
      most_recent = true
      preserve    = true
    }
    kube-proxy = {
      most_recent = true
      preserve    = true
    }
  }
  
  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
  enable_karpenter                  = true
  karpenter_enable_spot_termination = true
  karpenter_node = {
    create_iam_role          = true
    iam_role_use_name_prefix = false
    # We are defining role name so that we can add this to aws-auth during EKS Cluster creation
    iam_role_name = local.karpenter_iam_role_name
  }

  karpenter = {
    timeout             = "300"
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

}

#---------------------------------------------------------------
# IRSA for EBS
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.14"
  role_name             = format("%s-%s", local.name, "ebs-csi-driver")
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  tags = local.tags
}

#---------------------------------------------------------------
# IRSA for VPC CNI
#---------------------------------------------------------------
module "vpc_cni_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.14"
  role_name             = format("%s-%s", local.name, "vpc-cni")
  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }
  tags = local.tags
}
#---------------------------------------------------------------
# VPC CNI Addon should run before the nodes are created
# Ideally VPC CNI with custom configuration values should be deployed before the nodes are created to use the correct VPC CNI config
#---------------------------------------------------------------
resource "aws_eks_addon" "vpc_cni" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "vpc-cni"
  addon_version            = data.aws_eks_addon_version.this.version
  resolve_conflicts        = "OVERWRITE"
  preserve                 = true # Ensure VPC CNI is not deleted before the add-ons and nodes are deleted during the cleanup/destroy.
  service_account_role_arn = module.vpc_cni_irsa.iam_role_arn
}

#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
# NOTE: This module will be moved to a dedicated repo and the source will be changed accordingly.
module "kubernetes_data_addons" {
  # Please note that local source will be replaced once the below repo is public
  # source = "https://github.com/aws-ia/terraform-aws-kubernetes-data-addons"
  source            = "../../workshop/modules/terraform-aws-eks-data-addons"
  oidc_provider_arn = module.eks.oidc_provider_arn
  #---------------------------------------------------------------
  # JupyterHub Add-on
  #---------------------------------------------------------------
  jupyterhub_helm_config = {
    values = [templatefile("${path.module}/helm-values/jupyter-values.yaml", {
         ssl_cert_arn   = data.aws_acm_certificate.issued.arn
         jupyterdomain  = "https://${var.acm_certificate_domain}/hub/oauth_callback"
         authorize_url  = "https://${local.cog_domain_name}.auth.${local.region}.amazoncognito.com/oauth2/authorize"
         token_url      = "https://${local.cog_domain_name}.auth.${local.region}.amazoncognito.com/oauth2/token"
         userdata_url   = "https://${local.cog_domain_name}.auth.${local.region}.amazoncognito.com/oauth2/userInfo"
         client_id      =  aws_cognito_user_pool_client.user_pool_client.id
         client_secret  =  aws_cognito_user_pool_client.user_pool_client.client_secret
      })]
    }
  }
  #---------------------------------------------------------------
# EFS Filesystem for private volumes per user
#---------------------------------------------------------------
resource "aws_efs_file_system" "efs" {
  creation_token = "efs"
  encrypted      = true
  
  tags = local.tags
}

resource "aws_efs_mount_target" "efs_mt" {
  count = length(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) : substr(cidr_block, 0, 4) == "100." ? subnet_id : null]))
  
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = "${element(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) : substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), count.index)}"
  security_groups = [aws_security_group.efs.id]
}

resource "aws_security_group" "efs" {
  name        = "${local.name}-efs"
  description = "Allow inbound NFS traffic from private subnets of the VPC"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow NFS 2049/tcp"
    cidr_blocks = module.vpc.vpc_secondary_cidr_blocks
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
  }

  tags = local.tags
}
resource "kubectl_manifest" "pv" {
  yaml_body = templatefile("${path.module}/manifests/pv.yaml", {
   efs_id = aws_efs_file_system.efs.id
   region = local.region
   namespace = local.name
    })
    depends_on = [module.kubernetes_data_addons]
  }
resource "kubectl_manifest" "pvc" {
  yaml_body = templatefile("${path.module}/manifests/pvc.yaml", {
  namespace = local.name  
  })
    depends_on = [module.kubernetes_data_addons]
  }
#---------------------------------------------------------------
# EFS Filesystem for shared volume
#---------------------------------------------------------------
resource "aws_efs_file_system" "efs_shared" {
  creation_token = "efs_shared"
  encrypted      = true
  
  tags = local.tags
}
resource "aws_efs_mount_target" "efs_mt_shared" {
  count = length(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) : substr(cidr_block, 0, 4) == "100." ? subnet_id : null]))
   

  file_system_id  = aws_efs_file_system.efs_shared.id
  subnet_id       = "${element(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) : substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), count.index)}"
  security_groups = [aws_security_group.efs_shared.id]
}
resource "aws_security_group" "efs_shared" {
  name        = "${local.name}-efs_shared"
  description = "Allow inbound NFS traffic from private subnets of the VPC"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow NFS 2049/tcp"
    cidr_blocks = module.vpc.vpc_secondary_cidr_blocks
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
  }

  tags = local.tags
}
resource "kubectl_manifest" "pv_shared" {
  yaml_body = templatefile("${path.module}/manifests/pv_shared.yaml", {
  efs_shared_id = aws_efs_file_system.efs_shared.id
  region = local.region
  namespace = local.name
    })
  depends_on = [module.kubernetes_data_addons]
}

resource "kubectl_manifest" "pvc_shared" {
  yaml_body = templatefile("${path.module}/manifests/pvc_shared.yaml", {
  namespace = local.name
    })
  depends_on = [module.kubernetes_data_addons]
}
#---------------------------------------------------------------
# Cognito pool, domain and client creation. 
# This can be used 
# Auth integration later.
#---------------------------------------------------------------

resource "aws_cognito_user_pool" "pool" {
  name                       = "userpool"
  
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]
  
  password_policy {
    minimum_length    = 6
  }
}
resource "aws_cognito_user_pool_domain" "domain" {
  domain       = local.cog_domain_name
  user_pool_id = aws_cognito_user_pool.pool.id
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name = "jupyter-client"
  callback_urls                        = ["https://${var.acm_certificate_domain}/hub/oauth_callback"]
  user_pool_id                         = aws_cognito_user_pool.pool.id
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid","email"]
  generate_secret                      = true
  supported_identity_providers = [
    "COGNITO"
  ]
}