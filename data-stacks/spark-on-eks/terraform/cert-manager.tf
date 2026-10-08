resource "kubectl_manifest" "cert_manager" {
  yaml_body = templatefile("${path.module}/argocd-applications/cert-manager.yaml", {})

  depends_on = [
    helm_release.argocd,
  ]
}
