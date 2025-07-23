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

# # Récupération du securiy group
# data "aws_security_group" "default_vpc_sg" {
#   name   = "default"
#   vpc_id = local.vpc_id
# }

# Construction bucket
resource "aws_s3control_bucket" "this" {
  bucket     = local.bucket_name
  outpost_id = data.aws_outposts_outpost.default.id

  tags = var.tags
}

# # Construction endpoint --> Déclaré globalement
# resource "aws_s3outposts_endpoint" "testfab-ep" {
#   outpost_id        = data.aws_outposts_outpost.default.id 
#   security_group_id = data.aws_security_group.default_vpc_sg.id 
#   subnet_id         = local.outpost_subnet_id 
# }

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
# Ajout d'accès full pour éviter les pb ultérieurs (à hardener + tard)
# Pour l'instant en commentaire car par de policy sur les buckets normaux 
# et impossible d'appliquer tel quel (du moins sur la console)
# resource "aws_s3control_access_point_policy" "example" {
#   access_point_arn  = aws_s3_access_point.testfab-ap.arn
#   policy = jsonencode({
#     Id = "testBucketPolicy"
#     Statement = [
#       {
#         Sid      = "AllowAll"
#         Effect   = "Allow"
#         Principal = {
#           AWS = "*"
#         }
#         Action   = "s3-outposts:*"
#         Resource = ["*"]
#       }
#     ]
#     Version = "2012-10-17"
#   })
# }