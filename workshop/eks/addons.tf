
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
  enable_metrics_server         = true
  enable_cluster_autoscaler     = true
  enable_aws_cloudwatch_metrics = true

  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
  enable_karpenter                           = var.enable_karpenter
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
  # AWS for FluentBit - DaemonSet
  #---------------------------------------
  enable_aws_for_fluentbit = true
  aws_for_fluentbit_helm_config = {
    name                                      = "aws-for-fluent-bit"
    chart                                     = "aws-for-fluent-bit"
    repository                                = "https://aws.github.io/eks-charts"
    version                                   = "0.1.21"
    namespace                                 = "aws-for-fluent-bit"
    aws_for_fluent_bit_cw_log_group           = "/${var.name}/fluentbit-logs" # Optional
    aws_for_fluentbit_cwlog_retention_in_days = 30
    values = [templatefile("${path.module}/helm-values/aws-for-fluentbit-values.yaml", {
      region                    = var.region,
      aws_for_fluent_bit_cw_log = "/${var.name}/fluentbit-logs"
    })]
  }

  #---------------------------------------
  # Kubecost
  #---------------------------------------
  enable_kubecost = var.enable_kubecost
  kubecost_helm_config = {
    name                = "kubecost"
    repository          = "oci://public.ecr.aws/kubecost"
    chart               = "cost-analyzer"
    version             = "1.97.0"
    namespace           = "kubecost"
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
    values = [templatefile("${path.module}/helm-values/yunikorn-values.yaml", {
      image_version = "1.1.0"
    })]
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
    values     = [templatefile("${path.module}/helm-values/prometheus-values.yaml", {})]
  }

  tags = local.tags

}
#---------------------------------------------------------------
# Amazon Prometheus Workspace
#---------------------------------------------------------------
resource "aws_prometheus_workspace" "amp" {
  alias = format("%s-%s", "amp-ws", local.name)

  tags = local.tags
}
