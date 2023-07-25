# Creates a Data team with all the required resources for Spark

locals {
  data_team = "data-team-a"
}

# Create a namespace for data-team-a
resource "kubernetes_namespace_v1" "data_team_a" {
  metadata {
    name = local.data_team
  }
  timeouts {
    delete = "15m"
  }
}

# Create a service account for data-team-a
resource "kubernetes_service_account_v1" "data_team_a" {
  metadata {
    name        = local.data_team
    namespace   = kubernetes_namespace_v1.data_team_a.metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.data_team_a_irsa.iam_role_arn }
  }

  automount_service_account_token = true
}

# Create a secret for data-team-a
resource "kubernetes_secret_v1" "data_team_a" {
  metadata {
    name      = "${local.data_team}-secret"
    namespace = kubernetes_namespace_v1.data_team_a.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.data_team_a.metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace_v1.data_team_a.metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

#---------------------------------------------------------------
# Example IAM policy for Spark job execution
#---------------------------------------------------------------
data "aws_iam_policy_document" "spark_operator" {
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::*"]

    actions = [
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
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

# ---------------------------------------------------------------
# Creates IAM policy for IRSA. Provides IAM permissions for Spark driver/executor pods
# ---------------------------------------------------------------
resource "aws_iam_policy" "spark" {
  description = "IAM role policy for Spark Job execution"
  name        = "${local.name}-spark-irsa"
  policy      = data.aws_iam_policy_document.spark_operator.json
}

# ---------------------------------------------------------------
# IRSA for Spark driver/executor pods for "data-team-a"
# ---------------------------------------------------------------
module "data_team_a_irsa" {
  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.0"

  #Disable helm release
  create_release = false

  #IAM role for service account (IRSA)
  create_role   = true
  role_name     = "${local.name}-${local.data_team}"
  create_policy = false
  role_policies = { data_team_a_policy = aws_iam_policy.spark.arn }

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = local.data_team
      service_account = local.data_team
    }
  }
}

#---------------------------------------------------------------
# Kubernetes Cluster role for argo workflows to run spark jobs
#---------------------------------------------------------------
resource "kubernetes_cluster_role" "spark_op_role" {
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
# Kubernetes Role binding for argo workflows/data-team-a
#---------------------------------------------------------------

# Allow argo-workflows to run spark application in data-team-a
resource "kubernetes_role_binding" "spark_role_binding" {
  metadata {
    name      = "data-team-a-spark-rolebinding"
    namespace = local.data_team
  }

  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = "argo-workflows"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.spark_op_role.id
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

# Grant data-team-a admin role
resource "kubernetes_role_binding" "admin_rolebinding_data_team_a" {
  metadata {
    name      = "data-team-a-admin-rolebinding"
    namespace = local.data_team
  }

  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = local.data_team
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "admin"
  }

  depends_on = [resource.kubernetes_namespace_v1.data_team_a]
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
