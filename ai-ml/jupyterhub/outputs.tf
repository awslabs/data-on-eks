output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile  and run the following command to update your kubeconfig"
  value       = "aws eks --region ${var.region} update-kubeconfig --name ${var.name}"
}

# output "notebook_url" {
#   # namespace       =  data.kubernetes_service.elb.metadata[0].namespace
#   value        =  "Update DNS CNAME record value for your domain -${data.kubernetes_service.elb.status[0].load_balancer[0].ingress[0].hostname}"
#   description = "JupyterHub url"
# }

