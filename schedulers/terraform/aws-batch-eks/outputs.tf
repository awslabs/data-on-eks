output "configure_kubectl_cmd" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${var.aws_region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "aws_batch_ondemand_job_queue" {
  description = "The ARN of the created AWS Batch job queue to submit jobs to."
  value       = aws_batch_job_queue.doeks_ondemand_jq.name
}

output "aws_batch_spot_job_queue" {
  description = "The ARN of the created AWS Batch job queue to submit jobs to."
  value       = aws_batch_job_queue.doeks_spot_jq.name
}

output "run_example_aws_batch_job" {
  description = "Use the AWS CLI to submit the example Hello World AWS Batch job definition to the Spot job queue."
  value       = "JOB_ID=$(aws batch --region ${var.aws_region}  submit-job --job-definition ${aws_batch_job_definition.doeks_hello_world.arn} --job-queue ${aws_batch_job_queue.doeks_ondemand_jq.name} --job-name doeks_hello_example --output text --query jobId) && echo $JOB_ID"
}

output "run_example_aws_batch_job_on_spot" {
  description = "Use the AWS CLI to submit the example Hello World AWS Batch job definition to the Spot job queue."
  value       = "JOB_ID=$(aws batch --region ${var.aws_region}  submit-job --job-definition ${aws_batch_job_definition.doeks_hello_world.arn} --job-queue ${aws_batch_job_queue.doeks_spot_jq.name} --job-name doeks_hello_spot_example --output text --query jobId) && echo $JOB_ID"
}
