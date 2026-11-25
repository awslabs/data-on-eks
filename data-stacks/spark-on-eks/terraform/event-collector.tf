locals {
  clickhouse_host        = "event-store-clickhouse-headless.logging.svc.cluster.local"
  clickhouse_port        = "8123"
  clickhouse_database    = "k8s_events"
  clickhouse_tls         = "Off"
  clickhouse_user        = "default"
  namespace              = "logging"
  clickhouse_s3_endpoint = "https://${module.data_bucket.s3_bucket_id}.s3.${local.region}.amazonaws.com/clickhouse/"
  clickhouse_sa          = "event-store-clickhouse"

  fluent_bit_values = templatefile("${path.module}/helm-values/event-collector.yaml", {
    clickhouse_host     = local.clickhouse_host
    clickhouse_port     = local.clickhouse_port
    clickhouse_database = local.clickhouse_database
    clickhouse_tls      = local.clickhouse_tls
  })
}

resource "random_password" "clickhouse" {
  length  = 16
  special = false
}

resource "kubectl_manifest" "logging_namespace" {
  yaml_body = file("${path.module}/manifests/logging/namespace.yaml")
}

resource "kubernetes_secret" "clickhouse_password" {
  metadata {
    name      = "clickhouse-password"
    namespace = local.namespace
  }

  data = {
    password = random_password.clickhouse.result
  }

  depends_on = [kubectl_manifest.logging_namespace]
}

resource "kubernetes_secret" "fluent_bit_clickhouse" {
  metadata {
    name      = "fluent-bit-clickhouse-credentials"
    namespace = local.namespace
  }

  data = {
    username = local.clickhouse_user
    password = random_password.clickhouse.result
  }

  depends_on = [kubectl_manifest.logging_namespace]
}

resource "kubectl_manifest" "event_store" {
  yaml_body = templatefile("${path.module}/argocd-applications/event-store.yaml", {
    clickhouse_s3_endpoint = local.clickhouse_s3_endpoint
  })

  depends_on = [
    helm_release.argocd,
    kubectl_manifest.clickhouse_operator,
    kubernetes_secret.clickhouse_password,
    module.clickhouse_pod_identity,
  ]
}

module "clickhouse_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.9.0"

  name = "clickhouse"

  additional_policy_arns = {
    s3_access = aws_iam_policy.clickhouse_s3.arn
  }

  associations = {
    clickhouse = {
      cluster_name    = module.eks.cluster_name
      namespace       = local.namespace
      service_account = local.clickhouse_sa
    }
  }
}

resource "aws_iam_policy" "clickhouse_s3" {
  name        = "${local.name}-clickhouse-s3"
  description = "S3 access for ClickHouse cold storage"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          module.data_bucket.s3_bucket_arn,
          "${module.data_bucket.s3_bucket_arn}/clickhouse/*"
        ]
      }
    ]
  })
}

# The Fluent Bit DaemonSet runs in kube-system, so it needs its own copy of the Secret.
resource "kubernetes_secret" "fluent_bit_clickhouse_kube_system" {
  metadata {
    name      = "fluent-bit-clickhouse-credentials"
    namespace = "kube-system"
  }

  data = {
    username = local.clickhouse_user
    password = random_password.clickhouse.result
  }
}

resource "kubectl_manifest" "event_collector" {
  yaml_body = templatefile("${path.module}/argocd-applications/event-collector.yaml", {
    user_values_yaml = indent(8, local.fluent_bit_values)
  })

  depends_on = [
    helm_release.argocd,
    kubernetes_secret.fluent_bit_clickhouse,
  ]
}
