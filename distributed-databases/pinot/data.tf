data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_availability_zones" "available" {}

data "aws_partition" "current" {}

# data "aws_iam_policy_document" "fluent_bit" {
#   statement {
#     sid       = ""
#     effect    = "Allow"
#     resources = ["arn:${data.aws_partition.current.partition}:s3:::${module.s3_bucket.s3_bucket_id}/*"]

#     actions = [
#       "s3:ListBucket",
#       "s3:PutObject",
#       "s3:PutObjectAcl",
#       "s3:GetObject",
#       "s3:GetObjectAcl",
#       "s3:DeleteObject",
#       "s3:DeleteObjectVersion"
#     ]
#   }
# }
