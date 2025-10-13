locals {
  argo_events_values = yamldecode(templatefile("${path.module}/helm-values/argo-events.yaml", {
  }))
}

resource "kubectl_manifest" "argo_events" {
  yaml_body = templatefile("${path.module}/argocd-applications/argo-events.yaml", {
    user_values_yaml = indent(10, yamlencode(local.argo_events_values))
  })

  depends_on = [
    helm_release.argocd,
  ]
}