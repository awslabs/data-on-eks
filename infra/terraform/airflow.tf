locals {
  airflow_name                      = "airflow"
  airflow_namespace                 = "airflow"
  airflow_scheduler_service_account = "airflow-scheduler"
  airflow_api_service_account = "airflow-api-server"
  airflow_workers_service_account   = "airflow-worker"
  airflow_dag_service_account   = "airflow-dag-processor"
  airflow_webserver_secret_name     = "airflow-webserver-secret-key"

  # PostgreSQL in-cluster
  airflow_db_user = "airflow"
  airflow_db_name = "airflow"
  airflow_db_host = "airflow-postgresql" # Default service name for in-cluster postgres

  airflow_values = var.enable_airflow ? templatefile("${path.module}/helm-values/airflow.yaml", {
    airflow_db_user      = local.airflow_db_user
    airflow_db_pass      = random_password.airflow_postgres_user[0].result
    airflow_db_host      = local.airflow_db_host
    airflow_db_name      = local.airflow_db_name
    webserver_secret_name = kubernetes_secret.airflow_webserver_secret[0].metadata[0].name
    worker_service_account = local.airflow_workers_service_account
    scheduler_service_account = local.airflow_scheduler_service_account
    api_service_account = local.airflow_api_service_account
    dag_service_account = local.airflow_dag_service_account
    s3_bucket_name       = module.airflow_s3_bucket[0].s3_bucket_id
  }) : ""

  airflow_postgresql_manifests = provider::kubernetes::manifest_decode_multi(
    var.enable_airflow ? templatefile("${path.module}/manifests/airflow/postgresql.yaml", {
      namespace = local.airflow_namespace
      db_user   = local.airflow_db_user
      db_name   = local.airflow_db_name
    }) : ""
  )

  airflow_rbac_manifests = provider::kubernetes::manifest_decode_multi(
    var.enable_airflow ? templatefile("${path.module}/manifests/airflow/rbac.yaml", {}) : ""
  )
}

#---------------------------------------------------------------
# Airflow Namespace
#---------------------------------------------------------------
resource "kubernetes_namespace_v1" "airflow" {
  count = var.enable_airflow ? 1 : 0
  metadata {
    name = local.airflow_namespace
  }
}

#---------------------------------------------------------------
# PostgreSQL Secrets for in-cluster deployment
#---------------------------------------------------------------
resource "random_password" "airflow_postgres_user" {
  count   = var.enable_airflow ? 1 : 0
  length  = 16
  special = false
}

resource "kubernetes_secret" "airflow_postgresql_secrets" {
  count = var.enable_airflow ? 1 : 0

  metadata {
    name      = "airflow-postgresql-secrets"
    namespace = local.airflow_namespace
  }

  data = {
    "postgresql-password"    = random_password.airflow_postgres_user[0].result
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace_v1.airflow[0]]
}

#---------------------------------------------------------------
# PostgreSQL StatefulSet and Service (in-cluster)
#---------------------------------------------------------------
resource "kubectl_manifest" "airflow_postgresql" {
  for_each = { for idx, manifest in local.airflow_postgresql_manifests : idx => manifest }

  yaml_body = yamlencode(each.value)

  depends_on = [
    kubernetes_namespace_v1.airflow[0],
    kubernetes_secret.airflow_postgresql_secrets[0]
  ]
}

#---------------------------------------------------------------
# Airflow RBAC for Spark access
#---------------------------------------------------------------
resource "kubectl_manifest" "airflow_rbac" {
  for_each = { for idx, manifest in local.airflow_rbac_manifests : idx => manifest }

  yaml_body = yamlencode(each.value)

  depends_on = [
    kubernetes_namespace_v1.airflow[0]
  ]
}

#---------------------------------------------------------------
# Pod Identity for Airflow Scheduler
#---------------------------------------------------------------
module "airflow_scheduler_pod_identity" {
  count   = var.enable_airflow ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name = "${local.airflow_name}-scheduler"

