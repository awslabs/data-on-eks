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
    spark_team_a_policy = aws_iam_policy.spark.arn
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
# Creates IAM policy for IRSA. Provides IAM permissions for Spark driver/executor pods
#---------------------------------------------------------------
resource "aws_iam_policy" "spark" {
  description = "IAM role policy for Spark Job execution"
  name        = "${local.name}-spark-irsa"
  policy      = data.aws_iam_policy_document.spark_operator.json
}

#---------------------------------------------------------------
# Kubernetes Cluster role for service Account spark-team-a
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
# Kubernetes Cluster Role binding role for service Account spark-team-a
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

#---------------------------------------------------------------
# Kubernetes Cluster role for argo workflows to run spark jobs
#---------------------------------------------------------------
resource "kubernetes_cluster_role" "spark_argowf_role" {
  metadata {
    name = "spark-op-role"
  }

  rule {
    verbs      = ["*"]
    api_groups = ["sparkoperator.k8s.io"]
    resources  = ["sparkapplications"]
  }
}

#---------------------------------------------------------------
# Kubernetes Role binding for argo workflows/spark-team-a
#---------------------------------------------------------------

# Allow argo-workflows to run spark application in spark-team-a
resource "kubernetes_role_binding" "spark_role_binding" {
  metadata {
    name      = "spark-team-a-spark-rolebinding"
    namespace = local.spark_team
  }

  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = "argo-workflows"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.spark_argowf_role.id
  }

  depends_on = [module.eks_blueprints_addons]
}

# Grant argo-workflows admin role
resource "kubernetes_role_binding" "admin_rolebinding_argoworkflows" {
  metadata {
    name      = "argo-workflows-admin-rolebinding"
    namespace = "argo-workflows"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = "argo-workflows"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "admin"
  }

  depends_on = [module.eks_blueprints_addons]
}

# Grant spark-team-a admin role
resource "kubernetes_role_binding" "admin_rolebinding_spark_team_a" {
  metadata {
    name      = "spark-team-a-admin-rolebinding"
    namespace = local.spark_team
  }

  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = local.spark_team
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "admin"
  }

  depends_on = [resource.kubernetes_namespace_v1.spark_team_a]
}

#---------------------------------------------------------------
# IRSA for Argo events to read and send SQS
#---------------------------------------------------------------
resource "aws_iam_policy" "sqs_argo_events" {
  description = "IAM policy for Argo Events"
  name_prefix = format("%s-%s-", local.name, "argo-events")
  path        = "/"
  policy      = data.aws_iam_policy_document.sqs_argo_events.json
}


data "aws_iam_policy_document" "sqs_argo_events" {
  statement {
    sid       = "AllowReadingAndSendingSQSfromArgoEvents"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "sqs:ListQueues",
      "sqs:GetQueueUrl",
      "sqs:ListDeadLetterSourceQueues",
      "sqs:ListMessageMoveTasks",
      "sqs:ReceiveMessage",
      "sqs:SendMessage",
      "sqs:GetQueueAttributes",
      "sqs:ListQueueTags"
    ]
  }
}

locals {
  event_namespace       = "argo-events"
  event_service_account = "event-sa"
}

resource "kubernetes_service_account_v1" "event_sa" {
  metadata {
    name        = local.event_service_account
    namespace   = local.event_namespace
    annotations = { "eks.amazonaws.com/role-arn" : module.irsa_argo_events.iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "event_sa" {
  metadata {
    name      = "${local.event_service_account}-secret"
    namespace = local.event_namespace
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.event_sa.metadata[0].name
      "kubernetes.io/service-account.namespace" = local.event_namespace
    }
  }

  type = "kubernetes.io/service-account-token"
}

module "irsa_argo_events" {
  source         = "aws-ia/eks-blueprints-addon/aws"
  version        = "~> 1.0"
  create_release = false
  create_policy  = false
  create_role    = true
  role_name      = "${local.name}-${local.event_namespace}"
  role_policies  = { policy_event = aws_iam_policy.sqs_argo_events.arn }

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = local.event_namespace
      service_account = local.event_service_account
    }
  }

  depends_on = [module.eks_blueprints_addons]

  tags = local.tags
}
