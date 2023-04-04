
module "eks_blueprints_kubernetes_addons" {
  # Users should pin the version to the latest available release
  # tflint-ignore: terraform_module_pinned_source
  source = "github.com/aws-ia/terraform-aws-eks-blueprints-addons?ref=08650fd2b4bc894bde7b51313a8dc9598d82e925"

  cluster_name      = data.aws_eks_cluster.cluster.name
  cluster_endpoint  = data.aws_eks_cluster.cluster.endpoint
  cluster_version   = data.aws_eks_cluster.cluster.version
  oidc_provider     = replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")
  oidc_provider_arn = data.aws_iam_openid_connect_provider.eks_oidc.arn

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
      service_account_role_arn = module.vpc_cni_irsa.iam_role_arn
      preserve                 = true
    }
    kube-proxy = {
      preserve = true
    }
  }
  #---------------------------------------
  # Kubernetes Add-ons
  #---------------------------------------
  #---------------------------------------
  # Metrics Server
  #---------------------------------------
  enable_metrics_server = true
  metrics_server_helm_config = {
    name       = "metrics-server"
    repository = "https://kubernetes-sigs.github.io/metrics-server/" # (Optional) Repository URL where to locate the requested chart.
    chart      = "metrics-server"
    version    = "3.8.2"
    namespace  = "kube-system"
    timeout    = "300"
    values     = [templatefile("${path.module}/helm-values/metrics-server-values.yaml", {})]
  }

  #---------------------------------------
  # Cluster Autoscaler
  #---------------------------------------
  enable_cluster_autoscaler = true
  cluster_autoscaler_helm_config = {
    name       = "cluster-autoscaler"
    repository = "https://kubernetes.github.io/autoscaler" # (Optional) Repository URL where to locate the requested chart.
    chart      = "cluster-autoscaler"
    version    = "9.21.0"
    namespace  = "kube-system"
    timeout    = "300"
    values = [templatefile("${path.module}/helm-values/cluster-autoscaler-values.yaml", {
      aws_region     = var.region,
      eks_cluster_id = local.name
    })]
  }

  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
  enable_karpenter                           = true
  karpenter_enable_spot_termination_handling = true
  karpenter_node_iam_instance_profile        = module.karpenter.instance_profile_name

  karpenter_helm_config = {
    name                = "karpenter"
    chart               = "karpenter"
    repository          = "oci://public.ecr.aws/karpenter"
    version             = "v0.25.0"
    namespace           = "karpenter"
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

  #---------------------------------------
  # CloudWatch metrics for EKS
  #---------------------------------------
  enable_cloudwatch_metrics = var.enable_cloudwatch_metrics

  #---------------------------------------
  # AWS for FluentBit - DaemonSet
  #---------------------------------------
  enable_aws_for_fluentbit                 = var.enable_aws_for_fluentbit
  aws_for_fluentbit_cw_log_group_name      = "/${var.name}/fluentbit-logs" # Add-on creates this log group
  aws_for_fluentbit_cw_log_group_retention = 30
  aws_for_fluentbit_helm_config = {
    name       = "aws-for-fluent-bit"
    chart      = "aws-for-fluent-bit"
    repository = "https://aws.github.io/eks-charts"
    version    = "0.1.21"
    namespace  = "aws-for-fluent-bit"
    values = [templatefile("${path.module}/helm-values/aws-for-fluentbit-values.yaml", {
      region               = var.region,
      cloudwatch_log_group = "/${var.name}/fluentbit-logs"
    })]
  }

  #---------------------------------------
  # Amazon Managed Prometheus
  #---------------------------------------
  enable_amazon_prometheus             = true
  amazon_prometheus_workspace_endpoint = aws_prometheus_workspace.amp.prometheus_endpoint

  #---------------------------------------
  # Prometheus Server Add-on
  #---------------------------------------
  enable_prometheus = true
  prometheus_helm_config = {
    name       = "prometheus"
    repository = "https://prometheus-community.github.io/helm-charts"
    chart      = "prometheus"
    version    = "15.10.1"
    namespace  = "prometheus"
    timeout    = "300"
    values     = [templatefile("${path.module}/helm-values/prometheus-values.yaml", {})]
  }

  #---------------------------------------
  # Enable FSx for Lustre CSI Driver
  #---------------------------------------
  enable_aws_fsx_csi_driver = var.enable_fsx_for_lustre
  aws_fsx_csi_driver_helm_config = {
    name       = "aws-fsx-csi-driver"
    chart      = "aws-fsx-csi-driver"
    repository = "https://kubernetes-sigs.github.io/aws-fsx-csi-driver/"
    version    = "1.5.1"
    namespace  = "kube-system"
    # INFO: fsx node daemonset wont be placed on Karpenter nodes with taints without the following toleration
    values = [
      <<-EOT
        node:
          tolerations:
            - operator: Exists
      EOT
    ]
  }

  enable_grafana = var.enable_grafana

  # This example shows how to set default password for grafana using SecretsManager and Helm Chart set_sensitive values.
  grafana_helm_config = {
    set_sensitive = [
      {
        name  = "adminPassword"
        value = data.aws_secretsmanager_secret_version.admin_password_version.secret_string
      }
    ]
  }

  tags = local.tags
}

