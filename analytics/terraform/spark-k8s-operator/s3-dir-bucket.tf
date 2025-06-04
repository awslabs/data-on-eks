resource "aws_s3_directory_bucket" "spark_data_bucket_express" {
  bucket        = "${local.name}-${local.account_id}--${local.s3_express_zone_id}--x-s3"
  force_destroy = true

  location {
    name = local.s3_express_zone_id
  }
}
