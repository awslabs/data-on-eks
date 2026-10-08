#---------------------------------------------------------------
# Kyverno policy engine
#
# Admission-time mutation and validation for Kubernetes resources. Used by
# ray-history-server.tf to add the KubeRay History Server collector to every
# new RayCluster, so RayJobs, RayServices and RayClusters are archived to S3
# without each manifest opting in.
#
# Ref: https://kyverno.io/docs/
#---------------------------------------------------------------
resource "kubectl_manifest" "kyverno" {
  count = var.enable_kyverno ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/kyverno.yaml", {
    user_values_yaml = indent(8, yamlencode(yamldecode(templatefile("${path.module}/helm-values/kyverno.yaml", {}))))
  })

  depends_on = [
    helm_release.argocd,
  ]
}
