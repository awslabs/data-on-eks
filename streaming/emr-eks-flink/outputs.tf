# create output for flink operator role arn
output "flink_operator_role_arn" {
  value       = module.flink_irsa.iam_role_arn
  description = "IAM linked role for the flink operator"
}
