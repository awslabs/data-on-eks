locals {
  spark_team = "spark-team-a"
}

resource "kubernetes_namespace_v1" "spark_team_a" {
  metadata {
    name = local.spark_team
  }
  timeouts {
    delete = "15m"
  }
}

resource "kubernetes_service_account_v1" "spark_team_a" {
  metadata {
    name        = local.spark_team
    namespace   = kubernetes_namespace_v1.spark_team_a.metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.spark_team_a_irsa.iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "spark_team_a" {
  metadata {
    name      = "${local.spark_team}-secret"
    namespace = kubernetes_namespace_v1.spark_team_a.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.spark_team_a.metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace_v1.spark_team_a.metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

#---------------------------------------------------------------
# IRSA for Spark driver/executor pods for "spark-team-a"
#---------------------------------------------------------------
module "spark_team_a_irsa" {
  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.0"

  # Disable helm release
  create_release = false

  # IAM role for service account (IRSA)
  create_role   = true
  role_name     = "${local.name}-${local.spark_team}"
  create_policy = false
  role_policies = {
    consumer_s3_kafka_policy = aws_iam_policy.consumer_s3_kafka.arn
  }

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = local.spark_team
      service_account = local.spark_team
    }
  }
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

  depends_on = [module.spark_team_a_irsa]
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

  depends_on = [module.spark_team_a_irsa]
}
