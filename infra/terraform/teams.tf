locals {
  teams = {
    spark-team-a = {
      name                = "spark-team-a"
      namespace           = "spark-team-a"
      service_account     = "spark-team-a"
      iam_policy_arns     = [aws_iam_policy.spark_jobs.arn, aws_iam_policy.s3tables_policy.arn]
      additional_policies = {}
      tags = merge(local.tags, {
        Team = "spark-team-a"
      })
    }
    spark-team-b = {
      name                = "spark-team-b"
      namespace           = "spark-team-b"
      service_account     = "spark-team-b"
      iam_policy_arns     = [aws_iam_policy.spark_jobs.arn, aws_iam_policy.s3tables_policy.arn]
      additional_policies = {}
      tags = merge(local.tags, {
        Team = "spark-team-b"
      })
    }
    spark-team-c = {
      name                = "spark-team-c"
      namespace           = "spark-team-c"
      service_account     = "spark-team-c"
      iam_policy_arns     = [aws_iam_policy.spark_jobs.arn, aws_iam_policy.s3tables_policy.arn]
      additional_policies = {}
      tags = merge(local.tags, {
        Team = "spark-team-c"
      })
    }
    spark-s3-express = {
      name                = "spark-s3-express"
      namespace           = "spark-s3-express"
      service_account     = "spark-s3-express"
      iam_policy_arns     = [aws_iam_policy.spark_jobs.arn, aws_iam_policy.s3tables_policy.arn]
      additional_policies = {}
      tags = merge(local.tags, {
        Team = "spark-s3-express"
      })
    }
    flink-team-a = {
      name                = "flink-team-a"
      namespace           = "flink-team-a"
      service_account     = "flink-team-a"
      iam_policy_arns     = [aws_iam_policy.flink_jobs.arn]
      additional_policies = {}
      tags = merge(local.tags, {
        Team = "flink-team-a"
      })
    }
    raydata = {
      name                = "raydata"
      namespace           = "raydata"
      service_account     = "raydata"
      iam_policy_arns     = [aws_iam_policy.spark_jobs.arn, aws_iam_policy.s3tables_policy.arn]
      additional_policies = {}
      tags = merge(local.tags, {
        Team = "raydata"
      })
    }
  }
}

#---------------------------------------------------------------
# Pod Identity for Teams
#---------------------------------------------------------------
module "team_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"
  
  for_each = local.teams

  name = each.value.name

  additional_policy_arns = merge(
    { for idx, arn in each.value.iam_policy_arns : "policy_${idx}" => arn },
    each.value.additional_policies
  )

  associations = {
    team = {
      cluster_name    = module.eks.cluster_name
      namespace       = each.value.namespace
      service_account = each.value.service_account
    }
  }

  tags = each.value.tags
}

#---------------------------------------------------------------
# Kubernetes Resources for Teams
#---------------------------------------------------------------
resource "kubectl_manifest" "team_namespaces" {
  for_each = local.teams

  yaml_body = templatefile("${path.module}/manifests/teams/namespace.yaml", {
    namespace = each.value.namespace
    team_name = each.value.name
  })
}

resource "kubectl_manifest" "team_service_accounts" {
  for_each = local.teams

  yaml_body = templatefile("${path.module}/manifests/teams/service-account.yaml", {
    service_account = each.value.service_account
    namespace       = each.value.namespace
    team_name       = each.value.name
  })

  depends_on = [
    kubectl_manifest.team_namespaces,
    module.team_pod_identity
  ]
}

resource "kubectl_manifest" "team_cluster_role" {
  yaml_body = file("${path.module}/manifests/teams/cluster-role.yaml")
}

resource "kubectl_manifest" "team_cluster_role_bindings" {
  for_each = local.teams

  yaml_body = templatefile("${path.module}/manifests/teams/cluster-role-binding.yaml", {
    team_name       = each.value.name
    service_account = each.value.service_account
    namespace       = each.value.namespace
  })

  depends_on = [
    kubectl_manifest.team_namespaces,
    kubectl_manifest.team_cluster_role,
    kubectl_manifest.team_service_accounts
  ]
}

