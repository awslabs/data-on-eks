locals {
  teams = ["spark-team-a", "spark-team-b", "spark-team-c", "spark-s3-express", "raydata"] # Add more team names as needed
}

resource "kubernetes_namespace_v1" "spark_team" {
  for_each = toset(local.teams)

  metadata {
    name = each.value
  }
  timeouts {
    delete = "15m"
  }
}

resource "kubernetes_service_account_v1" "spark_team" {
  for_each = toset(local.teams)

  metadata {
    name        = each.value
    namespace   = kubernetes_namespace_v1.spark_team[each.key].metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.spark_team_irsa[each.key].iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "spark_team" {
  for_each = toset(local.teams)

  metadata {
    name      = "${each.value}-secret"
    namespace = kubernetes_namespace_v1.spark_team[each.key].metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.spark_team[each.key].metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace_v1.spark_team[each.key].metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

module "spark_team_irsa" {
  for_each = toset(local.teams)

  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.1"

  create_release = false
  create_role    = true
  role_name      = "${local.name}-${each.value}"
  create_policy  = false
  role_policies = {
    spark_team_policy = aws_iam_policy.spark.arn
    s3tables_policy   = aws_iam_policy.s3tables.arn
  }

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = each.value
      service_account = each.value
    }
  }
}

resource "aws_iam_policy" "spark" {
  description = "IAM role policy for Spark Job execution"
  name_prefix = "${local.name}-spark-irsa"
  policy      = data.aws_iam_policy_document.spark_operator.json
}

resource "aws_iam_policy" "s3tables" {
  description = "IAM role policy for S3 Tables Access from Spark Job execution"
  name_prefix = "${local.name}-s3tables-irsa"
  policy      = data.aws_iam_policy_document.s3tables_policy.json
}

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
    api_groups = ["batch", "extensions"]
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

  depends_on = [module.spark_team_irsa]
}

resource "kubernetes_cluster_role_binding" "spark_role_binding" {
  for_each = toset(local.teams)

  metadata {
    name = "spark-cluster-role-bind-${each.value}"
  }

  subject {
    kind      = "ServiceAccount"
    name      = each.value
    namespace = each.value
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.spark_role.id
  }

  depends_on = [module.spark_team_irsa]
}
