#---------------------------------------------------------------
# Apache Kafka lab — Strimzi Cluster Operator + tuned StorageClass
#---------------------------------------------------------------
# This file installs the two pieces of shared infrastructure that the Kafka
# lab depends on. The Kafka cluster itself is a `Kafka` custom resource that
# the participant applies during the lab (see `analytics/kafka/`), so broker
# capacity is only provisioned when someone actually runs the lab.
#
#   1. Strimzi Cluster Operator (Helm)        — watches the `kafka` namespace
#   2. `kafka-gp3` StorageClass                — tuned gp3 for broker PVs
#                                                (6000 IOPS / 500 MiB/s)
#
# The dedicated Kafka Karpenter NodePool lives in
# `manifests/automode/nodepool-kafka.yaml`; it is picked up automatically by
# the `auto_mode_nodepools` fileset() discovery in `eks.tf`, so it deploys
# regardless of `enable_kafka_lab` (an untainted NodePool with no matching
# pods is inert and costs nothing).
#
# Toggle the operator + StorageClass with `var.enable_kafka_lab` (default true).
#---------------------------------------------------------------

locals {
  kafka_lab = {
    namespace                    = "kafka"
    operator_version             = var.strimzi_operator_version
    storage_class_name           = "kafka-gp3"
    storage_class_iops           = 6000
    storage_class_throughput_mib = 1000
  }
}

resource "helm_release" "strimzi_kafka_operator" {
  count = var.enable_kafka_lab ? 1 : 0

  name             = "strimzi-kafka-operator"
  namespace        = local.kafka_lab.namespace
  create_namespace = true
  repository       = "https://strimzi.io/charts/"
  chart            = "strimzi-kafka-operator"
  version          = local.kafka_lab.operator_version
  timeout          = 600

  # The operator watches only the namespace it is deployed into by default,
  # which is where the participant deploys the Kafka custom resource.
  depends_on = [
    module.eks,
    kubectl_manifest.auto_mode_nodepools,
  ]
}

# Tuned gp3 StorageClass for Kafka broker/controller data volumes.
# The workshop's default `gp3` StorageClass uses gp3 defaults (3000 IOPS,
# 125 MiB/s per volume), which is well below what a real-shape broker
# wants. This class provisions gp3 at 6000 IOPS and 1000 MiB/s per volume
# — the gp3 throughput ceiling — matching AWS's Kafka-on-EBS guidance
# that Kafka is throughput-bound (sequential writes via the OS page cache)
# and that provisioned gp3 throughput should be set to unlock the target
# instance's EBS baseline. See the "Storage tiers" note in the lab README
# for st1 (cheap high-throughput HDD, data-volume only) and io2 Block
# Express (sub-ms latency, ~10x cost) upgrade paths.
resource "kubectl_manifest" "kafka_gp3_storageclass" {
  count = var.enable_kafka_lab ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = local.kafka_lab.storage_class_name
    }
    provisioner       = "ebs.csi.eks.amazonaws.com"
    volumeBindingMode = "WaitForFirstConsumer"
    reclaimPolicy     = "Delete"
    parameters = {
      type       = "gp3"
      fsType     = "xfs"
      encrypted  = "true"
      iops       = tostring(local.kafka_lab.storage_class_iops)
      throughput = tostring(local.kafka_lab.storage_class_throughput_mib)
    }
  })
  wait = true

  depends_on = [module.eks]
}
