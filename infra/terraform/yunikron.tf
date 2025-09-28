
locals {
  yunikorn_values = yamldecode(templatefile("${path.module}/helm-values/yunikorn.yaml", {
  }))
}

resource "kubectl_manifest" "yunikorn" {
  #   count = var.enable_yunikorn ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/apache-yunikorn.yaml", {
    values = indent(8, yamlencode(local.yunikorn_values))
  })
}
