# =============================================================================
# AWS Distro for OpenTelemetry (ADOT)
# =============================================================================
# 1. ADOT EKS add-on (aws_eks_addon.adot in eks-addons.tf): installs the
#    OpenTelemetry operator (needs cert-manager).
# 2. An OpenTelemetryCollector (manifests/adot/adot-collector.yaml) that:
#    - scrapes Ray, kube-state-metrics, node-exporter, cAdvisor, DCGM and the
#      KubeRay operator and remote-writes them to Amazon Managed Prometheus,
#      so metrics outlive ephemeral RayClusters (view them in Grafana via the
#      "Amazon Managed Prometheus" datasource)
#    - receives OTLP traces and exports them to AWS X-Ray
#
# In-cluster Prometheus keeps running for live, short-term views.
# =============================================================================

locals {
  adot_namespace       = "adot-collector"
  adot_service_account = "adot-collector"

  adot_collector_template = "${path.module}/manifests/adot/adot-collector.yaml"
  adot_collector_template_vars = {
    namespace       = local.adot_namespace
    service_account = local.adot_service_account
    region          = local.region
    collector_image = "public.ecr.aws/aws-observability/aws-otel-collector:v0.50.0"
  }

  # for_each keys must be known at plan time, but the AMP endpoint and cluster
  # name are not on a fresh deploy. Derive the keys from a render with
  # placeholders and take each object's body from the real render.
  adot_collector_keys = var.enable_adot && var.enable_amazon_prometheus ? toset([
    for m in provider::kubernetes::manifest_decode_multi(templatefile(local.adot_collector_template,
      merge(local.adot_collector_template_vars, { cluster_name = "placeholder", amp_remote_write_url = "placeholder" })
    )) : "${m.kind}/${m.metadata.name}"
  ]) : toset([])

  adot_collector_manifests = {
    for m in provider::kubernetes::manifest_decode_multi(templatefile(local.adot_collector_template,
      merge(local.adot_collector_template_vars, {
        cluster_name         = module.eks.cluster_name
        amp_remote_write_url = try("${aws_prometheus_workspace.amp[0].prometheus_endpoint}api/v1/remote_write", "")
      })
    )) : "${m.kind}/${m.metadata.name}" => m if var.enable_adot && var.enable_amazon_prometheus
  }
}

#---------------------------------------------------------------
# ADOT Operator: EKS managed add-on in eks-addons.tf
#---------------------------------------------------------------
resource "terraform_data" "adot_requires_amp" {
  count = var.enable_adot ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.enable_amazon_prometheus
      error_message = "enable_adot requires enable_amazon_prometheus = true (the collector remote-writes to AMP)."
    }
  }
}

#---------------------------------------------------------------
# Pod Identity: AMP remote write + X-Ray
#---------------------------------------------------------------
module "adot_collector_pod_identity" {
  count   = var.enable_adot ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name = "${local.name}-adot-collector"

  additional_policy_arns = {
    amp_remote_write = "arn:${local.partition}:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
    xray_write       = "arn:${local.partition}:iam::aws:policy/AWSXrayWriteOnlyAccess"
  }

  associations = {
    adot_collector = {
      cluster_name    = module.eks.cluster_name
      namespace       = local.adot_namespace
      service_account = local.adot_service_account
    }
  }

  tags = local.tags
}

# Wait for the Pod Identity association to propagate to the EKS webhook before
# the collector pod is created, otherwise it can start without credentials
resource "time_sleep" "adot_collector_pod_identity" {
  count = var.enable_adot ? 1 : 0

  create_duration = "30s"

  depends_on = [module.adot_collector_pod_identity]
}

#---------------------------------------------------------------
# Collector
#---------------------------------------------------------------
resource "kubectl_manifest" "adot_collector_namespace" {
  for_each = toset([for k in local.adot_collector_keys : k if startswith(k, "Namespace/")])

  yaml_body = yamlencode(local.adot_collector_manifests[each.key])
}

resource "kubectl_manifest" "adot_collector" {
  for_each = toset([for k in local.adot_collector_keys : k if !startswith(k, "Namespace/")])

  yaml_body = yamlencode(local.adot_collector_manifests[each.key])

  depends_on = [
    aws_eks_addon.adot, # provides the OpenTelemetryCollector CRD
    kubectl_manifest.adot_collector_namespace,
    time_sleep.adot_collector_pod_identity,
  ]
}
