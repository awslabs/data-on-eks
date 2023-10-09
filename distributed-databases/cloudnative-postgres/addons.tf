#---------------------------------------------------------------
# GP3 Encrypted Storage Class
#---------------------------------------------------------------
resource "kubernetes_annotations" "gp2_default" {
  annotations = {
    "storageclass.kubernetes.io/is-default-class" : "false"
  }
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }
  force = true

  depends_on = [module.eks]
}

resource "kubernetes_storage_class" "ebs_csi_encrypted_gp3_storage_class" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" : "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = {
    fsType    = "xfs"
    encrypted = true
    type      = "gp3"
  }

  depends_on = [kubernetes_annotations.gp2_default]
}

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0" #ensure to update this to the latest/desired version

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

  enable_kube_prometheus_stack = true
  kube_prometheus_stack = {
    namespace     = "monitoring"
    name          = "prometheus"
    chart_version = "48.1.1"
    set_sensitive = [
      {
        name  = "grafana.adminPassword"
        value = data.aws_secretsmanager_secret_version.admin_password_version.secret_string
    }]

    values = [
      templatefile("${path.module}/monitoring/kube-stack-config.yaml", {
        storage_class_type = kubernetes_storage_class.ebs_csi_encrypted_gp3_storage_class.id,
      })
    ]
  }
  tags = local.tags
}


#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "eks_data_addons" {
  source  = "aws-ia/eks-data-addons/aws"
  version = "~> 1.2.0"

  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------------------------------
  # CloudNative PG Add-on
  #---------------------------------------------------------------
  enable_cnpg_operator = true
  cnpg_operator_helm_config = {
    namespace   = "cnpg-system"
    description = "CloudNativePG Operator Helm chart deployment configuration"
    set = [
      {
        name  = "resources.limits.memory"
        value = "200Mi"
      },
      {
        name  = "resources.limits.cpu"
        value = "100m"
      },
      {
        name  = "resources.requests.cpu"
        value = "100m"
      },
      {
        name  = "resources.memory.memory"
        value = "100Mi"
      }
    ]
  }
}
resource "kubectl_manifest" "cnpg_prometheus_rule" {
  yaml_body = file("${path.module}/monitoring/cnpg-prometheusrule.yaml")

  depends_on = [
    module.eks_blueprints_addons.kube_prometheus_stack
  ]
}

resource "kubectl_manifest" "cnpg_grafana_cm" {
  yaml_body = file("${path.module}/monitoring/grafana-configmap.yaml")

  depends_on = [
    module.eks_blueprints_addons.kube_prometheus_stack
  ]
}
