#---------------------------------------------------------------
# EKS Blueprints Addons
#---------------------------------------------------------------
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
    values = [templatefile("${path.module}/helm-values/metrics-server-values.yaml", {})]
  }

  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
  enable_karpenter                  = true
  karpenter_enable_spot_termination = true
  karpenter = {
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

  #---------------------------------------
  # CloudWatch metrics for EKS
  #---------------------------------------
  enable_aws_cloudwatch_metrics = true
  aws_cloudwatch_metrics = {
    values = [templatefile("${path.module}/helm-values/aws-cloudwatch-metrics-values.yaml", {})]
  }

  #---------------------------------------
  # Adding AWS Load Balancer Controller
  #---------------------------------------
  enable_aws_load_balancer_controller = true


  #---------------------------------------
  # AWS for FluentBit - DaemonSet
  #---------------------------------------
  enable_aws_for_fluentbit = true
  aws_for_fluentbit_cw_log_group = {
    use_name_prefix   = false
    name              = "/${local.name}/aws-fluentbit-logs" # Add-on creates this log group
    retention_in_days = 30
  }
  aws_for_fluentbit = {
    s3_bucket_arns = [
      module.s3_bucket.s3_bucket_arn,
      "${module.s3_bucket.s3_bucket_arn}/*}"
    ]
    values = [templatefile("${path.module}/helm-values/aws-for-fluentbit-values.yaml", {
      region               = local.region,
      cloudwatch_log_group = "/${local.name}/aws-fluentbit-logs"
      s3_bucket_name       = module.s3_bucket.s3_bucket_id
      cluster_name         = module.eks.cluster_name
    })]
  }

  #---------------------------------------
  # Prommetheus and Grafana stack
  #---------------------------------------
  #---------------------------------------------------------------
  # Install Kafka Montoring Stack with Prometheus and Grafana
  # 1- Grafana port-forward `kubectl port-forward svc/kube-prometheus-stack-grafana 8080:80 -n kube-prometheus-stack`
  # 2- Grafana Admin user: admin
  # 3- Get admin user password: `aws secretsmanager get-secret-value --secret-id <output.grafana_secret_name> --region $AWS_REGION --query "SecretString" --output text`
  #---------------------------------------------------------------
  enable_kube_prometheus_stack = true
  kube_prometheus_stack = {
    values = [
      var.enable_amazon_prometheus ? templatefile("${path.module}/helm-values/kube-prometheus-amp-enable.yaml", {
        region              = local.region
        amp_sa              = local.amp_ingest_service_account
        amp_irsa            = module.amp_ingest_irsa[0].iam_role_arn
        amp_remotewrite_url = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}/api/v1/remote_write"
        amp_url             = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}"
      }) : templatefile("${path.module}/helm-values/kube-prometheus.yaml", {})
    ]
    chart_version = "48.1.1"
    set_sensitive = [
      {
        name  = "grafana.adminPassword"
        value = data.aws_secretsmanager_secret_version.admin_password_version.secret_string
      }
    ],
  }

  tags = local.tags
}

#---------------------------------------
# Karpenter Provisioners
#---------------------------------------
data "kubectl_path_documents" "karpenter_provisioners" {
  pattern = "${path.module}/karpenter-provisioners/provisioner*.yaml"
  vars = {
    azs            = local.region
    eks_cluster_id = module.eks.cluster_name
  }
}

resource "kubectl_manifest" "karpenter_provisioner" {
  for_each  = toset(data.kubectl_path_documents.karpenter_provisioners.documents)
  yaml_body = each.value

  depends_on = [module.eks_blueprints_addons]
}

#---------------------------------------
# Trino Helm Add-on
#---------------------------------------
module "trino_hive_addon" {
  source = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.1.1" #ensure to update this to the latest/desired version

  chart            = "trino"
  chart_version    = "0.13.0"
  repository       = "https://trinodb.github.io/charts"
  description      = "Trino Helm Chart deployment"
  namespace        = "${local.trino_namespace}"
  create_namespace = true

  values = [
    templatefile("${path.module}/trino-values/trino-${local.catalog_type}.yaml", 
    {
      sa                 = local.trino_sa
      region             = local.region
      bucket_id          = module.trino_s3_bucket.s3_bucket_id
      exchange_bucket_id = module.trino_exchange_bucket.s3_bucket_id
      irsa_arn           = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.trino_sa}-role"
    })
  ]

  set_irsa_names = ["serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"]

  # IAM role for service account (IRSA)
  allow_self_assume_role = true
  create_role            = true
  role_name              = "${local.trino_sa}-role"
  role_name_use_prefix   = false
  role_policies          = {
    data_bucket_policy     = aws_iam_policy.trino_s3_bucket_policy.arn
    exchange_bucket_policy = aws_iam_policy.trino_exchange_bucket_policy.arn
    glue_policy            = data.aws_iam_policy.glue_full_access.arn,
  }

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      service_account = local.trino_sa
    }
  }
}

#---------------------------------------
# Trino Helm Add-on with Iceberg
#---------------------------------------
# resource "helm_release" "trino_iceberg" {
#   name             = "${local.name}-iceberg"
#   chart            = "trino"
#   repository       = "https://trinodb.github.io/charts"
#   version          = "0.13.0"
#   namespace        = "${local.trino_namespace}-iceberg"
#   create_namespace = true
#   description      = "Trino Helm Chart deployment to use Iceberg"

#   values = [
#     templatefile("${path.module}/trino-values/trino-iceberg.yaml", 
#     {
#       sa                 = local.trino_sa
#       region             = local.region
#       bucket_id          = module.trino_s3_bucket.s3_bucket_id
#       exchange_bucket_id = module.trino_exchange_bucket.s3_bucket_id
#       irsa_arn           = module.trino_s3_irsa.irsa_iam_role_arn
#     })
#   ]
# }

#---------------------------------------------------------------
# Grafana Admin credentials resources
#---------------------------------------------------------------
data "aws_secretsmanager_secret_version" "admin_password_version" {
  secret_id  = aws_secretsmanager_secret.grafana.id
  depends_on = [aws_secretsmanager_secret_version.grafana]
}

resource "random_password" "grafana" {
  length           = 16
  special          = true
  override_special = "@_"
}

#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "grafana" {
  name                    = "${local.name}-grafana"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id     = aws_secretsmanager_secret.grafana.id
  secret_string = random_password.grafana.result
}

# Creating an s3 bucket for Spark History event logs
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket_prefix = "${local.name}-trino-"

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

# Creating an s3 bucket prefix. Ensure you copy Spark History event logs under this path to visualize the dags
resource "aws_s3_object" "this" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "trino-event-logs/"
  content_type = "application/x-directory"
}
