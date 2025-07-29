output "karpenter_node_iam_role_name" {
  description = "The name of the IAM role created for Karpenter nodes"
  value       = module.karpenter.node_iam_role_name
}

output "karpenter_iam_role_arn" {
  description = "ARN of the IAM role created for Karpenter"
  value       = module.karpenter.node_iam_role_arn
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.main_pool.id
}


