locals {
  kuberay_operator_values = yamldecode(templatefile("${path.module}/helm-values/kuberay-operator.yaml", {})
  )
  s3_prefix        = "${local.name}/spark-application-logs/spark-team-a"
  iceberg_database = "raydata_spark_logs"
}

resource "kubectl_manifest" "kuberay_operator" {
  count = var.enable_raydata ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/kuberay-operator.yaml", {
    user_values_yaml = indent(8, yamlencode(local.kuberay_operator_values))
  })

  depends_on = [
    helm_release.argocd,
  ]
}

resource "aws_iam_policy" "raydata_iceberg" {
  count = var.enable_raydata ? 1 : 0

  name        = "${local.name}-raydata-iceberg-policy"
  description = "IAM policy for Ray Data to access S3 and Glue for Iceberg operations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = [
          "${module.s3_bucket.s3_bucket_arn}/${local.s3_prefix}*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload"
        ]
        Resource = [
          "${module.s3_bucket.s3_bucket_arn}/iceberg-warehouse/*"
        ]
      },
      # vLLM streams safetensors from models/ with the Run:ai Model Streamer.
      # ray-batch-inference/ holds mock input data and inference results.
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload"
        ]
        Resource = [
          "${module.s3_bucket.s3_bucket_arn}/models/*",
          "${module.s3_bucket.s3_bucket_arn}/ray-batch-inference/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          module.s3_bucket.s3_bucket_arn
        ]
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "${local.s3_prefix}*",
              "iceberg-warehouse/*",
              "models/*",
              "ray-batch-inference/*",
              trimsuffix(local.s3_prefix, "/")
            ]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          module.s3_bucket.s3_bucket_arn
        ]
        Condition = {
          StringEquals = {
            "s3:prefix" = [
              trimsuffix(local.s3_prefix, "/")
            ]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
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
        Resource = [
          "arn:aws:glue:${local.region}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${local.region}:${data.aws_caller_identity.current.account_id}:database/*",
          "arn:aws:glue:${local.region}:${data.aws_caller_identity.current.account_id}:table/*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "lakeformation:GetDataAccess"
        ]
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "raydata_iceberg" {
  count = var.enable_raydata ? 1 : 0

  role       = module.team_pod_identity["raydata"].iam_role_name
  policy_arn = aws_iam_policy.raydata_iceberg[0].arn

  depends_on = [module.team_pod_identity]
}

resource "aws_glue_catalog_database" "raydata_iceberg" {
  count = var.enable_raydata ? 1 : 0

  name        = local.iceberg_database
  description = "Database for storing processed Spark logs using Iceberg format"

  catalog_id = data.aws_caller_identity.current.account_id
}
