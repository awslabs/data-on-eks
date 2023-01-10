data "aws_eks_cluster_auth" "this" {
  name = module.eks_blueprints.eks_cluster_id
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

data "aws_availability_zones" "available" {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_iam_policy_document" "emr_on_eks" {
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

# emr-studio virtual cluster execution role
data "aws_iam_role" "emr-studio-role" {
  name = format("%s-%s", var.name, "emr-eks-studio")

  depends_on = [
    module.eks_blueprints
  ]
}

# emr studio role, based on https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-studio-service-role.html
data "aws_iam_policy_document" "emr_on_eks_emrstudio" {
  statement {
    sid    = "AllowEMRReadOnlyActions"
    effect = "Allow"

    actions = [
      "elasticmapreduce:ListInstances",
      "elasticmapreduce:DescribeCluster",
      "elasticmapreduce:ListSteps"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowEC2ENIActionsWithEMRTags"
    effect = "Allow"

    actions = [
      "ec2:CreateNetworkInterfacePermission",
      "ec2:DeleteNetworkInterface"
    ]

    resources = [
      "arn:aws:ec2:*:*:network-interface/*"
    ]

  }

  statement {
    sid    = "AllowEC2ENIAttributeAction"
    effect = "Allow"

    actions = [
      "ec2:ModifyNetworkInterfaceAttribute"
    ]

    resources = ["arn:aws:ec2:*:*:instance/*",
      "arn:aws:ec2:*:*:network-interface/*",
    "arn:aws:ec2:*:*:security-group/*"]
  }

  statement {
    sid    = "AllowEC2SecurityGroupActionsWithEMRTags"
    effect = "Allow"

    actions = [
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:DeleteNetworkInterfacePermission"
    ]

    resources = [
      "*"
    ]

  }


  statement {
    sid    = "AllowDefaultEC2SecurityGroupsCreationWithEMRTags"
    effect = "Allow"

    actions = [
      "ec2:CreateSecurityGroup"
    ]

    resources = [
      "arn:aws:ec2:*:*:security-group/*"
    ]

  }

  statement {
    sid    = "AllowDefaultEC2SecurityGroupsCreationInVPCWithEMRTags"
    effect = "Allow"

    actions = [
      "ec2:CreateSecurityGroup"
    ]

    resources = [
      "arn:aws:ec2:*:*:vpc/*"
    ]

  }

  statement {
    sid    = "AllowAddingEMRTagsDuringDefaultSecurityGroupCreation"
    effect = "Allow"

    actions = [
      "ec2:CreateTags"
    ]

    resources = [
      "arn:aws:ec2:*:*:security-group/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateSecurityGroup"]
    }
  }

  statement {
    sid    = "AllowEC2ENICreationWithEMRTags"
    effect = "Allow"

    actions = [
      "ec2:CreateNetworkInterface"
    ]

    resources = [
      "arn:aws:ec2:*:*:network-interface/*"
    ]

  }

  statement {
    sid    = "AllowEC2ENICreationInSubnetAndSecurityGroupWithEMRTags"
    effect = "Allow"

    actions = [
      "ec2:CreateNetworkInterface"
    ]

    resources = [
      "arn:aws:ec2:*:*:subnet/*",
      "arn:aws:ec2:*:*:security-group/*"
    ]

  }

  statement {
    sid    = "AllowAddingTagsDuringEC2ENICreation"
    effect = "Allow"

    actions = [
      "ec2:CreateTags"
    ]

    resources = [
      "arn:aws:ec2:*:*:network-interface/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateNetworkInterface"]
    }
  }

  statement {
    sid    = "AllowSecretsManagerReadOnlyActionsWithEMRTags"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue"
    ]

    resources = [
      "arn:aws:secretsmanager:*:*:secret:*"
    ]

  }

  statement {
    sid    = "AllowEC2ReadOnlyActions"
    effect = "Allow"

    actions = [
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:DescribeInstances",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowWorkspaceCollaboration"
    effect = "Allow"

    actions = [
      "iam:GetUser",
      "iam:GetRole",
      "iam:ListUsers",
      "iam:ListRoles",
      "sso:GetManagedApplicationInstance",
      "sso-directory:SearchUsers"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowAccessToS3BucketEncryptionKey"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:ReEncrypt",
      "kms:DescribeKey"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowEMRStudioAccesstoS3BucketforStudioWorkspaces"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetEncryptionConfiguration",
      "s3:ListBucket",
      "s3:DeleteObject"
    ]

    resources = ["*"]
  }
}

data "aws_iam_policy_document" "emr_studio_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["elasticmapreduce.amazonaws.com"]
    }

  }
}
