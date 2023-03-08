
module "emr_on_eks" {
  source = "./emr-on-eks"

  for_each = var.emr_on_eks_config

  # Kubernetes Namespace + Role/Role Binding
  create_namespace       = try(each.value.create_namespace, true)
  namespace              = try(each.value.namespace, each.value.name, each.key)
  create_kubernetes_role = try(each.value.create_kubernetes_role, true)

  # Job Execution Role
  create_iam_role   = try(each.value.create_iam_role, true)
  oidc_provider_arn = var.eks_oidc_provider_arn

  role_name                     = try(each.value.execution_role_name, each.value.name, each.key)
  iam_role_use_name_prefix      = try(each.value.execution_iam_role_use_name_prefix, false)
  iam_role_path                 = try(each.value.execution_iam_role_path, null)
  iam_role_description          = try(each.value.execution_iam_role_description, null)
  iam_role_permissions_boundary = try(each.value.execution_iam_role_permissions_boundary, null)
  iam_role_additional_policies  = try(each.value.execution_iam_role_additional_policies, {})

  # Cloudwatch Log Group
  create_cloudwatch_log_group            = try(each.value.create_cloudwatch_log_group, true)
  cloudwatch_log_group_arn               = try(each.value.cloudwatch_log_group_arn, "arn:aws:logs:*:*:*")
  cloudwatch_log_group_retention_in_days = try(each.value.cloudwatch_log_group_retention_in_days, 7)
  cloudwatch_log_group_kms_key_id        = try(each.value.cloudwatch_log_group_kms_key_id, null)

  # EMR Virtual Cluster
  name           = try(each.value.name, each.key)
  eks_cluster_id = var.eks_cluster_id

  tags = merge(var.tags, try(each.value.tags, {}))
}
