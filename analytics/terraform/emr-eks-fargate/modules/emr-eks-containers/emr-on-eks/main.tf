data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

locals {
  account_id         = data.aws_caller_identity.current.account_id
  internal_role_name = try(coalesce(var.role_name, var.name), "")
  namespace          = var.create_namespace ? kubernetes_namespace_v1.this[0].metadata[0].name : var.namespace
  emr_service_name   = "emr-containers"
}

#-----------------------------------------------------------
# Kubernetes Namespace + Role/Role Binding
#-----------------------------------------------------------
resource "kubernetes_namespace_v1" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

resource "kubernetes_role_v1" "this" {
  count = var.create_kubernetes_role ? 1 : 0

  metadata {
    name      = local.emr_service_name
    namespace = local.namespace
  }

  rule {
    verbs      = ["get"]
    api_groups = [""]
    resources  = ["namespaces"]
  }

  rule {
    verbs      = ["get", "list", "watch", "describe", "create", "edit", "delete", "deletecollection", "annotate", "patch", "label"]
    api_groups = [""]
    resources  = ["serviceaccounts", "services", "configmaps", "events", "pods", "pods/log"]
  }

  rule {
    verbs      = ["create", "delete", "deletecollection", "get", "list", "patch", "update", "watch"]
    api_groups = [""]
    resources  = ["persistentvolumeclaims"]
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
    api_groups = ["batch"]
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
}

resource "kubernetes_role_binding_v1" "this" {
  metadata {
    name      = local.emr_service_name
    namespace = local.namespace
  }

  subject {
    kind      = "User"
    name      = local.emr_service_name
    api_group = "rbac.authorization.k8s.io"
  }

  role_ref {
    kind      = "Role"
    name      = local.emr_service_name
    api_group = "rbac.authorization.k8s.io"
  }
}

#-----------------------------------------------------------
# EMR on EKS Job Execution Role
#-----------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  count = var.create_iam_role ? 1 : 0

  statement {
    sid     = "EMR"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["elasticmapreduce.${data.aws_partition.current.dns_suffix}"]
    }
  }

  statement {
    sid     = "IRSA"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringLike"
      variable = "${replace(var.oidc_provider_arn, "/^(.*provider/)/", "")}:sub"
      # Terraform lacks support for a base32 function and role names with prefixes are unknown so a wildcard is used
      values = ["system:serviceaccount:${local.namespace}:emr-containers-sa-*-*-${local.account_id}-*"]
    }

    # https://aws.amazon.com/premiumsupport/knowledge-center/eks-troubleshoot-oidc-and-irsa/?nc1=h_ls
    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_arn, "/^(.*provider/)/", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "this" {
  count = var.create_iam_role ? 1 : 0

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:PutLogEvents",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = var.create_cloudwatch_log_group ? ["${aws_cloudwatch_log_group.this[0].arn}:log-stream:*"] : ["${var.cloudwatch_log_group_arn}:log-stream:*"]
  }

  statement {
    sid    = "CloudWatchLogsReadOnly"
    effect = "Allow"
    actions = [
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "this" {
  count = var.create_iam_role ? 1 : 0

  name        = var.iam_role_use_name_prefix ? null : local.internal_role_name
  name_prefix = var.iam_role_use_name_prefix ? "${local.internal_role_name}-" : null
  path        = var.iam_role_path
  description = coalesce(var.iam_role_description, "Job execution role for EMR on EKS ${var.name} virtual cluster")

  assume_role_policy    = data.aws_iam_policy_document.assume[0].json
  permissions_boundary  = var.iam_role_permissions_boundary
  force_detach_policies = true

  tags = var.tags
}

resource "aws_iam_policy" "this" {
  count = var.create_iam_role ? 1 : 0

  name        = var.iam_role_use_name_prefix ? null : local.internal_role_name
  name_prefix = var.iam_role_use_name_prefix ? "${local.internal_role_name}-" : null
  path        = var.iam_role_path
  description = coalesce(var.iam_role_description, "Job execution role policy for EMR on EKS ${var.name} virtual cluster")

  policy = data.aws_iam_policy_document.this[0].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  count = var.create_iam_role ? 1 : 0

  policy_arn = aws_iam_policy.this[0].arn
  role       = aws_iam_role.this[0].name
}

resource "aws_iam_role_policy_attachment" "additional" {
  for_each = { for k, v in var.iam_role_additional_policies : k => v if var.create_iam_role }

  policy_arn = each.value
  role       = aws_iam_role.this[0].name
}

#-----------------------------------------------------------
# Cloudwatch Log Group
#-----------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  count = var.create_cloudwatch_log_group ? 1 : 0

  name              = "/emr-on-eks-logs/${var.eks_cluster_id}/${local.namespace}"
  retention_in_days = var.cloudwatch_log_group_retention_in_days
  kms_key_id        = var.cloudwatch_log_group_kms_key_id

  tags = var.tags
}

#-----------------------------------------------------------
# EMR Virtual Cluster
#-----------------------------------------------------------
resource "aws_emrcontainers_virtual_cluster" "this" {
  name = var.name

  container_provider {
    id   = var.eks_cluster_id
    type = "EKS"

    info {
      eks_info {
        namespace = local.namespace
      }
    }
  }

  tags = var.tags
}