# ---------------------------------------
# Kubecost
# ---------------------------------------
resource "helm_release" "kubecost" {
  name                = "kubecost"
  repository          = "oci://public.ecr.aws/kubecost"
  chart               = "cost-analyzer"
  version             = "1.97.0"
  namespace           = "kubecost"
  create_namespace    = true
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  timeout             = "300"
  values              = [templatefile("${path.module}/helm-values/kubecost-values.yaml", {})]
}

#---------------------------------------------------------------
# Apache YuniKorn Add-on
#---------------------------------------------------------------
# resource "helm_release" "yunikorn" {
#   count = var.enable_yunikorn ? 1 : 0

#   name             = "yunikorn"
#   repository       = "https://apache.github.io/yunikorn-release"
#   chart            = "yunikorn"
#   version          = "1.1.0"
#   namespace        = "yunikorn"
#   create_namespace = true
#   timeout          = "300"
#   values = [templatefile("${path.module}/helm-values/yunikorn-values.yaml", {
#     image_version = "1.1.0"
#   })]
# }

#---------------------------------------
# Karpenter Provisioners
#---------------------------------------
data "kubectl_path_documents" "karpenter_provisioners" {
  pattern = "${path.module}/karpenter-provisioners/spark-*.yaml"
  vars = {
    azs            = local.region
    eks_cluster_id = data.aws_eks_cluster.cluster.name
  }
}

resource "kubectl_manifest" "karpenter_provisioner" {
  for_each  = toset(data.kubectl_path_documents.karpenter_provisioners.documents)
  yaml_body = each.value

  depends_on = [module.eks_blueprints_kubernetes_addons]
}

#---------------------------------------------------------------
# Amazon Prometheus Workspace
#---------------------------------------------------------------
resource "aws_prometheus_workspace" "amp" {
  alias = format("%s-%s", "amp-ws", local.name)
  tags  = local.tags
}

#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.14"
  role_name             = format("%s-%s", local.name, "ebs-csi-driver")
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = data.aws_iam_openid_connect_provider.eks_oidc.arn
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
      provider_arn               = data.aws_iam_openid_connect_provider.eks_oidc.arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }
  tags = local.tags
}

#---------------------------------------------------------------
# Grafana Admin credentials resources
# Login to AWS secrets manager with the same role as Terraform to extract the Grafana admin password with the secret name as "grafana"
#---------------------------------------------------------------
resource "random_password" "grafana" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}
#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "grafana" {
  name                    = "workshop-grafana"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id     = aws_secretsmanager_secret.grafana.id
  secret_string = random_password.grafana.result
}
