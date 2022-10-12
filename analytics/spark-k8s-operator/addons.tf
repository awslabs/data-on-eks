module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.12.2"

  eks_cluster_id       = module.eks_blueprints.eks_cluster_id
  eks_cluster_endpoint = module.eks_blueprints.eks_cluster_endpoint
  eks_oidc_provider    = module.eks_blueprints.oidc_provider
  eks_cluster_version  = module.eks_blueprints.eks_cluster_version

  #---------------------------------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------------------------------
  # EKS Addons
  enable_amazon_eks_vpc_cni            = true
  enable_amazon_eks_coredns            = true
  enable_amazon_eks_kube_proxy         = true
  enable_amazon_eks_aws_ebs_csi_driver = true

  #---------------------------------------------------------------
  # CoreDNS Autoscaler helps to scale for large EKS Clusters
  #   Further tuning for CoreDNS is to leverage NodeLocal DNSCache -> https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/
  #---------------------------------------------------------------
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
      node_group_type  = "core"
    })]
    description = "Cluster Proportional Autoscaler for CoreDNS Service"
  }

  #---------------------------------------------------------------
  # Metrics Server
  #---------------------------------------------------------------
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
      node_group_type  = "core"
    })]
  }

  #---------------------------------------------------------------
  # Cluster Autoscaler
  #---------------------------------------------------------------
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
      node_group_type  = "core"
    })]
  }

  #---------------------------------------------------------------
  # Spark Operator Add-on
  #---------------------------------------------------------------
  enable_spark_k8s_operator = true
  spark_k8s_operator_helm_config = {
    name             = "spark-operator"
    chart            = "spark-operator"
    repository       = "https://googlecloudplatform.github.io/spark-on-k8s-operator"
    version          = "1.1.25"
    namespace        = "spark-operator"
    timeout          = "300"
    create_namespace = true
    values = [templatefile("${path.module}/helm-values/spark-k8s-operator-values.yaml", {
      operating_system = "linux"
      node_group_type  = "core"
    })]
  }

  #---------------------------------------------------------------
  # Apache YuniKorn Add-on
  #---------------------------------------------------------------
  enable_yunikorn = true
  yunikorn_helm_config = {
    name       = "yunikorn"
    repository = "https://apache.github.io/yunikorn-release"
    chart      = "yunikorn"
    version    = "0.12.2"
    values = [templatefile("${path.module}/helm-values/yunikorn-values.yaml", {
      image_version    = "0.12.2"
      operating_system = "linux"
      node_group_type  = "core"
    })]
    timeout = "300"
  }

  #---------------------------------------------------------------
  # Spark History Server Addon
  #---------------------------------------------------------------
  enable_spark_history_server = true
  # This example is using a managed s3 readonly policy. It' recommended to create your own IAM Policy
  spark_history_server_irsa_policies = ["arn:${data.aws_partition.current.id}:iam::aws:policy/AmazonS3ReadOnlyAccess"]
  spark_history_server_helm_config = {
    name       = "spark-history-server"
    chart      = "spark-history-server"
    repository = "https://hyper-mesh.github.io/spark-history-server"
    version    = "1.0.0"
    namespace  = "spark-history-server"
    timeout    = "300"
    values = [
      <<-EOT
        serviceAccount:
          create: false

        sparkHistoryOpts: "-Dspark.history.fs.logDirectory=s3a://${aws_s3_bucket.this.id}/${aws_s3_object.this.key}"

        # Update spark conf according to your needs
        sparkConf: |-
          spark.hadoop.fs.s3a.aws.credentials.provider=com.amazonaws.auth.WebIdentityTokenCredentialsProvider
          spark.history.fs.eventLog.rolling.maxFilesToRetain=5
          spark.hadoop.fs.s3a.impl=org.apache.hadoop.fs.s3a.S3AFileSystem
          spark.eventLog.enabled=true
          spark.history.ui.port=18080

        resources:
          limits:
            cpu: 200m
            memory: 2G
          requests:
            cpu: 100m
            memory: 1G
        EOT
    ]
  }

  #---------------------------------------------------------------
  # Logging with FluentBit
  #---------------------------------------------------------------
  enable_aws_for_fluentbit                 = true
  aws_for_fluentbit_cw_log_group_retention = 30
  aws_for_fluentbit_helm_config = {
    name                            = "aws-for-fluent-bit"
    chart                           = "aws-for-fluent-bit"
    repository                      = "https://aws.github.io/eks-charts"
    version                         = "0.1.19"
    namespace                       = "logging"
    timeout                         = "300"
    aws_for_fluent_bit_cw_log_group = "/${module.eks_blueprints.eks_cluster_id}/worker-fluentbit-logs" # Optional
    create_namespace                = true
    values = [templatefile("${path.module}/helm-values/aws-for-fluentbit-values.yaml", {
      region                    = data.aws_region.current.id
      aws_for_fluent_bit_cw_log = "/${module.eks_blueprints.eks_cluster_id}/worker-fluentbit-logs"
    })]
    set = [
      {
        name  = "nodeSelector.kubernetes\\.io/os"
        value = "linux"
      }
    ]
  }

  #---------------------------------------------------------------
  # Amazon Managed Prometheus
  #---------------------------------------------------------------
  enable_amazon_prometheus             = true
  amazon_prometheus_workspace_endpoint = module.managed_prometheus.workspace_prometheus_endpoint

  #---------------------------------------------------------------
  # Prometheus Server Add-on
  #---------------------------------------------------------------
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
      node_group_type  = "core"
    })]
  }

  #---------------------------------------------------------------
  # Vertical Pod Autoscaling for Prometheus Server
  #---------------------------------------------------------------
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
      node_group_type  = "core"
    })]
  }

  #---------------------------------------------------------------
  # Open Source Grafana Add-on
  #---------------------------------------------------------------
  enable_grafana = true

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

  # This is required when using terraform apply with target option
  depends_on = [
    aws_s3_bucket_acl.this,
    aws_s3_bucket_public_access_block.this,
    aws_s3_bucket_server_side_encryption_configuration.this,
    aws_s3_object.this
  ]
}
