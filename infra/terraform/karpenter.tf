
locals {
  karpenter_node_pools = {
    for f in fileset("${path.module}/manifests/karpenter", "nodepool*.yaml") :
    f => templatefile("${path.module}/manifests/karpenter/${f}", {
      CLUSTER_NAME                 = local.name
      KARPENTER_NODE_IAM_ROLE_NAME = module.karpenter.node_iam_role_name
    })
  }

  ec2nodeclass_manifests = provider::kubernetes::manifest_decode_multi(
    templatefile("${path.module}/manifests/karpenter/ec2nodeclass.yaml", {
      CLUSTER_NAME                 = local.name
      KARPENTER_NODE_IAM_ROLE_NAME = module.karpenter.node_iam_role_name
    })
  )
}

#---------------------------------------------------------------
# Controller & Node IAM roles, SQS Queue, Eventbridge Rules
#---------------------------------------------------------------

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = module.eks.cluster_name
  namespace    = "karpenter"

  # Name needs to match role name passed to the EC2NodeClass
  node_iam_role_use_name_prefix   = false
  node_iam_role_name              = "karpenter-doeks-${local.name}"
  create_pod_identity_association = true

  # Used to attach additional IAM policies to the Karpenter node IAM role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    S3TableAccess                = aws_iam_policy.s3tables_policy.arn
  }
}


resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = "karpenter"
  create_namespace = true
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "1.6.4"
  wait             = true

  values = [
    <<-EOT
    nodeSelector:
      NodeGroupType: 'core'
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
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

  depends_on = [module.karpenter]
}

resource "kubectl_manifest" "karpenter_resources" {
  for_each = local.karpenter_node_pools

  yaml_body = each.value

  depends_on = [
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "ec2nodeclass" {
  for_each = { for idx, manifest in local.ec2nodeclass_manifests : idx => manifest }

  yaml_body = yamlencode(each.value)
  wait      = true
  depends_on = [
    helm_release.karpenter
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
