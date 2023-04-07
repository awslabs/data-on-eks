locals {
  flink_team = "flink-team-a"
}

#---------------------------------------------------------------
# Creates IAM policy for IRSA. Provides IAM permissions for flink pods
#---------------------------------------------------------------
resource "aws_iam_policy" "flink" {
  description = "IAM role policy for flink Job execution"
  name        = "${local.name}-flink-irsa"
  policy      = data.aws_iam_policy_document.flink_operator.json
}

#---------------------------------------------------------------
# IRSA for flink pods for "flink-team-a"
#---------------------------------------------------------------
module "flink_irsa" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/irsa?ref=v4.15.0"

  eks_cluster_id             = local.name
  eks_oidc_provider_arn      = module.eks.oidc_provider_arn
  irsa_iam_policies          = [aws_iam_policy.flink.arn]
  kubernetes_namespace       = "${local.flink_team}-ns"
  kubernetes_service_account = "${local.flink_team}-sa"
}

#---------------------------------------------------------------
# Flink Role
#---------------------------------------------------------------
resource "kubernetes_role" "flink" {
  metadata {
    name      = "${local.flink_team}-role"
    namespace = "${local.flink_team}-ns"

    labels = {
      "app.kubernetes.io/name"    = "flink-kubernetes-operator"
      "app.kubernetes.io/version" = "1.4.0"
    }
  }

  rule {
    verbs      = ["*"]
    api_groups = [""]
    resources  = ["pods", "pods/log", "configmaps", "endpoints", "persistentvolumes", "persistentvolumeclaims"]
  }

  rule {
    verbs      = ["create", "patch", "delete", "watch"]
    api_groups = [""]
    resources  = ["secrets"]
  }

  rule {
    verbs      = ["*"]
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets"]
  }

  rule {
    verbs      = ["get", "list", "watch", "describe", "create", "edit", "delete", "annotate", "patch", "label"]
    api_groups = ["extensions", "networking.k8s.io"]
    resources  = ["ingresses"]
  }

  rule {
    verbs      = ["list", "watch"]
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses"]
  }

  rule {
    verbs      = ["get", "list", "watch", "describe", "create", "edit", "delete", "annotate", "patch", "label"]
    api_groups = ["batch"]
    resources  = ["jobs"]
  }

  depends_on = [module.flink_irsa]
}

#---------------------------------------------------------------
# Flink Rolebinding
#---------------------------------------------------------------
resource "kubernetes_role_binding" "flink" {
  metadata {
    name      = "${local.flink_team}-role-binding"
    namespace = "${local.flink_team}-ns"

    labels = {
      "app.kubernetes.io/name"    = "flink-kubernetes-operator"
      "app.kubernetes.io/version" = "1.4.0"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "${local.flink_team}-role"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "${local.flink_team}-sa"
    namespace = "${local.flink_team}-ns"
  }

  depends_on = [module.flink_irsa]
}
