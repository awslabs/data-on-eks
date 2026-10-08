locals {
  local_static_provisioner_values = yamldecode(templatefile("${path.module}/helm-values/local-static-provisioner.yaml", {}))
}

resource "kubectl_manifest" "local_static_provisioner" {
  yaml_body = templatefile("${path.module}/argocd-applications/local-static-provisioner.yaml", {
    user_values_yaml = indent(8, yamlencode(local.local_static_provisioner_values))
  })

  depends_on = [
    helm_release.argocd,
  ]
}
