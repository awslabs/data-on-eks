locals {
    teams = var.spark_teams
}
#---------------------------------------------------------------
# Kubernetes Cluster Role binding role for Airflow Worker with Spark Operator Role
#---------------------------------------------------------------
resource "kubernetes_cluster_role_binding" "airflow_worker_spark_role_binding" {
  metadata {
    name = "airflow-worker-spark-cluster-role-bind"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.airflow_worker.metadata[0].name
    namespace = local.airflow_namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "spark-operator"
  }

  depends_on = [module.airflow_irsa_worker]
}

#---------------------------------------------------------------
# Example IAM policy for Spark job execution
#---------------------------------------------------------------
data "aws_iam_policy_document" "spark_operator" {
  statement {
    sid       = "AccessPointAccess"
    effect    = "Allow"
    resources = [
      "${module.airflow_s3_bucket.s3_access_arn}",
      "${module.airflow_s3_bucket.s3_access_arn}/*"
    ]

    actions = [
      "s3-outposts:GetObject",
      "s3-outposts:PutObject",
      "s3-outposts:DeleteObject",
      "s3-outposts:ListBucket"
    ]
  }
  statement {
    sid       = "BucketAccess"
    effect    = "Allow"
    resources = [
      "${module.airflow_s3_bucket.s3_bucket_arn}",
      "${module.airflow_s3_bucket.s3_bucket_arn}/*"
    ]

    actions = [
      "s3-outposts:GetObject",
      "s3-outposts:PutObject",
      "s3-outposts:DeleteObject",
      "s3-outposts:ListBucket"
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


# Create cluster role for Airflow Worker
resource "kubernetes_cluster_role" "airflow_spark_access" {
  metadata {
    name = "spark-operator"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log"]
    verbs      = ["get", "list", "watch", "create", "delete", "patch"]
  }

  rule {
    api_groups = ["sparkoperator.k8s.io"]
    resources  = ["sparkapplications", "sparkapplications/status"]
    verbs      = ["create", "get", "list", "delete", "watch", "patch"]
  }
}

# Create cluster role binding for Airflow Worker with other teams
resource "kubernetes_role_binding" "airflow_spark_binding" {
  for_each = toset(local.teams)

  metadata {
    name      = "airflow-spark-binding"
    namespace = each.value
  }

  subject {
    kind      = "ServiceAccount"
    name      = local.airflow_workers_service_account
    namespace = local.airflow_namespace
  }

  role_ref {
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.airflow_spark_access.metadata[0].name
    api_group = "rbac.authorization.k8s.io"
  }

  depends_on = [kubernetes_cluster_role.airflow_spark_access]
}
