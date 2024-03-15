
resource "kubernetes_namespace_v1" "flink_team_a" {

  metadata {
    name = "${local.flink_team}-ns"
  }
  timeouts {
    delete = "15m"
  }
}

resource "kubernetes_service_account_v1" "flink_team_a" {
  metadata {
    name        = "${local.flink_team}-sa"
    namespace   = "${local.flink_team}-ns"
    annotations = { "eks.amazonaws.com/role-arn" : module.flink_irsa.iam_role_arn }
  }

  automount_service_account_token = true
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
  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.0"

  # Disable helm release
  create_release = false

  # IAM role for service account (IRSA)
  create_role   = true
  role_name     = "${local.name}-${local.flink_team}"
  create_policy = false
  role_policies = {
    flink_team_a_policy = aws_iam_policy.flink.arn
  }

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = "${local.flink_team}-ns"
      service_account = "${local.flink_team}-sa"
    }
  }
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
      "app.kubernetes.io/name"    = "emr-flink-kubernetes-operator"
      "app.kubernetes.io/version" = "7.0.0"
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