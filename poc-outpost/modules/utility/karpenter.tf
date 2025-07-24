module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.24"

  cluster_name          = local.name
  enable_v1_permissions = true

  enable_pod_identity             = true
  create_pod_identity_association = true

  # Used to attach additional IAM policies to the Karpenter node IAM role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags
}

# Deploy Karpenter using Helm
resource "helm_release" "karpenter" {
  namespace  = "kube-system"
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  repository_username = local.repository_username
  repository_password = local.repository_password
  chart      = "karpenter"
  version    = "1.5.0"
  wait       = false

  values = [
    <<-EOT
    serviceAccount:
      name: ${module.karpenter.service_account}
    settings:
      clusterName: ${local.name}
      clusterEndpoint: ${local.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
      - key: karpenter.sh/controller
        operator: Exists
        effect: NoSchedule
    webhook:
      enabled: false
    EOT
  ]

  # lifecycle {
  #   ignore_changes = [
  #     repository_password
  #   ]
  # }

  depends_on = [
    module.karpenter
  ]
}

#---------------------------------------------------------------
# S3Table IAM policy for Karpenter nodes
# The S3 tables library does not fully support IRSA and Pod Identity as of this writing.
# We give the node role access to S3tables to work around this limitation.
#---------------------------------------------------------------
resource "aws_iam_policy" "s3tables_policy" {
  name_prefix = "${local.name}-s3tables"
  path        = "/"
  description = "S3Tables Metadata access for Nodes"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VisualEditor0"
        Effect = "Allow"
        Action = [
          "s3tables:UpdateTableMetadataLocation",
          "s3tables:GetNamespace",
          "s3tables:ListTableBuckets",
          "s3tables:ListNamespaces",
          "s3tables:GetTableBucket",
          "s3tables:GetTableBucketMaintenanceConfiguration",
          "s3tables:GetTableBucketPolicy",
          "s3tables:CreateNamespace",
          "s3tables:CreateTable"
        ]
        Resource = "arn:aws:s3tables:*:${data.aws_caller_identity.current.account_id}:bucket/*"
      },
      {
        Sid    = "VisualEditor1"
        Effect = "Allow"
        Action = [
          "s3tables:GetTableMaintenanceJobStatus",
          "s3tables:GetTablePolicy",
          "s3tables:GetTable",
          "s3tables:GetTableMetadataLocation",
          "s3tables:UpdateTableMetadataLocation",
          "s3tables:GetTableData",
          "s3tables:GetTableMaintenanceConfiguration"
        ]
        Resource = "arn:aws:s3tables:*:${data.aws_caller_identity.current.account_id}:bucket/*/table/*"
      }
    ]
  })
}
