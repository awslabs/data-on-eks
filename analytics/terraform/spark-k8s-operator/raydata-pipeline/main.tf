# =============================================================================
# Local Values
# =============================================================================

locals {
  # Resource naming with prefix (same as sparksense-ai)
  iam_role_name   = "${var.eks_cluster_name}-s3-access-role"
  iam_policy_name = "${var.eks_cluster_name}-s3-policy"

  # Merge default tags with provided tags
  common_tags = merge(
    {
      Module    = "ray-spark-log-processing-iceberg"
      Terraform = "true"
    },
    var.tags
  )

  # Ray configuration with defaults
  ray_config = merge(
    {
      batch_size      = "10000"
      min_workers     = "2"
      max_workers     = "10"
      initial_workers = "2"
    },
    var.ray_config
  )
}

# =============================================================================
# Data Sources
# =============================================================================

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Get EKS cluster information
data "aws_eks_cluster" "cluster" {
  name = var.eks_cluster_name
}

# Extract OIDC issuer ID
locals {
  oidc_issuer_url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
  oidc_issuer_id  = split("/", local.oidc_issuer_url)[4]
  account_id      = data.aws_caller_identity.current.account_id
}

# =============================================================================
# IAM Policy for S3 and Glue Access (for Iceberg)
# =============================================================================

data "aws_iam_policy_document" "s3_access" {
  # Allow reading Spark logs from S3
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion"
    ]
    resources = [
      "arn:aws:s3:::${var.s3_bucket}/${var.s3_prefix}*"
    ]
  }

  # Allow writing Iceberg data to S3
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload"
    ]
    resources = [
      "arn:aws:s3:::${var.s3_bucket}/iceberg-warehouse/*"
    ]
  }

  # Allow listing bucket with prefix restriction
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [
      "arn:aws:s3:::${var.s3_bucket}"
    ]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        "${var.s3_prefix}*",
        "iceberg-warehouse/*",
        trimsuffix(var.s3_prefix, "/")
      ]
    }
  }

  # Additional ListBucket permission for exact prefix match
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::${var.s3_bucket}"
    ]
    condition {
      test     = "StringEquals"
      variable = "s3:prefix"
      values = [
        trimsuffix(var.s3_prefix, "/")
      ]
    }
  }

  # AWS Glue permissions for Iceberg catalog
  statement {
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:CreateDatabase",
      "glue:GetTable",
      "glue:GetTables",
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:DeleteTable",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:CreatePartition",
      "glue:UpdatePartition",
      "glue:DeletePartition",
      "glue:BatchCreatePartition",
      "glue:BatchDeletePartition",
      "glue:BatchUpdatePartition"
    ]
    resources = [
      "arn:aws:glue:${var.aws_region}:${local.account_id}:catalog",
      "arn:aws:glue:${var.aws_region}:${local.account_id}:database/*",
      "arn:aws:glue:${var.aws_region}:${local.account_id}:table/*/*"
    ]
  }

  # Additional permissions for Iceberg operations
  statement {
    effect = "Allow"
    actions = [
      "lakeformation:GetDataAccess"
    ]
    resources = ["*"]
  }
}

# Create IAM policy with prefixed name
resource "aws_iam_policy" "s3_access" {
  name        = local.iam_policy_name
  description = "S3 and Glue access policy for Ray Spark log processing with Iceberg"
  policy      = data.aws_iam_policy_document.s3_access.json
  tags        = local.common_tags
}

# =============================================================================
# IAM Role for IRSA (IAM Roles for Service Accounts)
# =============================================================================

# Trust policy for IRSA
data "aws_iam_policy_document" "irsa_trust" {
  statement {
    effect = "Allow"
    principals {
      type = "Federated"
      identifiers = [
        "arn:aws:iam::${local.account_id}:oidc-provider/oidc.eks.${var.aws_region}.amazonaws.com/id/${local.oidc_issuer_id}"
      ]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "oidc.eks.${var.aws_region}.amazonaws.com/id/${local.oidc_issuer_id}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }
    condition {
      test     = "StringEquals"
      variable = "oidc.eks.${var.aws_region}.amazonaws.com/id/${local.oidc_issuer_id}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# Create IAM role with prefixed name
resource "aws_iam_role" "ray_s3_access" {
  name               = local.iam_role_name
  description        = "IAM role for Ray Spark log processing with Iceberg and IRSA"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust.json
  tags               = local.common_tags
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "ray_s3_access" {
  role       = aws_iam_role.ray_s3_access.name
  policy_arn = aws_iam_policy.s3_access.arn
}

# =============================================================================
# AWS Glue Database for Iceberg
# =============================================================================

resource "aws_glue_catalog_database" "raydata_iceberg" {
  name        = var.iceberg_database
  description = "Database for storing processed Spark logs using Iceberg format"

  catalog_id = local.account_id

  tags = local.common_tags
}

# =============================================================================
# Kubernetes Resources using kubectl provider
# =============================================================================

# Create namespace
resource "kubectl_manifest" "namespace" {
  yaml_body = <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: ${var.namespace}
  labels:
    name: ${var.namespace}
    purpose: spark-log-processing
    team: data-engineering
    module: ray-spark-log-processing
    app.kubernetes.io/managed-by: terraform
  annotations:
    description: "Namespace for Ray-based Spark log processing jobs with Iceberg"
    module: ray-spark-log-processing
YAML
}

# Create service account with IRSA annotation
resource "kubectl_manifest" "service_account" {
  yaml_body = <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${var.service_account_name}
  namespace: ${var.namespace}
  annotations:
    eks.amazonaws.com/role-arn: ${aws_iam_role.ray_s3_access.arn}
  labels:
    app.kubernetes.io/managed-by: terraform
    module: ray-spark-log-processing
YAML

  depends_on = [
    kubectl_manifest.namespace,
    aws_iam_role.ray_s3_access
  ]

  # Force replacement if IAM role changes
  force_new = true
}

# Create cluster role for Ray pods
resource "kubectl_manifest" "cluster_role" {
  yaml_body = <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ${var.eks_cluster_name}-cluster-role
  labels:
    app.kubernetes.io/managed-by: terraform
    module: ray-spark-log-processing
rules:
- apiGroups: [""]
  resources: ["pods", "services", "endpoints"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "list"]
YAML
}

# Create cluster role binding
resource "kubectl_manifest" "cluster_role_binding" {
  yaml_body = <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${var.eks_cluster_name}-cluster-role-binding
  labels:
    app.kubernetes.io/managed-by: terraform
    module: ray-spark-log-processing
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ${var.eks_cluster_name}-cluster-role
subjects:
- kind: ServiceAccount
  name: ${var.service_account_name}
  namespace: ${var.namespace}
YAML

  depends_on = [
    kubectl_manifest.cluster_role,
    kubectl_manifest.service_account
  ]
}
