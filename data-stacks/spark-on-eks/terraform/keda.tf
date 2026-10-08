#---------------------------------------------------------------
# KEDA Operator for Kubernetes Event-Driven Autoscaling
#
# KEDA enables scale-to-zero and Prometheus/event-based autoscaling
# for stateless workloads (e.g., StarRocks CN, Trino workers).
# It complements the standard HPA with richer triggers and activation.
#
# Deployed unconditionally as a shared infrastructure component —
# any data stack (StarRocks, Trino, etc.) can create ScaledObjects
# without re-installing the operator.
#
# Ref: https://keda.sh/docs/
#---------------------------------------------------------------
resource "kubectl_manifest" "keda_operator" {
  yaml_body = templatefile("${path.module}/argocd-applications/keda.yaml", {
    user_values_yaml = indent(8, yamlencode(yamldecode(templatefile("${path.module}/helm-values/keda.yaml", {}))))
  })

  depends_on = [
    helm_release.argocd,
  ]
}
