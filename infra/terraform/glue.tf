# Need glue a database as a Iceberg Catalog until https://github.com/datahub-project/datahub/issues/14849 is addressed

#---------------------------------------------------------------
# Glue Database for Iceberg Tables
#---------------------------------------------------------------
resource "aws_glue_catalog_database" "data_on_eks" {
  name        = "data_on_eks"
  description = "Database for Data on EKS Iceberg tables"
}

#---------------------------------------------------------------
# IAM Role for Glue Crawler
#---------------------------------------------------------------
resource "aws_iam_role" "glue_crawler_role" {
  name = "${local.name}-glue-crawler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

#---------------------------------------------------------------
# IAM Policy for Glue Crawler S3 Access
#---------------------------------------------------------------
resource "aws_iam_policy" "glue_crawler_s3_policy" {
  name        = "${local.name}-glue-crawler-s3-policy"
  description = "IAM Policy for Glue Crawler S3 access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${module.s3_bucket.s3_bucket_arn}/iceberg-warehouse/*"
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceAccount" = local.account_id
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
      }
    ]
  })
}

#---------------------------------------------------------------
# Attach Policies to Glue Crawler Role
#---------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue_crawler_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "glue_crawler_s3_policy" {
  role       = aws_iam_role.glue_crawler_role.name
  policy_arn = aws_iam_policy.glue_crawler_s3_policy.arn
}

#---------------------------------------------------------------
# Glue Crawler for Iceberg Tables
#---------------------------------------------------------------
resource "aws_glue_crawler" "iceberg_crawler" {
  database_name = aws_glue_catalog_database.data_on_eks.name
  name          = "${local.name}-iceberg-crawler"
  role          = aws_iam_role.glue_crawler_role.arn

  iceberg_target {
    paths                   = ["s3://${module.s3_bucket.s3_bucket_id}/iceberg-warehouse/"]
    maximum_traversal_depth = 10
  }

  schedule = "cron(0 * * * ? *)" # Every hour

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }
}
