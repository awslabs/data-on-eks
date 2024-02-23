output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${var.region} update-kubeconfig --name ${var.name}"
}

output "superset_url" {
  description = "Configure kubectl: Once the kubeconfig is configured as above, use the below command to get the Superset URL"
  value       = <<EOT
  kubectl get ingress  -n superset -o json | jq -r '"http://" + .items[0].status.loadBalancer.ingress[0].hostname'
  EOT
}

