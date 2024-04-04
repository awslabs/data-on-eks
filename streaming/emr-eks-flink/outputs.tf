# create output for flink operator role arn
output "flink_jobs_role_arn" {
  value       = trimspace(module.flink_irsa_jobs.iam_role_arn)
  description = "IAM linked role for the flink job"
}
output "flink_operator_role_arn" {
  value       = module.flink_irsa_operator.iam_role_arn
  description = "IAM linked role for the flink operator"
}
