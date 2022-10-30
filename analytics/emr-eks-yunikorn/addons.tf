module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.12.2"

  eks_cluster_id       = module.eks_blueprints.eks_cluster_id
  eks_cluster_endpoint = module.eks_blueprints.eks_cluster_endpoint
  eks_oidc_provider    = module.eks_blueprints.oidc_provider
  eks_cluster_version  = module.eks_blueprints.eks_cluster_version

  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
  enable_amazon_eks_vpc_cni            = true
  enable_amazon_eks_coredns            = true
  enable_amazon_eks_kube_proxy         = true
  enable_amazon_eks_aws_ebs_csi_driver = true

  #---------------------------------------------------------
  # CoreDNS Autoscaler helps to scale for large EKS Clusters
  #   Further tuning for CoreDNS is to leverage NodeLocal DNSCache -> https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/
  #---------------------------------------------------------
  enable_coredns_autoscaler = true
  coredns_autoscaler_helm_config = {
    name       = "cluster-proportional-autoscaler"
    chart      = "cluster-proportional-autoscaler"
    repository = "https://kubernetes-sigs.github.io/cluster-proportional-autoscaler"
    version    = "1.0.0"
    namespace  = "kube-system"
    timeout    = "300"
    values = [templatefile("${path.module}/helm-values/coredns-autoscaler-values.yaml", {
      operating_system = "linux"
      target           = "deployment/coredns"
    })]
    description = "Cluster Proportional Autoscaler for CoreDNS Service"
  }

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
    version    = "15.16.1"
    namespace  = "prometheus"
    timeout    = "300"
    values = [templatefile("${path.module}/helm-values/prometheus-values.yaml", {
      operating_system = "linux"
      eks_cluster_id   = local.name
    })]
  }

  #---------------------------------------
  # Kubecost
  #---------------------------------------
  enable_kubecost = false
  kubecost_helm_config = {
    name       = "kubecost"                                             # (Required) Release name.
    repository = "oci://public.ecr.aws/kubecost"                        # (Optional) Repository URL where to locate the requested chart.
    chart      = "cost-analyzer"                                        # (Required) Chart name to be installed.
    version    = "1.97.0"                                               # (Optional) Specify the exact chart version to install. If this is not specified, it defaults to the version set within default_helm_config: https://github.com/aws-ia/terraform-aws-eks-blueprints/blob/main/modules/kubernetes-addons/kubecost/locals.tf
    namespace  = "kubecost"                                             # (Optional) The namespace to install the release into.
    timeout    = "300"
    values = [templatefile("${path.module}/helm-values/kubecost-values.yaml", {
      iam-role-arn = local.kubecost_iam_role_arn
    })]
  }

  #---------------------------------------
  # Vertical Pod Autoscaling
  #---------------------------------------
  enable_vpa = true
  vpa_helm_config = {
    name       = "vpa"
    repository = "https://charts.fairwinds.com/stable" # (Optional) Repository URL where to locate the requested chart.
    chart      = "vpa"
    version    = "1.4.0"
    namespace  = "vpa"
    timeout    = "300"
    values = [templatefile("${path.module}/helm-values/vpa-values.yaml", {
      operating_system = "linux"
    })]
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
    timeout    = "300"
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
    timeout    = "300"
    aws_for_fluent_bit_cw_log_group           = "/${var.name}/worker-fluentbit-logs" # Optional
    aws_for_fluentbit_cwlog_retention_in_days = 90
    values = [templatefile("${path.module}/helm-values/aws-for-fluentbit-values.yaml", {
      region                    = var.region,
      aws_for_fluent_bit_cw_log = "/${var.name}/worker-fluentbit-logs"
    })]
  }

  tags = local.tags

  #---------------------------------------------------------------
  # Apache YuniKorn Add-on
  #---------------------------------------------------------------
  enable_yunikorn = true
  yunikorn_helm_config = {
    name       = "yunikorn"
    repository = "https://apache.github.io/yunikorn-release"
    chart      = "yunikorn"
    version    = "1.1.0"
    timeout    = "300"
    values = [templatefile("${path.module}/helm-values/yunikorn-values.yaml", {
      image_version    = "1.1.0"
      operating_system = "linux"
      node_group_type  = "core"
    })]
    timeout = "300"
  }

  #---------------------------------------------------------------
  # Spark Operator Add-on
  #---------------------------------------------------------------
  enable_spark_k8s_operator = true
  spark_k8s_operator_helm_config = {
    name             = "spark-operator"
    chart            = "spark-operator"
    repository       = "https://googlecloudplatform.github.io/spark-on-k8s-operator"
    version          = "1.1.26"
    namespace        = "spark-operator"
    timeout          = "300"
    create_namespace = true
    values = [templatefile("${path.module}/helm-values/spark-k8s-operator-values.yaml", {
      operating_system = "linux"
      node_group_type  = "core"
    })]
  }

  depends_on = [module.kubecost_irsa]
}

