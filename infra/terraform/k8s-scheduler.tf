
locals {
  yunikorn_values = yamldecode(templatefile("${path.module}/helm-values/yunikorn.yaml", {
  }))
}

resource "kubectl_manifest" "yunikorn" {
  yaml_body = templatefile("${path.module}/argocd-applications/apache-yunikorn.yaml", {
    values = indent(8, yamlencode(local.yunikorn_values))
  })

  depends_on = [
    helm_release.argocd,
  ]
}
