locals {
  name   = var.cluster_name
  region = var.region

  tags = merge(var.tags, {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  })
}

module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints-addons?ref=08650fd2b4bc894bde7b51313a8dc9598d82e925"

  cluster_name      = var.cluster_name
  cluster_endpoint  = var.cluster_endpoint
  cluster_version   = var.cluster_version
  oidc_provider     = var.oidc_provider
  oidc_provider_arn = var.oidc_provider_arn

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
  #---------------------------------------
  # Metrics Server
  #---------------------------------------
  enable_metrics_server = var.enable_metrics_server
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
  enable_cluster_autoscaler = var.enable_cluster_autoscaler
  cluster_autoscaler_helm_config = {
    name       = "cluster-autoscaler"
    repository = "https://kubernetes.github.io/autoscaler" # (Optional) Repository URL where to locate the requested chart.
    chart      = "cluster-autoscaler"
    version    = "9.21.0"
    namespace  = "kube-system"
    timeout    = "300"
    values = [templatefile("${path.module}/helm-values/cluster-autoscaler-values.yaml", {
      aws_region     = local.region,
      eks_cluster_id = local.name
    })]
  }

  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
  enable_karpenter                           = var.enable_karpenter
  karpenter_enable_spot_termination_handling = true
  karpenter_node_iam_instance_profile        = var.karpenter_iam_instance_profile_name

  karpenter_helm_config = {
    name                = "karpenter"
    chart               = "karpenter"
    repository          = "oci://public.ecr.aws/karpenter"
    version             = "v0.25.0"
    namespace           = "karpenter"
    repository_username = var.ecr_repository_username
    repository_password = var.ecr_repository_password
  }

  #---------------------------------------
  # CloudWatch metrics for EKS
  #---------------------------------------
  enable_cloudwatch_metrics = var.enable_cloudwatch_metrics

  #---------------------------------------
  # AWS for FluentBit - DaemonSet
  #---------------------------------------
  enable_aws_for_fluentbit                 = var.enable_aws_for_fluentbit
  aws_for_fluentbit_cw_log_group_name      = "/${local.name}/fluentbit-logs" # Add-on creates this log group
  aws_for_fluentbit_cw_log_group_retention = 30
  aws_for_fluentbit_helm_config = {
    name       = "aws-for-fluent-bit"
    chart      = "aws-for-fluent-bit"
    repository = "https://aws.github.io/eks-charts"
    version    = "0.1.21"
    namespace  = "aws-for-fluent-bit"
    values = [templatefile("${path.module}/helm-values/aws-for-fluentbit-values.yaml", {
      region               = local.region,
      s3_bucket_name       = module.fluentbit_s3_bucket.s3_bucket_id,
      cluster_name         = local.name,
      cloudwatch_log_group = "/${local.name}/fluentbit-logs"
    })]
  }

  #---------------------------------------
  # Amazon Managed Prometheus
  #---------------------------------------
  enable_amazon_prometheus             = var.enable_amazon_prometheus
  amazon_prometheus_workspace_endpoint = aws_prometheus_workspace.amp[0].prometheus_endpoint

  #---------------------------------------
  # Prometheus Server Add-on
  #---------------------------------------
  enable_prometheus = var.enable_prometheus
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
  enable_aws_fsx_csi_driver = var.enable_aws_fsx_csi_driver
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

  tags = local.tags
}

#---------------------------------------
# Kubecost
#---------------------------------------
resource "helm_release" "kubecost" {
  count = var.enable_kubecost ? 1 : 0

  name                = "kubecost"
  repository          = "oci://public.ecr.aws/kubecost"
  chart               = "cost-analyzer"
  version             = "1.97.0"
  namespace           = "kubecost"
  create_namespace    = true
  repository_username = var.ecr_repository_username
  repository_password = var.ecr_repository_password
  timeout             = "300"
  values              = [templatefile("${path.module}/helm-values/kubecost-values.yaml", {})]
}

#---------------------------------------------------------------
# Apache YuniKorn Add-on
#---------------------------------------------------------------
resource "helm_release" "yunikorn" {
  count = var.enable_yunikorn ? 1 : 0

  name             = "yunikorn"
  repository       = "https://apache.github.io/yunikorn-release"
  chart            = "yunikorn"
  version          = "1.1.0"
  namespace        = "yunikorn"
  create_namespace = true
  timeout          = "300"
  values = [templatefile("${path.module}/helm-values/yunikorn-values.yaml", {
    image_version = "1.1.0"
  })]
}

#---------------------------------------------------------------
# Amazon Prometheus Workspace
#---------------------------------------------------------------
resource "aws_prometheus_workspace" "amp" {
  count = var.enable_amazon_prometheus ? 1 : 0
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
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  tags = local.tags
}

#---------------------------------------------------------------
# S3 log bucket for FluentBit
#---------------------------------------------------------------
#tfsec:ignore:*
module "fluentbit_s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket_prefix = "${local.name}-emr-logs-"
  # For example only - please evaluate for your environment
  force_destroy = true
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}
