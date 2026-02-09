locals {
  flink_operator_values = yamldecode(templatefile("${path.module}/helm-values/flink-operator.yaml", {
  }))
}

resource "kubectl_manifest" "flink_operator" {
  count = var.enable_emr_on_eks ? 0 : 1

  yaml_body = templatefile("${path.module}/argocd-applications/flink-operator.yaml", {
    user_values_yaml = indent(10, yamlencode(local.flink_operator_values))
  })

  depends_on = [
    helm_release.argocd,
  ]
}
