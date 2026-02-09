locals {
  ingress_nginx_values = templatefile("${path.module}/helm-values/ingress-nginx.yaml", {
    enable_ipv6 = var.enable_ipv6
  })
}

#---------------------------------------------------------------
# Ingress Nginx Application
#---------------------------------------------------------------
resource "kubectl_manifest" "ingress_nginx" {
  count = var.enable_ingress_nginx ? 1 : 0
  yaml_body = templatefile("${path.module}/argocd-applications/ingress-nginx.yaml", {
    user_values_yaml = indent(8, local.ingress_nginx_values)
  })

  wait = true

  depends_on = [
    helm_release.argocd,
    kubectl_manifest.aws_load_balancer_controller
  ]
}
