output "karpenter_node_iam_role_name" {
  description = "The name of the IAM role created for Karpenter nodes"
  value       = module.karpenter.node_iam_role_name
}