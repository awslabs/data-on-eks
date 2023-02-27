locals {
  karpenter_helm_chart_version     = "v0.25.0"
  karpenter_namespace              = "karpenter"
  core_node_group_instance_profile = compact(flatten([for group in module.eks.eks_managed_node_groups : group.iam_role_name]))
}

module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.25.0"

  # Wait on the node group(s) before provisioning addons
  data_plane_wait_arn = join(",", [for group in module.eks.eks_managed_node_groups : group.node_group_arn])

  eks_cluster_id        = module.eks.cluster_name
  eks_cluster_endpoint  = module.eks.cluster_endpoint
  eks_oidc_provider     = module.eks.oidc_provider
  eks_oidc_provider_arn = module.eks.oidc_provider_arn
  eks_cluster_version   = module.eks.cluster_version

  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
  enable_amazon_eks_vpc_cni            = true
  enable_amazon_eks_coredns            = true
  enable_amazon_eks_kube_proxy         = true
  enable_amazon_eks_aws_ebs_csi_driver = true

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
    values = [templatefile("${path.module}/helm-values/metrics-server-values.yaml", {
      operating_system = "linux"
    })]
  }

  #---------------------------------------
  # Cluster Autoscaler
  #---------------------------------------
  enable_cluster_autoscaler = true
  cluster_autoscaler_helm_config = {
    name       = "cluster-autoscaler"
    repository = "https://kubernetes.github.io/autoscaler" # (Optional) Repository URL where to locate the requested chart.
    chart      = "cluster-autoscaler"
    version    = "9.15.0"
    namespace  = "kube-system"
    timeout    = "300"
    values = [templatefile("${path.module}/helm-values/cluster-autoscaler-values.yaml", {
      aws_region       = var.region,
      eks_cluster_id   = local.name,
      operating_system = "linux"
    })]
  }

  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
  enable_karpenter = true
  karpenter_helm_config = {
    name                = "karpenter"
    chart               = "karpenter"
    repository          = "oci://public.ecr.aws/karpenter"
    version             = local.karpenter_helm_chart_version
    namespace           = local.karpenter_namespace
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
    values = [
      <<-EOT
          settings:
            aws:
              clusterName: ${module.eks.cluster_name}
              clusterEndpoint: ${module.eks.cluster_endpoint}
              defaultInstanceProfile: ${module.karpenter.instance_profile_name}
              interruptionQueueName: ${module.karpenter.queue_name}
        EOT
    ]
  }

  #---------------------------------------
  # CloudWatch metrics for EKS
  #---------------------------------------
  enable_aws_cloudwatch_metrics = true
  aws_cloudwatch_metrics_helm_config = {
    name       = "aws-cloudwatch-metrics"
    chart      = "aws-cloudwatch-metrics"
    repository = "https://aws.github.io/eks-charts"
    version    = "0.0.7"
    namespace  = "amazon-cloudwatch"
    values = [templatefile("${path.module}/helm-values/aws-cloudwatch-metrics-valyes.yaml", {
      eks_cluster_id = var.name
    })]
  }

  #---------------------------------------
  # AWS for FluentBit - DaemonSet
  #---------------------------------------
  enable_aws_for_fluentbit = true
  aws_for_fluentbit_helm_config = {
    name                                      = "aws-for-fluent-bit"
    chart                                     = "aws-for-fluent-bit"
    repository                                = "https://aws.github.io/eks-charts"
    version                                   = "0.1.21"
    namespace                                 = "aws-for-fluent-bit"
    aws_for_fluent_bit_cw_log_group           = "/${var.name}/worker-fluentbit-logs" # Optional
    aws_for_fluentbit_cwlog_retention_in_days = 90
    values = [templatefile("${path.module}/helm-values/aws-for-fluentbit-values.yaml", {
      region                    = var.region,
      aws_for_fluent_bit_cw_log = "/${var.name}/worker-fluentbit-logs"
    })]
  }

  #---------------------------------------
  # Kubecost
  #---------------------------------------
  enable_kubecost = true
  kubecost_helm_config = {
    name                = "kubecost"                      # (Required) Release name.
    repository          = "oci://public.ecr.aws/kubecost" # (Optional) Repository URL where to locate the requested chart.
    chart               = "cost-analyzer"                 # (Required) Chart name to be installed.
    version             = "1.97.0"                        # (Optional) Specify the exact chart version to install. If this is not specified, it defaults to the version set within default_helm_config: https://github.com/aws-ia/terraform-aws-eks-blueprints/blob/main/modules/kubernetes-addons/kubecost/locals.tf
    namespace           = "kubecost"                      # (Optional) The namespace to install the release into.
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
    timeout             = "300"
    values              = [templatefile("${path.module}/helm-values/kubecost-values.yaml", {})]
  }

  #---------------------------------------------------------------
  # Apache YuniKorn Add-on
  #---------------------------------------------------------------
  enable_yunikorn = var.enable_yunikorn
  yunikorn_helm_config = {
    name       = "yunikorn"
    repository = "https://apache.github.io/yunikorn-release"
    chart      = "yunikorn"
    version    = "1.1.0"
    timeout    = "300"
    values = [
      templatefile("${path.module}/helm-values/yunikorn-values.yaml", {
        image_version    = "1.1.0"
        operating_system = "linux"
        node_group_type  = "core"
      })
    ]
    timeout = "300"
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
    values = [templatefile("${path.module}/helm-values/prometheus-values.yaml", {
      operating_system = "linux"
    })]
  }

  tags = local.tags
}

#---------------------------------------
# Karpenter Provisioners
#---------------------------------------
data "kubectl_path_documents" "karpenter_provisioners" {
  pattern = "${path.module}/provisioners/spark-*.yaml"
  vars = {
    azs              = local.region
    eks_cluster_id   = module.eks.cluster_name
  }
}

resource "kubectl_manifest" "karpenter_provisioner" {
  for_each  = toset(data.kubectl_path_documents.karpenter_provisioners.documents)
  yaml_body = each.value

  depends_on = [module.eks_blueprints_kubernetes_addons]
}

##------------------------------------------------------------------------------------------------------------
## Karpenter-CRD Helm Chart for upgrades - Custom Resource Definition (CRD) Upgrades
## https://gallery.ecr.aws/karpenter/karpenter-crd
## Checkout the user guide https://karpenter.sh/preview/upgrade-guide/
## https://github.com/aws/karpenter/tree/main/charts/karpenter-crd
##------------------------------------------------------------------------------------------------------------
## README:
## Karpenter ships with a few Custom Resource Definitions (CRDs). These CRDs are published:
## As an independent helm chart karpenter-crd - source that can be used by Helm to manage the lifecycle of these CRDs.
## To upgrade or install karpenter-crd run:
## helm upgrade --install karpenter-crd oci://public.ecr.aws/karpenter/karpenter-crd --version vx.y.z --namespace karpenter --create-namespace
##------------------------------------------------------------------------------------------------------------
##resource "helm_release" "karpenter_crd" {
##  namespace        = local.karpenter_namespace
##  create_namespace = true
##  name             = "karpenter"
##  repository       = "oci://public.ecr.aws/karpenter/karpenter-crd"
##  chart            = "karpenter-crd"
##  version          = "v0.24.0"
##  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
##  repository_password = data.aws_ecrpublic_authorization_token.token.password
##
##  depends_on = [module.eks_blueprints_kubernetes_addons.karpenter]
##}

#---------------------------------------------------------------
# Amazon Prometheus Workspace
#---------------------------------------------------------------
resource "aws_prometheus_workspace" "amp" {
  alias = format("%s-%s", "amp-ws", local.name)

  tags = local.tags
}
