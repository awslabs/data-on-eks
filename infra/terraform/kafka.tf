locals {
  strimzi_kafka_operator_values = templatefile("${path.module}/helm-values/strimzi-kafka-operator.yaml", {})
  kafka_manifests_base_path     = "${path.root}/../data-stacks/kafka-on-eks/kafka-cluster"
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
  yaml_body = templatefile("${local.kafka_manifests_base_path}/namespace.yaml", {})
}

#---------------------------------------------------------------
# Kafka Manifests
#---------------------------------------------------------------
resource "kubectl_manifest" "kafka_manifests" {
  for_each = fileset(local.kafka_manifests_base_path, "*.yaml")

  yaml_body = templatefile("${local.kafka_manifests_base_path}/${each.value}", {})

  depends_on = [
    kubectl_manifest.strimzi_kafka_operator,
    kubectl_manifest.kafka_namespace
  ]
}
