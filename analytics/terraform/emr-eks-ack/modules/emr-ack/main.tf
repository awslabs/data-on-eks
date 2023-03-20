data "aws_region" "current" {}

locals {
  service = "emrcontainers"
  name    = "ack-emrcontainers-controller"
  region  = data.aws_region.current.name

  set_values = [
    {
      name  = "serviceAccount.name"
      value = local.name
    },
    {
      name  = "aws.region"
      value = local.region
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = module.emr_containers_irsa.iam_role_arn
    },
  ]
}

#---------------------------------------------------------------
# EMR on EKS ACK Addon
#---------------------------------------------------------------
resource "helm_release" "emr_containers" {
  name                = try(var.helm_config["name"], local.name)
  repository          = try(var.helm_config["repository"], "oci://public.ecr.aws/aws-controllers-k8s")
  chart               = try(var.helm_config["chart"], "${local.service}-chart")
  version             = try(var.helm_config["version"], "v1.0.0")
  namespace           = try(var.helm_config["namespace"], local.name)
  description         = try(var.helm_config["description"], "Helm Charts for the emr-containers controller for AWS Controllers for Kubernetes (ACK)")
  create_namespace    = try(var.helm_config["create_namespace"], true)
  repository_username = var.ecr_public_repository_username
  repository_password = var.ecr_public_repository_password
  timeout             = try(var.helm_config["timeout"], "300")

  values = try(var.helm_config["values"], [])

  dynamic "set" {
    iterator = each_item
    for_each = try(var.helm_config["set"], null) != null ? distinct(concat(local.set_values, var.helm_config["set"])) : local.set_values

    content {
      name  = each_item.value.name
      value = each_item.value.value
      type  = try(each_item.value.type, null)
    }
  }

  dynamic "set_sensitive" {
    iterator = each_item
    for_each = try(var.helm_config["set_sensitive"], [])

    content {
      name  = each_item.value.name
      value = each_item.value.value
      type  = try(each_item.value.type, null)
    }
  }
}

#---------------------------------------------------------------
# IRSA IAM policy for EMR Containers
#---------------------------------------------------------------
resource "aws_iam_policy" "emr_containers" {
  name_prefix = format("%s-%s", var.eks_cluster_id, "emr-ack")
  description = "IAM policy for EMR Containers controller"
  path        = "/"
  policy      = data.aws_iam_policy_document.emrcontainers.json
}

#---------------------------------------------------------------
# IRSA for EMR containers
#---------------------------------------------------------------
module "emr_containers_irsa" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "~> 5.14"
  role_name = format("%s-%s", var.eks_cluster_id, local.name)

  role_policy_arns = {
    policy = aws_iam_policy.emr_containers.arn
  }
  oidc_providers = {
    main = {
      provider_arn               = var.eks_oidc_provider_arn
      namespace_service_accounts = ["${local.name}:${local.name}"]
    }
  }
  tags = var.tags
}

# inline policy providered by ack https://raw.githubusercontent.com/aws-controllers-k8s/emrcontainers-controller/main/config/iam/recommended-inline-policy
data "aws_iam_policy_document" "emrcontainers" {
  statement {
    effect = "Allow"
    actions = [
      "iam:CreateServiceLinkedRole"
    ]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "iam:AWSServiceName"
      values   = ["emr-containers.amazonaws.com"]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "emr-containers:CreateVirtualCluster",
      "emr-containers:ListVirtualClusters",
      "emr-containers:DescribeVirtualCluster",
      "emr-containers:DeleteVirtualCluster"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "emr-containers:StartJobRun",
      "emr-containers:ListJobRuns",
      "emr-containers:DescribeJobRun",
      "emr-containers:CancelJobRun"
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "emr-containers:DescribeJobRun",
      "emr-containers:TagResource",
      "elasticmapreduce:CreatePersistentAppUI",
      "elasticmapreduce:DescribePersistentAppUI",
      "elasticmapreduce:GetPersistentAppUIPresignedURL"
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:Get*",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = ["*"]
  }
}
