data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

# Use this data source to get the ARN of a certificate in AWS Certificate Manager (ACM)
data "aws_acm_certificate" "issued" {
  domain   = var.acm_certificate_domain
  statuses = ["ISSUED"]
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

locals {
  cognito_custom_domain = var.cognito_custom_domain
}
#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.20"
  role_name_prefix      = format("%s-%s", local.name, "ebs-csi-driver-")
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  tags = local.tags
}

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.2"

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
  # Kubernetes Add-ons
  #---------------------------------------
  #---------------------------------------------------------------
  # CoreDNS Autoscaler helps to scale for large EKS Clusters
  #   Further tuning for CoreDNS is to leverage NodeLocal DNSCache -> https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/
  #---------------------------------------------------------------
  enable_cluster_proportional_autoscaler = true
  cluster_proportional_autoscaler = {
    timeout = "300"
    values = [templatefile("${path.module}/helm-values/coredns-autoscaler-values.yaml", {
      target = "deployment/coredns"
    })]
    description = "Cluster Proportional Autoscaler for CoreDNS Service"
  }

  #---------------------------------------
  # Metrics Server
  #---------------------------------------
  enable_metrics_server = true
  metrics_server = {
    timeout = "300"
    values  = [templatefile("${path.module}/helm-values/metrics-server-values.yaml", {})]
  }

  #---------------------------------------
  # Cluster Autoscaler
  #---------------------------------------
  enable_cluster_autoscaler = true
  cluster_autoscaler = {
    timeout     = "300"
    create_role = true
    values = [templatefile("${path.module}/helm-values/cluster-autoscaler-values.yaml", {
      aws_region     = var.region,
      eks_cluster_id = module.eks.cluster_name
    })]
  }

  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
  enable_karpenter                  = true
  karpenter_enable_spot_termination = true
  karpenter = {
    timeout             = "300"
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

  #---------------------------------------
  # CloudWatch metrics for EKS
  #---------------------------------------
  enable_aws_cloudwatch_metrics = true
  aws_cloudwatch_metrics = {
    timeout = "300"
    values  = [templatefile("${path.module}/helm-values/aws-cloudwatch-metrics-values.yaml", {})]
  }

  enable_aws_load_balancer_controller = true

  tags = local.tags
}

#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "eks_data_addons" {
  source  = "aws-ia/eks-data-addons/aws"
  version = "~> 1.0" # ensure to update this to the latest/desired version

  oidc_provider_arn = module.eks.oidc_provider_arn
  #---------------------------------------------------------------
  # JupyterHub Add-on
  #---------------------------------------------------------------
  enable_jupyterhub = true
  jupyterhub_helm_config = {
    values = [templatefile("${path.module}/helm-values/jupyterhub-values.yaml", {
      ssl_cert_arn  = data.aws_acm_certificate.issued.arn
      jupyterdomain = "https://${var.jupyterhub_domain}/hub/oauth_callback"
      authorize_url = "https://${local.cognito_custom_domain}.auth.${local.region}.amazoncognito.com/oauth2/authorize"
      token_url     = "https://${local.cognito_custom_domain}.auth.${local.region}.amazoncognito.com/oauth2/token"
      userdata_url  = "https://${local.cognito_custom_domain}.auth.${local.region}.amazoncognito.com/oauth2/userInfo"
      client_id     = aws_cognito_user_pool_client.user_pool_client.id
      client_secret = aws_cognito_user_pool_client.user_pool_client.client_secret
    })]
  }
}


resource "kubectl_manifest" "storage_class_gp2" {
  force_new = true
  yaml_body = <<YAML
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp2
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: kubernetes.io/aws-ebs
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
parameters:
  type: gp2
  fsType: ext4
YAML

  depends_on = [module.eks_blueprints_addons]
}

resource "kubectl_manifest" "storage_class_gp3" {
  yaml_body = <<YAML
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  csi.storage.k8s.io/fstype: ext4
  encrypted: "true"
YAML

  depends_on = [module.eks_blueprints_addons]
}
#---------------------------------------------------------------
# EFS Filesystem for private volumes per user
# This will be repalced with Dynamic EFS provision using EFS CSI Driver
#---------------------------------------------------------------
resource "aws_efs_file_system" "efs" {
  creation_token = "efs"
  encrypted      = true

  tags = local.tags
}

resource "aws_efs_mount_target" "efs_mt" {
  count = length(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) : substr(cidr_block, 0, 4) == "100." ? subnet_id : null]))

  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = element(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) : substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), count.index)
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
  yaml_body = <<YAML
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-persist
  namespace: jupyterhub
spec:
  capacity:
    storage: 123Gi
  accessModes:
    - ReadWriteMany
  nfs:
    server: ${aws_efs_file_system.efs.dns_name}
    path: "/"
YAML

  depends_on = [module.eks_blueprints_addons]
}

resource "kubectl_manifest" "pvc" {
  yaml_body = <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: efs-persist
  namespace: jupyterhub
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 1Gi
YAML

  depends_on = [module.eks_blueprints_addons]
}

resource "kubectl_manifest" "pv_shared" {
  yaml_body = <<YAML
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-persist-shared
  namespace: jupyterhub
spec:
  capacity:
    storage: 123Gi
  accessModes:
    - ReadWriteMany
  nfs:
    server: ${aws_efs_file_system.efs.dns_name}
    path: "/"
YAML

  depends_on = [module.eks_blueprints_addons]
}

resource "kubectl_manifest" "pvc_shared" {
  yaml_body = <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: efs-persist-shared
  namespace: jupyterhub
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 1Gi
YAML

  depends_on = [module.eks_blueprints_addons]
}

#---------------------------------------------------------------
# Cognito pool, domain and client creation.
# This can be used
# Auth integration later.
# ---------------------------------------------------------------
resource "aws_cognito_user_pool" "pool" {
  name = "jupyterhub-userpool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
  }
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain       = local.cognito_custom_domain
  user_pool_id = aws_cognito_user_pool.pool.id
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                                 = "jupyter-client"
  callback_urls                        = ["https://${var.jupyterhub_domain}/hub/oauth_callback"]
  user_pool_id                         = aws_cognito_user_pool.pool.id
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email"]
  generate_secret                      = true
  supported_identity_providers = [
    "COGNITO"
  ]

  depends_on = [aws_cognito_user_pool_domain.domain]
}