#---------------------------------------------------------------
# Creates IAM Role for Service Account. Provides IAM permissions for Spark driver/executor pods
#---------------------------------------------------------------
module "kubecost_irsa" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/irsa?ref=v4.12.2"

  eks_cluster_id             = local.name
  eks_oidc_provider_arn      = module.eks_blueprints.eks_oidc_provider_arn
  irsa_iam_policies          = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  irsa_iam_role_name         = local.kubecost_iam_role_name
  kubernetes_namespace       = "kubecost"
  kubernetes_service_account = "kubecost-cost-analyzer"
}

#---------------------------------------------------------------
# Creates IAM policy for IRSA. Provides IAM permissions for Spark driver/executor pods
#---------------------------------------------------------------
#resource "aws_iam_policy" "kubecost" {
#  description = "IAM role policy for Kubecost Job execution"
#  name        = "${local.name}-kubecost-irsa"
#  policy      = data.aws_iam_policy_document.spark_operator.json
#}

#---------------------------------------------------------------
# Creates IAM Role for Service Account. Provides IAM permissions for Spark driver/executor pods
#---------------------------------------------------------------
module "irsa" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/irsa?ref=v4.12.2"

  eks_cluster_id             = local.name
  eks_oidc_provider_arn      = module.eks_blueprints.eks_oidc_provider_arn
  irsa_iam_policies          = [aws_iam_policy.spark.arn]
  kubernetes_namespace       = local.spark_team
  kubernetes_service_account = local.spark_team
}

#---------------------------------------------------------------
# Creates IAM policy for IRSA. Provides IAM permissions for Spark driver/executor pods
#---------------------------------------------------------------
resource "aws_iam_policy" "spark" {
  description = "IAM role policy for Spark Job execution"
  name        = "${local.name}-spark-irsa"
  policy      = data.aws_iam_policy_document.spark_operator.json
}

#---------------------------------------------------------------
# Kubernetes Cluster role for service Account analytics-k8s-data-team-a
#---------------------------------------------------------------
resource "kubernetes_cluster_role" "spark_role" {
  metadata {
    name = "spark-cluster-role"
  }

  rule {
    verbs      = ["get", "list", "watch"]
    api_groups = [""]
    resources  = ["namespaces", "nodes", "persistentvolumes"]
  }

  rule {
    verbs      = ["list", "watch"]
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses"]
  }
  rule {
    verbs      = ["get", "list", "watch", "describe", "create", "edit", "delete", "deletecollection", "annotate", "patch", "label"]
    api_groups = [""]
    resources  = ["serviceaccounts", "services", "configmaps", "events", "pods", "pods/log", "persistentvolumeclaims"]
  }

  rule {
    verbs      = ["create", "patch", "delete", "watch"]
    api_groups = [""]
    resources  = ["secrets"]
  }

  rule {
    verbs      = ["get", "list", "watch", "describe", "create", "edit", "delete", "annotate", "patch", "label"]
    api_groups = ["apps"]
    resources  = ["statefulsets", "deployments"]
  }

  rule {
    verbs      = ["get", "list", "watch", "describe", "create", "edit", "delete", "annotate", "patch", "label"]
    api_groups = ["batch"]
    resources  = ["jobs"]
  }

  rule {
    verbs      = ["get", "list", "watch", "describe", "create", "edit", "delete", "annotate", "patch", "label"]
    api_groups = ["extensions"]
    resources  = ["ingresses"]
  }

  rule {
    verbs      = ["get", "list", "watch", "describe", "create", "edit", "delete", "deletecollection", "annotate", "patch", "label"]
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["roles", "rolebindings"]
  }

  depends_on = [module.irsa]
}
#---------------------------------------------------------------
# Kubernetes Cluster Role binding role for service Account analytics-k8s-data-team-a
#---------------------------------------------------------------
resource "kubernetes_cluster_role_binding" "spark_role_binding" {
  metadata {
    name = "spark-cluster-role-bind"
  }

  subject {
    kind      = "ServiceAccount"
    name      = local.spark_team
    namespace = local.spark_team
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.spark_role.id
  }

  depends_on = [module.irsa]
}

#---------------------------------------------------------------
# Example IAM policy for Spark job execution
#---------------------------------------------------------------
data "aws_iam_policy_document" "spark_operator" {
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::*"]

    actions = [
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
    ]
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:*"]

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
  }
}