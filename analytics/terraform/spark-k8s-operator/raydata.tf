# =============================================================================
# Ray Data Spark Log Processing
# =============================================================================
# This file contains Ray Data specific configurations that extend the base
# spark-team infrastructure for processing Spark logs.
# =============================================================================

# Only create these resources if Ray Data processing is enabled
resource "aws_iam_policy" "raydata_iceberg" {
  count = var.enable_raydata ? 1 : 0

  name        = "${local.name}-raydata-iceberg-policy"
  description = "IAM policy for Ray Data to access S3 and Glue for Iceberg operations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Allow reading Spark logs from S3
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
      # Allow writing Iceberg data to S3
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
      # Allow listing bucket with prefix restriction
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
              trimsuffix(local.s3_prefix, "/")
            ]
          }
        }
      },
      # Additional ListBucket permission for exact prefix match
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
      # AWS Glue permissions for Iceberg catalog
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
      # Additional permissions for Iceberg operations
      {
        Effect = "Allow"
        Action = [
          "lakeformation:GetDataAccess"
        ]
        Resource = ["*"]
      }
    ]
  })

  tags = local.tags
}

# Attach the Iceberg policy to the raydata team's IAM role
resource "aws_iam_role_policy_attachment" "raydata_iceberg" {
  count = var.enable_raydata ? 1 : 0

  role       = module.spark_team_irsa["raydata"].iam_role_name
  policy_arn = aws_iam_policy.raydata_iceberg[0].arn

  depends_on = [module.spark_team_irsa]
}

# AWS Glue Database for Iceberg
resource "aws_glue_catalog_database" "raydata_iceberg" {
  count = var.enable_raydata ? 1 : 0

  name        = local.iceberg_database
  description = "Database for storing processed Spark logs using Iceberg format"

  catalog_id = data.aws_caller_identity.current.account_id

  tags = local.tags
}
