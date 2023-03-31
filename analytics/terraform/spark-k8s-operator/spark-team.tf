locals {
  spark_team = "spark-team-a"
}
#---------------------------------------------------------------
# IRSA for Spark driver/executor pods for "spark-team-a"
#---------------------------------------------------------------
module "irsa" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/irsa?ref=v4.15.0"

  eks_cluster_id             = local.name
  eks_oidc_provider_arn      = module.eks.oidc_provider_arn
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
