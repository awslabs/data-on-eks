locals {
  s3_express_supported_az_ids = [
    "use1-az4", "use1-az5", "use1-az6", "usw2-az1", "usw2-az3", "usw2-az4", "apne1-az1", "apne1-az4", "eun1-az1", "eun1-az2", "eun1-az3"
  ]

  s3_express_az_ids = [
    for az_id in data.aws_availability_zones.available.zone_ids :
    az_id if contains(local.s3_express_supported_az_ids, az_id)
  ]

  s3_express_azs = [for zone_id in local.s3_express_az_ids : [
    for az in data.aws_availability_zones.available.zone_ids :
    data.aws_availability_zones.available.names[index(data.aws_availability_zones.available.zone_ids, az)] if az == zone_id
  ][0]]

  s3_express_zone_id   = local.s3_express_az_ids[0]
  s3_express_zone_name = local.s3_express_azs[0]
}


#---------------------------------------------------------------
# S3 bucket for Spark Event Logs and Example Data
#---------------------------------------------------------------
#tfsec:ignore:*
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

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
}

# Creating an s3 bucket prefix. Ensure you copy Spark History event logs under this path to visualize the dags
resource "aws_s3_object" "this" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "spark-event-logs/"
  content_type = "application/x-directory"
}

resource "aws_s3_directory_bucket" "spark_data_bucket_express" {
  bucket        = "${local.name}-${local.account_id}--${local.s3_express_zone_id}--x-s3"
  force_destroy = true

  location {
    name = local.s3_express_zone_id
  }
}