  additional_policy_arns = {
    s3_access = aws_iam_policy.airflow_scheduler[0].arn
  }

  associations = {
    scheduler = {
      cluster_name    = module.eks.cluster_name
      namespace       = local.airflow_namespace
      service_account = local.airflow_scheduler_service_account
    }
  }
}

resource "aws_iam_policy" "airflow_scheduler" {
  count       = var.enable_airflow ? 1 : 0
  name        = "${local.airflow_name}-scheduler-s3-policy"
  description = "IAM Policy for Airflow Scheduler S3 access"

  policy = data.aws_iam_policy_document.airflow_s3_logs[0].json
}

#---------------------------------------------------------------
# Pod Identity for Airflow Webserver
#---------------------------------------------------------------
module "airflow_webserver_pod_identity" {
  count   = var.enable_airflow ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name = "${local.airflow_name}-webserver"

  additional_policy_arns = {
    s3_access = aws_iam_policy.airflow_webserver[0].arn
  }

  associations = {
    webserver = {
      cluster_name    = module.eks.cluster_name
      namespace       = local.airflow_namespace
      service_account = local.airflow_api_service_account
    }
  }
}

resource "aws_iam_policy" "airflow_webserver" {
  count       = var.enable_airflow ? 1 : 0
  name        = "${local.airflow_name}-webserver-s3-policy"
  description = "IAM Policy for Airflow Webserver S3 access"

  policy = data.aws_iam_policy_document.airflow_s3_logs[0].json
}

#---------------------------------------------------------------
# Pod Identity for Airflow Workers
#---------------------------------------------------------------
module "airflow_worker_pod_identity" {
  count   = var.enable_airflow ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name = "${local.airflow_name}-worker"

  additional_policy_arns = {
    s3_access = aws_iam_policy.airflow_worker[0].arn
  }

  associations = {
    worker = {
      cluster_name    = module.eks.cluster_name
      namespace       = local.airflow_namespace
      service_account = local.airflow_workers_service_account
    }
  }
}

resource "aws_iam_policy" "airflow_worker" {
  count       = var.enable_airflow ? 1 : 0
  name        = "${local.airflow_name}-worker-s3-policy"
  description = "IAM Policy for Airflow Worker S3 access"

  policy = data.aws_iam_policy_document.airflow_s3_logs[0].json
}

#---------------------------------------------------------------
# Pod Identity for DAG Processors
#---------------------------------------------------------------
module "airflow_dag_pod_identity" {
  count   = var.enable_airflow ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name = "${local.airflow_name}-dag-processor"

  additional_policy_arns = {
    s3_access = aws_iam_policy.airflow_worker[0].arn
  }

  associations = {
    dag = {
      cluster_name    = module.eks.cluster_name
      namespace       = local.airflow_namespace
      service_account = local.airflow_dag_service_account
    }
  }
}


#---------------------------------------------------------------
# S3 bucket for Airflow
#---------------------------------------------------------------
module "airflow_s3_bucket" {
  count   = var.enable_airflow ? 1 : 0
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.0"

  bucket_prefix = "${local.name}-airflow-"

  force_destroy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_object" "dags" {
  count   = var.enable_airflow ? 1 : 0
  bucket       = module.airflow_s3_bucket[0].s3_bucket_id
  key          = "dags/"
  content_type = "application/x-directory"
}

