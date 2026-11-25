locals {
  spark_operator_values = yamldecode(templatefile("${path.module}/helm-values/spark-operator.yaml", {
    enable_ipv6 = var.enable_ipv6
  }))
}

resource "kubectl_manifest" "spark_operator" {
  yaml_body = templatefile("${path.module}/argocd-applications/spark-operator.yaml", {
    user_values_yaml = indent(8, yamlencode(local.spark_operator_values))
  })

  depends_on = [
    helm_release.argocd,
    module.spark_history_server_irsa,
    # The controller stops if the submitter is not ready within submitter.startupTimeout (5m).
    kubectl_manifest.spark_submitter,
  ]
}
