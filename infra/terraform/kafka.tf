locals {
  strimzi_kafka_operator_values = templatefile("${path.module}/helm-values/strimzi-kafka-operator.yaml", {})
}

resource "kubectl_manifest" "strimzi_kafka_operator" {
  yaml_body = templatefile("${path.module}/argocd-applications/strimzi-kafka-operator.yaml", {
    user_values_yaml = indent(10, local.strimzi_kafka_operator_values)
  })

  depends_on = [
    helm_release.argocd,
  ]
}
