
locals {
  # Pinned AMI for all EC2NodeClasses. With "@latest", Karpenter replaces nodes (drift)
  # each time AWS releases a new AMI, also during a load test.
  # The release must match the cluster Kubernetes version (var.eks_cluster_version).
  # To update: change the version between tests. Karpenter then replaces all nodes.
  # Find the latest release:
  #   aws ssm get-parameter --name /aws/service/eks/optimized-ami/<k8s-version>/amazon-linux-2023/x86_64/standard/recommended/image_id
  #   (then describe-images; the version is the "-vYYYYMMDD" suffix of the AMI name)
  karpenter_ami_alias = "al2023@v20260930"

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
      # Used by the spark-operator EC2NodeClass to select the primary CIDR subnets.
      REGION    = local.region
      AMI_ALIAS = local.karpenter_ami_alias
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
    CniIpv6Policy                = aws_iam_policy.cni_ipv6_policy.arn
    EbsVolumeManagement          = aws_iam_policy.karpenter_ebs_volume_policy.arn
  }
  enable_inline_policy = true
}


resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = "karpenter"
  create_namespace = true
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "1.14.0"
  wait             = true

  values = [
    <<-EOT
    nodeSelector:
      NodeGroupType: 'core'
    replicas: 2
    controller:
      resources:
        requests:
          cpu: "8"
          memory: 32Gi
        limits:
          cpu: "8"
          memory: 32Gi
    # Required: never put two Karpenter replicas on the same node.
    # Also keep Karpenter off nodes that Karpenter manages (same as the chart default).
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: karpenter.sh/nodepool
                  operator: DoesNotExist
      podAntiAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          - topologyKey: kubernetes.io/hostname
            labelSelector:
              matchLabels:
                app.kubernetes.io/name: karpenter
                app.kubernetes.io/instance: karpenter
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
  wait      = true

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

#---------------------------------------------------------------
# EBS Volume Management Policy for Karpenter Nodes
# Required for EC2NodeClass userData scripts that dynamically
# create and attach EBS volumes (e.g. emr-pcp-benchmark /data1 shuffle dir)
#---------------------------------------------------------------
resource "aws_iam_policy" "karpenter_ebs_volume_policy" {
  name_prefix = "${local.name}-karpenter-ebs-vol"
  path        = "/"
  description = "Allow Karpenter nodes to create/attach EBS volumes via userData scripts"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EbsVolumeOperations"
        Effect = "Allow"
        Action = [
          "ec2:CreateVolume",
          "ec2:AttachVolume",
          "ec2:DeleteVolume",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumeStatus",
          "ec2:ModifyInstanceAttribute",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}
