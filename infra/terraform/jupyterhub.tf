locals {
  jupyterhub_name            = "jupyterhub"
  jupyterhub_service_account = "${module.eks.cluster_name}-jupyterhub-single-user"

  jupyterhub_values = templatefile("${path.module}/helm-values/jupyterhub-single-user.yaml", {
    jupyter_single_user_sa_name = local.jupyterhub_service_account
  })
}

#---------------------------------------------------------------
# JupyterHub Application
#---------------------------------------------------------------
resource "kubectl_manifest" "jupyterhub" {
  count = var.enable_jupyterhub ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/jupyterhub.yaml", {
    user_values_yaml = indent(8, local.jupyterhub_values)
  })

  depends_on = [
    helm_release.argocd,
    module.jupyterhub_single_user_pod_identity,
    kubectl_manifest.jupyterhub_service_account
  ]
}

#-----------------------------------------------------------------------------------------
# JupyterHub Single User Pod Identity Configuration
#-----------------------------------------------------------------------------------------
resource "kubernetes_namespace" "jupyterhub" {
  count = var.enable_jupyterhub ? 1 : 0
  metadata {
    name = "jupyterhub"
  }
}

module "jupyterhub_single_user_pod_identity" {
  count   = var.enable_jupyterhub ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "jupyterhub-single-user"

  additional_policy_arns = {
    s3_readonly     = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
    spark_jobs      = aws_iam_policy.s3_write_jupyter[0].arn
    s3tables_policy = aws_iam_policy.s3tables.arn
    bedrock_policy  = aws_iam_policy.bedrock[0].arn
    glue_policy     = aws_iam_policy.glue_jupyter[0].arn
  }

  associations = {
    jupyterhub = {
      cluster_name    = module.eks.cluster_name
      namespace       = kubernetes_namespace.jupyterhub[0].metadata[0].name
      service_account = local.jupyterhub_service_account
    }
  }
}

resource "kubectl_manifest" "jupyterhub_service_account" {
  count = var.enable_jupyterhub ? 1 : 0

  yaml_body = templatefile("${path.module}/manifests/jupyterhub/sa.yaml", {
    service_account_name = local.jupyterhub_service_account
    namespace            = kubernetes_namespace.jupyterhub[0].metadata[0].name
  })

  depends_on = [
    kubernetes_namespace.jupyterhub,
    module.jupyterhub_single_user_pod_identity
  ]
}

#---------------------------------------------------------------------
# Example IAM policy for accessing S3 Iceberg files from JupyterHub
#---------------------------------------------------------------------

data "aws_iam_policy_document" "s3_write_jupyter" {
  count = var.enable_jupyterhub ? 1 : 0

  statement {
    sid    = "S3Access"
    effect = "Allow"
    resources = [
      module.s3_bucket.s3_bucket_arn,
      "${module.s3_bucket.s3_bucket_arn}/*"
    ]

    actions = [
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
    ]
  }
}

resource "aws_iam_policy" "s3_write_jupyter" {
  count       = var.enable_jupyterhub ? 1 : 0
  name_prefix = "${local.name}-spark-jobs-jupyter"
  path        = "/"
  description = "IAM policy for Spark job execution from JupyterHub"
  policy      = data.aws_iam_policy_document.s3_write_jupyter[0].json
  tags        = local.tags
}

#---------------------------------------------------------------------
# Example IAM policy for accessing Glue from JupyterHub
#---------------------------------------------------------------------

data "aws_iam_policy_document" "glue_jupyter" {
  count = var.enable_jupyterhub ? 1 : 0
  statement {
    sid       = "GlueAccess"
    effect    = "Allow"
    resources = ["*"]

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
  }
}

resource "aws_iam_policy" "glue_jupyter" {
  count       = var.enable_jupyterhub ? 1 : 0
  description = "IAM role policy for Glue access from JupyterHub pods"
  name_prefix = "${local.name}-glue-jupyter-pod-identity"
  policy      = data.aws_iam_policy_document.glue_jupyter[0].json
}

#---------------------------------------------------------------------
# Example IAM policy for accessing Bedrock Models from JupyterHub
# Please modify this policy according to your security requirements.
#---------------------------------------------------------------------
data "aws_iam_policy_document" "bedrock_jupyter" {
  count = var.enable_jupyterhub ? 1 : 0
  statement {
    sid    = "BedrockModelAccess"
    effect = "Allow"
    resources = [
      "arn:${data.aws_partition.current.partition}:bedrock:*::foundation-model/*",
      "arn:aws:bedrock:*:*:inference-profile/us.anthropic.claude-3-7-sonnet-20250219-v1:0",
      "arn:aws:bedrock:*:*:inference-profile/us.anthropic.claude-sonnet-4-20250514-v1:0"
    ]
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream"
    ]
  }

  statement {
    sid       = "BedrockModelDiscovery"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "bedrock:ListFoundationModels",
      "bedrock:GetFoundationModel"
    ]
  }
}

#---------------------------------------------------------------------
# Important prerequisite: Amazon Bedrock models must be enabled in the AWS console first.
# The IAM policy alone doesn't enable model access - you need to request access to models in the Bedrock console.
#---------------------------------------------------------------------
resource "aws_iam_policy" "bedrock" {
  count       = var.enable_jupyterhub ? 1 : 0
  description = "IAM role policy for Bedrock model access from JupyterHub pods"
  name_prefix = "${local.name}-bedrock-pod-identity"
  policy      = data.aws_iam_policy_document.bedrock_jupyter[0].json
}
