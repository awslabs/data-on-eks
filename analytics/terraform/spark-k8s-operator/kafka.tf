#---------------------------------------------------------------
# Apache Kafka on EKS - Strimzi Cluster Operator
#---------------------------------------------------------------
# Installs the Strimzi Cluster Operator only. The Kafka cluster
# (Kafka + KafkaNodePool custom resources) is deployed by the
# participant during the lab from analytics/kafka/kafka-cluster.yaml,
# so broker nodes are only provisioned when the lab is actually run.
#
# Strimzi 1.1.0 supports Apache Kafka 4.3.0 and only the v1 CRD API.
# Reference: https://strimzi.io/
#---------------------------------------------------------------

resource "helm_release" "strimzi_kafka_operator" {
  count = var.enable_kafka ? 1 : 0

  name             = "strimzi-kafka-operator"
  namespace        = "kafka"
  create_namespace = true
  repository       = "https://strimzi.io/charts/"
  chart            = "strimzi-kafka-operator"
  version          = var.strimzi_operator_version
  timeout          = 600

  # By default the operator watches the namespace it is deployed into ("kafka"),
  # which is where the lab deploys the Kafka custom resource. No extra config needed.

  depends_on = [module.eks, kubectl_manifest.auto_mode_nodepools]
}
