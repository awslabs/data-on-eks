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

#---------------------------------------------------------------
# Kafka Namespace
#---------------------------------------------------------------
resource "kubectl_manifest" "kafka_namespace" {
  yaml_body = templatefile("${path.module}/manifests/kafka/namespace.yaml", {})
}

#---------------------------------------------------------------
# Kafka Manifests
#---------------------------------------------------------------
resource "kubectl_manifest" "kafka_manifests" {
  for_each = fileset("${path.module}/manifests/kafka", "*.yaml")

  yaml_body = templatefile("${path.module}/manifests/kafka/${each.value}", {})

  depends_on = [
    kubectl_manifest.strimzi_kafka_operator,
    kubectl_manifest.kafka_namespace
  ]
}
