locals {
  argo_workflows_values = yamldecode(templatefile("${path.module}/helm-values/argo-workflows.yaml", {
  }))
}

resource "kubectl_manifest" "argo_workflows" {
  yaml_body = templatefile("${path.module}/argocd-applications/argo-workflows.yaml", {
    user_values_yaml = indent(10, yamlencode(local.argo_workflows_values))
  })

  depends_on = [
    helm_release.argocd,
  ]
}
