module "emr_containers" {
  source  = "terraform-aws-modules/emr/aws//modules/virtual-cluster"
  version = "~> 1.0"

  for_each = toset(["data-team-a", "data-team-b"])

  eks_cluster_id    = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn

  name      = "${module.eks.cluster_name}-emr-${each.value}"
  namespace = "emr-${each.value}"

  role_name                    = "${module.eks.cluster_name}-emr-${each.value}"
  iam_role_use_name_prefix     = false
  iam_role_description         = "EMR Execution Role for emr-${each.value}"
  iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"] # Attach additional policies for execution IAM Role

  tags = merge(local.tags, { Name = "emr-${each.value}" })
}
