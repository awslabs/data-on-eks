

resource "aws_s3_bucket" "model_storage" {
  count         = var.create_s3_bucket ? 1 : 0
  bucket_prefix = "model-storage-"
}
