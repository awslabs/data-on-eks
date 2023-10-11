#-----------------------------------------------------------------------------------------
# JupyterHub Single User IRSA, maybe that block could be incorporated in add-on registry
#-----------------------------------------------------------------------------------------
resource "kubernetes_namespace" "jupyterhub" {
  metadata {
    name = "jupyterhub"
  }
}

module "jupyterhub_single_user_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name = "${module.eks.cluster_name}-jupyterhub-single-user-sa"

  role_policy_arns = {
    policy = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" # Policy needs to be defined based in what you need to give access to your notebook instances.
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${kubernetes_namespace.jupyterhub.metadata[0].name}:jupyterhub-single-user"]
    }
  }
}

resource "kubernetes_service_account_v1" "jupyterhub_single_user_sa" {
  metadata {
    name        = "${module.eks.cluster_name}-jupyterhub-single-user"
    namespace   = kubernetes_namespace.jupyterhub.metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.jupyterhub_single_user_irsa.iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "jupyterhub_single_user" {
  metadata {
    name      = "${module.eks.cluster_name}-jupyterhub-single-user-secret"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.jupyterhub_single_user_sa.metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace.jupyterhub.metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

#---------------------------------------------------------------
# EFS Filesystem for private volumes per user
# This will be replaced with Dynamic EFS provision using EFS CSI Driver
#---------------------------------------------------------------
resource "aws_efs_file_system" "efs" {
  creation_token = "efs-jupyter-single-user"
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
