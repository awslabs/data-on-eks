module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.24.0"

  eks_cluster_id       = module.eks.cluster_name
  eks_cluster_endpoint = module.eks.cluster_endpoint
  eks_oidc_provider    = module.eks.oidc_provider
  eks_cluster_version  = module.eks.cluster_version
  eks_cluster_domain   = var.eks_cluster_domain

  # Wait on the node group(s) before provisioning addons
  data_plane_wait_arn = join(",", [for group in module.eks.eks_managed_node_groups : group.node_group_arn])

  #---------------------------------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------------------------------
  enable_amazon_eks_vpc_cni            = true
  enable_amazon_eks_coredns            = true
  enable_amazon_eks_kube_proxy         = true
  enable_amazon_eks_aws_ebs_csi_driver = true

  #---------------------------------------------------------------
  # Additional Add-ons
  #---------------------------------------------------------------
  enable_aws_load_balancer_controller = true

  enable_external_dns = true
  external_dns_helm_config = {
    values = [templatefile("${path.module}/helm-values/external-dns-values.yaml", {
      txtOwnerId   = local.name
      domainFilter = var.eks_cluster_domain
    })]
  }

  enable_cert_manager = true

  enable_metrics_server = true
  metrics_server_helm_config = {
    set = [
      {
        name  = "image.repository"
        value = "registry.k8s.io/metrics-server/metrics-server"
      }
    ]
  }

  enable_cluster_autoscaler = true

  enable_aws_for_fluentbit                 = true
  aws_for_fluentbit_cw_log_group_retention = 30

  enable_prometheus = true
  prometheus_helm_config = {
    values = [file("${path.module}/helm-values/prometheus-values.yaml")]
  }

  enable_aws_cloudwatch_metrics = true

  enable_grafana = true
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

resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
  }

  storage_provisioner    = "ebs.csi.aws.com"
  allow_volume_expansion = true
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = {
    encrypted = true
    fsType    = "ext4"
    type      = "gp3"
  }
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
  name                    = "grafana-${random_string.random_suffix.result}"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id     = aws_secretsmanager_secret.grafana.id
  secret_string = random_password.grafana.result
}

#---------------------------------------------------------------
# Apache NiFi
#---------------------------------------------------------------

resource "random_string" "random_suffix" {
  length  = 10
  special = false
  upper   = false
}

resource "random_password" "nifi_keystore_password" {
  length  = 16
  special = false
}

#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "nifi_keystore_password" {
  name                    = "nifi_keystore_password-${random_string.random_suffix.result}"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "nifi_keystore_password" {
  secret_id     = aws_secretsmanager_secret.nifi_keystore_password.id
  secret_string = random_password.nifi_keystore_password.result
}

resource "random_password" "nifi_truststore_password" {
  length  = 16
  special = false
}

#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "nifi_truststore_password" {
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "nifi_truststore_password" {
  secret_id     = aws_secretsmanager_secret.nifi_truststore_password.id
  secret_string = random_password.nifi_truststore_password.result
}

resource "random_password" "nifi_login_password" {
  length  = 16
  special = false
}
#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "nifi_login_password" {
  name                    = "nifi_login_password-${random_string.random_suffix.result}"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "nifi_login_password" {
  secret_id     = aws_secretsmanager_secret.nifi_login_password.id
  secret_string = random_password.nifi_login_password.result
}

resource "random_password" "sensitive_key" {
  length  = 16
  special = false
}
#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "sensitive_key" {
  name                    = "sensitive_key-${random_string.random_suffix.result}"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "sensitive_key" {
  secret_id     = aws_secretsmanager_secret.sensitive_key.id
  secret_string = random_password.sensitive_key.result
}

resource "helm_release" "nifi" {
  name             = "nifi"
  repository       = "https://cetic.github.io/helm-charts"
  chart            = "nifi"
  version          = "1.1.3"
  namespace        = "nifi"
  create_namespace = true

  values = [templatefile("${path.module}/helm-values/nifi-values.yaml", {
    hostname            = join(".", [var.nifi_sub_domain, var.eks_cluster_domain])
    ssl_cert_arn        = data.aws_acm_certificate.issued.arn
    nifi_username       = var.nifi_username
    nifi_password       = data.aws_secretsmanager_secret_version.nifi_login_password_version.secret_string
    keystore_password   = data.aws_secretsmanager_secret_version.nifi_keystore_password_version.secret_string
    truststore_password = data.aws_secretsmanager_secret_version.nifi_truststore_password_version.secret_string
    sensitive_key       = data.aws_secretsmanager_secret_version.sensitive_key_version.secret_string
  })]

  depends_on = [module.eks_blueprints_kubernetes_addons]
}
