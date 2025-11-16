#---------------------------------------------------------------
# S3 one zone express bucket for Spark Data
#---------------------------------------------------------------
resource "aws_s3_directory_bucket" "spark_data_bucket_express" {
  bucket        = "${local.name}-${local.account_id}--${local.s3_express_zone_id}--x-s3"
  force_destroy = true

  location {
    name = local.s3_express_zone_id
  }
}

#---------------------------------------------------------------
# S3 bucket for Spark Event Logs and Example Data
#---------------------------------------------------------------
#tfsec:ignore:*
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "4.11.0"

  bucket_prefix = "${local.name}-spark-logs-"

  # For example only - please evaluate for your environment
  force_destroy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}

# Creating an s3 bucket prefix. Ensure you copy Spark History event logs under this path to visualize the dags
resource "aws_s3_object" "this" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "spark-event-logs/"
  content_type = "application/x-directory"
}
