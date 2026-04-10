locals {
  nvidia_gpu_operator_values = yamldecode(templatefile("${path.module}/helm-values/nvidia-gpu-operator.yaml", {
  }))
}

resource "kubectl_manifest" "nvidia_gpu_operator" {
  count = var.enable_nvidia_gpu_operator ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/nvidia-gpu-operator.yaml", {
    user_values_yaml = indent(8, yamlencode(local.nvidia_gpu_operator_values))
  })

  depends_on = [
    helm_release.argocd,
  ]
}
