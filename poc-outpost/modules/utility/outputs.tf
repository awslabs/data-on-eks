output "karpenter_node_iam_role_name" {
  description = "The name of the IAM role created for Karpenter nodes"
  value       = module.karpenter.node_iam_role_name
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value        = aws_cognito_user_pool.main_pool.id
}

output "wildcard_certificate_arn" {
  description = "ARN of the wildcard ACM certificate"
  value       = aws_acm_certificate_validation.cert.certificate_arn
}