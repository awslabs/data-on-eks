locals {
  overlayfolder = var.overlayfolder
  helminstallname = var.helminstallname
  namespace = var.namespace
  createnamespace = var.createnamespace

  manifests = [
    for m in data.kustomization_build.this.manifests :
    yamldecode(m)
  ]
}

## Resolution
data "kustomization_build" "this" {
  path = local.overlayfolder
}

resource "kubernetes_namespace_v1" "this" {
  provider = kubernetes
  count = local.createnamespace ? 1 : 0

  metadata {
    name = local.namespace
    labels = {
      istio-injection = "enabled"
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/enforce-version" = "latest"
    }
  }
}

resource "helm_release" "this" {
  provider = helm
  name             = local.helminstallname
  namespace        = local.namespace
  create_namespace = false

  repository        = "https://bedag.github.io/helm-charts"
  chart             = "raw"
  version           = "2.0.0"
  dependency_update = true
  upgrade_install   = true
  wait              = true

  values = [
    yamlencode({
      resources = local.manifests
    })
  ]

  depends_on = [kubernetes_namespace_v1.this]
}