#---------------------------------------------------------------
# IAM policy document for Airflow S3 logging
#---------------------------------------------------------------
data "aws_iam_policy_document" "airflow_s3_logs" {
  count = var.enable_airflow ? 1 : 0
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${module.airflow_s3_bucket[0].s3_bucket_id}"]

    actions = [
      "s3:ListBucket"
    ]
  }
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${module.airflow_s3_bucket[0].s3_bucket_id}/*"]

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
  }
}

#---------------------------------------------------------------
# Apache Airflow Webserver Secret
#---------------------------------------------------------------
resource "random_id" "airflow_webserver_secret_key" {
  count       = var.enable_airflow ? 1 : 0
  byte_length = 16
}

resource "kubernetes_secret" "airflow_webserver_secret" {
  count = var.enable_airflow ? 1 : 0

  metadata {
    name      = local.airflow_webserver_secret_name
    namespace = local.airflow_namespace
  }

  data = {
    "webserver-secret-key" = random_id.airflow_webserver_secret_key[0].hex
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace_v1.airflow[0]]
}

#---------------------------------------------------------------
# Airflow ArgoCD Application
#---------------------------------------------------------------
resource "kubectl_manifest" "airflow_argocd_application" {
  count = var.enable_airflow ? 1 : 0
  yaml_body = templatefile("${path.module}/argocd-applications/airflow.yaml", {
    user_values_yaml = indent(8, local.airflow_values)
  })
  wait = true

  depends_on = [
    kubernetes_namespace_v1.airflow[0],
    kubectl_manifest.airflow_postgresql,
    module.airflow_scheduler_pod_identity,
    module.airflow_webserver_pod_identity,
    module.airflow_worker_pod_identity,
    kubernetes_secret.airflow_webserver_secret
  ]
}

#---------------------------------------------------------------
# Airflow PostgreSQL Connection Secret
#---------------------------------------------------------------
resource "kubernetes_secret" "airflow_config_connection" {
  count = var.enable_airflow ? 1 : 0

  metadata {
    name      = "airflow-config"
    namespace = local.airflow_namespace
  }

  data = {
    connection = format("postgresql://%s:%s@airflow-pgbouncer.%s.svc.cluster.local:6543/airflow-metadata",
      local.airflow_db_user,
      random_password.airflow_postgres_user[0].result,
      local.airflow_namespace
    )
  }

  type = "Opaque"

  depends_on = [
    kubernetes_namespace_v1.airflow[0],
    random_password.airflow_postgres_user[0]
  ]
}

resource "kubernetes_secret" "airflow_stats_connection" {
  count = var.enable_airflow ? 1 : 0

  metadata {
    name      = "pgbouncer-stats"
    namespace = local.airflow_namespace
  }

  data = {
    # this is the connection string for the pgbouncer container in the same pod.
    connection = format("postgresql://%s:%s@127.0.0.1:6543/pgbouncer?sslmode=disable",
      local.airflow_db_user,
      random_password.airflow_postgres_user[0].result
    )
  }

  type = "Opaque"

  depends_on = [
    kubernetes_namespace_v1.airflow[0],
    random_password.airflow_postgres_user[0]
  ]
}

#---------------------------------------------------------------
# Airflow PGBouncer Config Secret
#---------------------------------------------------------------
resource "kubernetes_secret" "airflow_pgbouncer_config" {
  count = var.enable_airflow ? 1 : 0

  metadata {
    name      = "pgbouncer-config"
    namespace = local.airflow_namespace
  }

  data = {
    "pgbouncer.ini" = templatefile("${path.module}/manifests/airflow/pgbouncer.ini", {
      external_database_host = local.airflow_db_host
      external_database_dbname = local.airflow_db_name
    })
    "users.txt" = format("\"%s\" \"%s\"",
      local.airflow_db_user,
      random_password.airflow_postgres_user[0].result
    )
  }

  type = "Opaque"

  depends_on = [
    kubernetes_namespace_v1.airflow[0],
  ]
}

#---------------------------------------------------------------
# Airflow AWS Connection Secret
#---------------------------------------------------------------
resource "kubernetes_secret" "airflow_connecton_config" {
  count = var.enable_airflow ? 1 : 0

  metadata {
    name      = "airflow-connection-config"
    namespace = local.airflow_namespace
  }

  data = {
    "connection-config.yaml" = templatefile("${path.module}/manifests/airflow/connection-config.yaml", {})
  }

  type = "Opaque"

  depends_on = [
    kubernetes_namespace_v1.airflow[0],
  ]
}
