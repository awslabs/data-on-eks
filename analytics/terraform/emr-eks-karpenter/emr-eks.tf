# module "emr_containers" {
#   source = "./modules/emr-eks-containers"

#   eks_cluster_id        = data.aws_eks_cluster.cluster.name
#   eks_oidc_provider_arn = data.aws_iam_openid_connect_provider.eks_oidc.arn

#   emr_on_eks_config = {
#     # Example of all settings
#     emr-data-team-a = {
#       name = format("%s-%s", data.aws_eks_cluster.cluster.name, "emr-data-team-a")

#       create_namespace = true
#       namespace        = "emr-data-team-a"

#       execution_role_name                    = format("%s-%s", data.aws_eks_cluster.cluster.name, "emr-eks-data-team-a")
#       execution_iam_role_description         = "EMR Execution Role for emr-data-team-a"
#       execution_iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"] # Attach additional policies for execution IAM Role

#       tags = {
#         Name = "emr-data-team-a"
#       }
#     },

#     emr-data-team-b = {
#       name = format("%s-%s", data.aws_eks_cluster.cluster.name, "emr-data-team-b")

#       create_namespace = true
#       namespace        = "emr-data-team-b"

#       execution_role_name            = format("%s-%s", data.aws_eks_cluster.cluster.name, "emr-eks-data-team-b")
#       execution_iam_role_description = "EMR Execution Role for emr-data-team-b"
#       # Terraform apply throws an error for_each error if aws_iam_policy.this.arn is passed below hence the policy is hardcoded for testing purpose only. Users can create secured policies and apply terrafrom using -target
#       execution_iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"] # Attach additional policies for execution IAM Role

#       tags = {
#         Name = "emr-data-team-b"
#       }
#     }
#   }
# }

module "emr_containers" {
  source  = "terraform-aws-modules/emr/aws//modules/virtual-cluster"
  version = "~> 1.0"

  for_each = toset(["emr-data-team-a", "emr-data-team-b"])

  eks_cluster_id    = data.aws_eks_cluster.cluster.name
  oidc_provider_arn = data.aws_iam_openid_connect_provider.eks_oidc.arn

  name      = "${data.aws_eks_cluster.cluster.name}-${each.value}"
  namespace = "${each.value}"

  role_name                = "${data.aws_eks_cluster.cluster.name}-${each.value}"
  iam_role_use_name_prefix = false
  iam_role_description     = "EMR Execution Role for ${each.value}"
  # NOTE: S3 full access added only for testing purpose. You should modify this policy to restrict access to S3 buckets
  iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"]
  cloudwatch_log_group_name    = "/emr-on-eks-logs/${data.aws_eks_cluster.cluster.name}/${each.value}/"

  tags = merge(local.tags, { Name = "${each.value}" })
}


#---------------------------------------------------
# Supporting resources
#---------------------------------------------------
#tfsec:ignore:*
module "emr_s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket_prefix = "${local.name}-"
  # acl           = "private"

  # For example only - please evaluate for your environment
  force_destroy = true

  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}
