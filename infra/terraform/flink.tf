resource "kubectl_manifest" "flink_operator" {
    count = var.enable_flink ? 1 : 0
  yaml_body = templatefile("${path.module}/argocd-applications/flink-operator.yaml", {})

  depends_on = [
    helm_release.argocd,
  ]
}