data "aws_iam_policy_document" "s3tables_policy" {
  version = "2012-10-17"

  statement {
    sid    = "VisualEditor0"
    effect = "Allow"

    actions = [
      "s3tables:CreateTableBucket",
      "s3tables:ListTables",
      "s3tables:CreateTable",
      "s3tables:GetNamespace",
      "s3tables:DeleteTableBucket",
      "s3tables:CreateNamespace",
      "s3tables:ListNamespaces",
      "s3tables:ListTableBuckets",
      "s3tables:GetTableBucket",
      "s3tables:DeleteNamespace",
      "s3tables:GetTableBucketMaintenanceConfiguration",
      "s3tables:PutTableBucketMaintenanceConfiguration",
      "s3tables:GetTableBucketPolicy"
    ]

    resources = ["arn:aws:s3tables:*:${data.aws_caller_identity.current.account_id}:bucket/*"]
  }

  statement {
    sid    = "VisualEditor1"
    effect = "Allow"

    actions = [
      "s3tables:GetTableMaintenanceJobStatus",
      "s3tables:GetTablePolicy",
      "s3tables:GetTable",
      "s3tables:GetTableMetadataLocation",
      "s3tables:UpdateTableMetadataLocation",
      "s3tables:DeleteTable",
      "s3tables:PutTableData",
      "s3tables:RenameTable",
      "s3tables:PutTableMaintenanceConfiguration",
      "s3tables:GetTableData",
      "s3tables:GetTableMaintenanceConfiguration"
    ]

    resources = ["arn:aws:s3tables:*:${data.aws_caller_identity.current.account_id}:bucket/*/table/*"]
  }

  statement {
    sid    = "VisualEditor2"
    effect = "Allow"

    actions = ["s3tables:ListTableBuckets"]

    resources = ["*"]
  }
}

data "aws_iam_policy_document" "spark_jobs" {
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

  statement {
    sid       = "CloudWatchLogsAccess"
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:logs:${local.region}:${local.account_id}:log-group:*"]

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
  }

  statement {
    sid       = "ECRAccess"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetAuthorizationToken",
    ]
  }
}

resource "aws_iam_policy" "spark_jobs" {
  name_prefix = "${local.name}-spark-jobs"
  path        = "/"
  description = "IAM policy for Spark job execution"
  policy      = data.aws_iam_policy_document.spark_jobs.json
  tags        = local.tags
}

data "aws_iam_policy_document" "flink_jobs" {
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

  statement {
    sid       = "CloudWatchLogsAccess"
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:logs:${local.region}:${local.account_id}:log-group:*"]

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
  }

  statement {
    sid       = "ECRAccess"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetAuthorizationToken",
    ]
  }

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

resource "aws_iam_policy" "flink_jobs" {
  name_prefix = "${local.name}-flink-jobs"
  description = "IAM policy for Flink job execution"
  policy      = data.aws_iam_policy_document.flink_jobs.json
  tags        = local.tags
}

resource "aws_iam_policy" "s3tables" {
  description = "IAM role policy for S3 Tables Access from Spark Job execution"
  name_prefix = "${local.name}-spark-jobs-s3tables"
  policy      = data.aws_iam_policy_document.s3tables_policy.json
}

#---------------------------------------------------------------
# Flink-specific RBAC
#---------------------------------------------------------------
resource "kubectl_manifest" "flink_role" {
  yaml_body = templatefile("${path.module}/manifests/flink/role.yaml", {
    team_name = "flink-team-a"
    namespace = "flink-team-a"
  })

  depends_on = [kubectl_manifest.team_namespaces]
}

resource "kubectl_manifest" "flink_rolebinding" {
  yaml_body = templatefile("${path.module}/manifests/flink/rolebinding.yaml", {
    team_name       = "flink-team-a"
    namespace       = "flink-team-a"
    service_account = "flink-team-a"
  })

  depends_on = [
    kubectl_manifest.team_service_accounts,
    kubectl_manifest.flink_role
  ]
}
