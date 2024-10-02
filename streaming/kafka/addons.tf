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

#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------

module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.20"

  role_name_prefix = "${module.eks.cluster_name}-ebs-csi-driver-"

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
  version = "1.16.3"

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
  # Metrics Server
  #---------------------------------------
  enable_metrics_server = true
  metrics_server = {
    timeout = "300"
    values = [templatefile("${path.module}/helm-values/metrics-server-values.yaml", {
      operating_system = "linux"
      node_group_type  = "core"
    })]
  }

  #---------------------------------------
  # Karpenter
  #---------------------------------------
  enable_karpenter = true
  karpenter = {
    chart_version       = "1.0.5"
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }
  karpenter_enable_spot_termination          = true
  karpenter_enable_instance_profile_creation = true
  karpenter_node = {
    iam_role_use_name_prefix = false
  }

  #---------------------------------------
  # Prommetheus and Grafana stack
  #---------------------------------------
  #---------------------------------------------------------------
  # Install Kafka Monitoring Stack with Prometheus and Grafana
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
        storage_class_type  = kubernetes_storage_class.ebs_csi_encrypted_gp3_storage_class.id
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


#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "eks_data_addons" {
  source  = "aws-ia/eks-data-addons/aws"
  version = "1.32.1" # ensure to update this to the latest/desired version

  oidc_provider_arn = module.eks.oidc_provider_arn
  #---------------------------------------------------------------
  # Strimzi Kafka Add-on
  #---------------------------------------------------------------
  enable_strimzi_kafka_operator = true
  strimzi_kafka_operator_helm_config = {
    values = [templatefile("${path.module}/helm-values/strimzi-kafka-values.yaml", {
      operating_system = "linux"
      node_group_type  = "core"
    })],
    version = "0.43.0"
  }

  depends_on = [module.eks_blueprints_addons]
}

#---------------------------------------------------------------
# Install Kafka cluster
#---------------------------------------------------------------

resource "kubernetes_namespace" "kafka_namespace" {
  metadata {
    name = local.kafka_namespace
  }

  depends_on = [module.eks.cluster_name]
}

data "kubectl_path_documents" "kafka_cluster" {
  pattern = "${path.module}/kafka-manifests/kafka-cluster.yaml"
}

resource "kubectl_manifest" "kafka_cluster" {
  for_each  = toset(data.kubectl_path_documents.kafka_cluster.documents)
  yaml_body = each.value

  depends_on = [module.eks_data_addons]
}

#---------------------------------------------------------------
# Deploy Strimzi Kafka and Zookeeper dashboards in Grafana
#---------------------------------------------------------------

data "kubectl_path_documents" "podmonitor_metrics" {
  pattern = "${path.module}/monitoring-manifests/podmonitor-*.yaml"
}

resource "kubectl_manifest" "podmonitor_metrics" {
  for_each  = toset(data.kubectl_path_documents.podmonitor_metrics.documents)
  yaml_body = each.value

  depends_on = [module.eks_blueprints_addons]
}

data "kubectl_path_documents" "grafana_strimzi_dashboard" {
  pattern = "${path.module}/monitoring-manifests/grafana-strimzi-*-dashboard.yaml"
}

resource "kubectl_manifest" "grafana_strimzi_dashboard" {
  for_each  = toset(data.kubectl_path_documents.grafana_strimzi_dashboard.documents)
  yaml_body = each.value

  depends_on = [module.eks_blueprints_addons]
}

#---------------------------------------------------------------
# Karpenter Resources
#---------------------------------------------------------------

data "kubectl_path_documents" "karpenter" {
  pattern = "${path.module}/karpenter-manifests/*.yaml"
}

resource "kubectl_manifest" "karpenter" {
  for_each  = toset(data.kubectl_path_documents.karpenter.documents)
  yaml_body = replace(each.value, "--CLUSTER_NAME--", local.name)

  depends_on = [module.eks_data_addons]
}
