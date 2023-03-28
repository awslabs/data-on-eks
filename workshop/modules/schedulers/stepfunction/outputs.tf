#-----------------------------------------------------------
# Step Function Arn
#-----------------------------------------------------------
output "step_function_arn" {
  description = "ARN of the Step Function"
  value       = module.step-functions.state_machine_arn
}

output "step_function_iam_role_arn" {
  description = "The role arn of the Step Function"
  value       = module.step-functions.role_arn
}
