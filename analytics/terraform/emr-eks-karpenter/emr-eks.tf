module "emr_containers" {
  source  = "terraform-aws-modules/emr/aws//modules/virtual-cluster"
  version = "2.4.2"

  for_each = toset(["data-team-a", "data-team-b"])

  eks_cluster_id    = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn

  name      = "${module.eks.cluster_name}-emr-${each.value}"
  namespace = "emr-${each.value}"

  role_name = "${module.eks.cluster_name}-emr-${each.value}"

  s3_bucket_arns = [
    "arn:aws:s3:::/${module.s3_bucket.s3_bucket_id}",
    "arn:aws:s3:::/${module.s3_bucket.s3_bucket_id}/*",
  ]

  iam_role_use_name_prefix = false
  iam_role_description     = "EMR Execution Role for emr-${each.value}"
  # NOTE: S3 full access added only for testing purpose. You should modify this policy to restrict access to S3 buckets
  iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"]
  cloudwatch_log_group_name    = "/emr-on-eks-logs/${module.eks.cluster_name}/emr-${each.value}/"

  tags = merge(local.tags, { Name = "emr-${each.value}" })
}
