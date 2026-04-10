locals {
  kube_prometheus_values = templatefile("${path.module}/helm-values/kube-prometheus.yaml", {
    # Add template variables if needed for AMP integration
    region              = local.region
    amp_sa              = local.amp_ingest_service_account
    amp_remotewrite_url = var.enable_amazon_prometheus ? "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}/api/v1/remote_write" : ""
    amp_url             = var.enable_amazon_prometheus ? "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}" : ""
  })
}

#---------------------------------------------------------------
# Grafana Admin Password
#---------------------------------------------------------------
resource "random_password" "grafana" {
  length  = 16
  special = true
}

#---------------------------------------------------------------
# Namespace for kube-prometheus-stack
#---------------------------------------------------------------
resource "kubectl_manifest" "kube_prometheus_stack_namespace" {
  yaml_body = file("${path.module}/manifests/kube-prometheus-stack/kube-prometheus-stack-namespace.yaml")
}

#---------------------------------------------------------------
# Kubernetes Secret for Grafana Admin
#---------------------------------------------------------------
resource "kubernetes_secret" "grafana_admin" {
  metadata {
    name      = "grafana-admin-secret"
    namespace = "kube-prometheus-stack"
  }

  data = {
    admin-user     = "admin"
    admin-password = random_password.grafana.result
  }

  depends_on = [kubectl_manifest.kube_prometheus_stack_namespace]
}

#---------------------------------------------------------------
# Kube Prometheus Stack Application
#---------------------------------------------------------------
resource "kubectl_manifest" "kube_prometheus_stack" {
  yaml_body = templatefile("${path.module}/argocd-applications/kube-prometheus-stack.yaml", {
    user_values_yaml = indent(8, local.kube_prometheus_values)
  })

  depends_on = [
    helm_release.argocd,
    module.amp_ingest_pod_identity
  ]
}
