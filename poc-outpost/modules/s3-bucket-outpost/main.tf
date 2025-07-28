locals {
    outpost_name = var.outpost_name
    bucket_name = var.bucket_name
    vpc-id = var.vpc-id
    outpost_subnet_id = var.output_subnet_id
    vpc_id = var.vpc_id

}

# Récupération outpost
data "aws_outposts_outpost" "default" {
  name = var.outpost_name
}

# Construction bucket
resource "aws_s3control_bucket" "this" {
  bucket     = local.bucket_name
  outpost_id = data.aws_outposts_outpost.default.id

  tags = var.tags
}

# Construction access point
# Utilisation de aws_s3_access_point.this.alias pour référencer l'accès
resource "aws_s3_access_point" "this" {
  bucket = aws_s3control_bucket.this.arn
  name = "${local.bucket_name}-ap"

  # VPC must be specified for S3 on Outposts
  vpc_configuration {
    vpc_id = local.vpc-id
  }

}

