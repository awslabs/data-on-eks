module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.25.0"

  eks_cluster_id       = module.eks.cluster_name
  eks_cluster_endpoint = module.eks.cluster_endpoint
  eks_oidc_provider    = module.eks.oidc_provider
  eks_cluster_version  = module.eks.cluster_version
  

  # Wait on the node group(s) before provisioning addons
  data_plane_wait_arn = join(",", [for group in module.eks.eks_managed_node_groups : group.node_group_arn])

  #---------------------------------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------------------------------
  enable_amazon_eks_vpc_cni            = true
  enable_amazon_eks_coredns            = true
  enable_amazon_eks_kube_proxy         = true
  enable_amazon_eks_aws_ebs_csi_driver = true
  
 }
 
 resource "helm_release" "jupyterhub" {
  name             = "jupyterhub"
  repository       = "https://jupyterhub.github.io/helm-chart/"
  chart            = "jupyterhub"
  version          = "2.0.0"
  namespace        = "k8-jupyterhub"
  create_namespace = true
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
  



#---------------------------------------------------------------
# EFS Filesystem for JupyterHub
#---------------------------------------------------------------
resource "aws_efs_file_system" "efs" {
  creation_token = "efs"
  encrypted      = true
  
  tags = local.tags
}

resource "aws_efs_mount_target" "efs_mt" {
  count = length(module.vpc.private_subnets)

  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.efs.id]
}

resource "aws_security_group" "efs" {
  name        = "${local.name}-efs"
  description = "Allow inbound NFS traffic from private subnets of the VPC"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow NFS 2049/tcp"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
  }

  tags = local.tags
}


resource "kubectl_manifest" "pv" {
  yaml_body = templatefile("${path.module}/manifests/pv.yaml", {
   efs_id = aws_efs_file_system.efs.id
    })
  }

resource "kubectl_manifest" "pvc" {
  yaml_body = templatefile("${path.module}/manifests/pvc.yaml", {
    })
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


