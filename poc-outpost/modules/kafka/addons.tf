resource "kubernetes_namespace" "kafka" {
  metadata {
    name = "kafka"
  }
}

#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "eks_data_addons" {
  source  = "aws-ia/eks-data-addons/aws"
  version = "1.34.0" # ensure to update this to the latest/desired version

  oidc_provider_arn = local.oidc_provider_arn
  #---------------------------------------------------------------
  # Strimzi Kafka Add-on
  #---------------------------------------------------------------
  enable_strimzi_kafka_operator = true
  strimzi_kafka_operator_helm_config = {
    values = [templatefile("${path.module}/helm-values/strimzi-kafka-values.yaml", {
      node_group_type  = "doeks"
    })],
    version = "0.43.0"
  }

  depends_on = [kubernetes_namespace.kafka]
}

# resource "kubernetes_manifest" "kafka-manifests" {
#   for_each = { for f in local.kafka_manifest_files : f => f }
#   manifest = yamldecode(file("${path.module}/kafka-manifests/${each.value}"))

#   depends_on = [module.eks_data_addons,
#     kubernetes_namespace.kafka]
# }

# resource "kubernetes_manifest" "monitoring-manifests" {
#   for_each = { for f in local.monitoring_manifest_files : f => f }
#   manifest = yamldecode(file("${path.module}/monitoring-manifests/${each.value}"))

#   depends_on = [kubernetes_manifest.kafka-manifests,
#       kubernetes_namespace.kafka]
# }

# Application des templates
# (on n'utilise pas kubernetes_manifest car dans le cas de CRD custom, la vérification fait que le tf script plante au premier lancement)
locals {
  kafka_manifests = {
    for file in local.kafka_manifest_files :
    trimsuffix(file, ".yaml") => yamldecode(file("${path.module}/kafka-manifests/${file}"))
  }
  monitoring_manifests = {
    for file in local.monitoring_manifest_files :
    trimsuffix(file, ".yaml") => yamldecode(file("${path.module}/monitoring-manifests/${file}"))
  }
   all_manifests = merge(local.kafka_manifests, local.monitoring_manifests)
}

resource "helm_release" "kafkamanifest" {
  name             = "kafkamanifest"
  namespace        = "kafka"
  create_namespace = false

  repository        = "https://bedag.github.io/helm-charts"
  chart             = "raw"
  version           = "2.0.0"
  dependency_update = true
  upgrade_install   = true
  wait              = true

  values = [
    yamlencode({
      resources = local.all_manifests
    })
  ]

  depends_on = [module.eks_data_addons]
}