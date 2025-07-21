

locals {
  name   = var.name
  region = var.region
  cluster_version = var.cluster_version
  cluster_endpoint = var.cluster_endpoint
  oidc_provider_arn = var.oidc_provider_arn
  karpenter_node_iam_role_name = var.karpenter_node_iam_role_name

  kafka_manifest_files = fileset("${path.module}/kafka-manifests", "*.yaml")
  monitoring_manifest_files = fileset("${path.module}/monitoring-manifests", "*.yaml")

  tags = var.tags
}

