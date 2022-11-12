output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = module.eks_blueprints.configure_kubectl
}

output "eks_api_server_url" {
  description = "Your eks API server endpoint"
  value       = module.eks_blueprints.eks_cluster_endpoint
}

output "your_event_irsa_arn" {
  description = "the ARN of IRSA for argo events"
  value       = module.irsa_argo_events.irsa_iam_role_arn
}
