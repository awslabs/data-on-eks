locals {
  clickhouse_operator_values = templatefile("${path.module}/helm-values/clickhouse-operator.yaml", {})
}

resource "kubectl_manifest" "clickhouse_operator" {
  count = var.enable_clickhouse ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/clickhouse-operator.yaml", {
    user_values_yaml = indent(8, local.clickhouse_operator_values)
  })

  depends_on = [
    helm_release.argocd,
  ]
}
