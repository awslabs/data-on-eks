locals {
  nvidia_device_plugin_values = yamldecode(templatefile("${path.module}/helm-values/nvidia-device-plugin.yaml", {
  }))
}

resource "kubectl_manifest" "nvidia_device_plugin" {
  count = var.enable_nvidia_device_plugin ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/nvidia-device-plugin.yaml", {
    user_values_yaml = indent(8, yamlencode(local.nvidia_device_plugin_values))
  })

  depends_on = [
    helm_release.argocd,
  ]
}
