# =============================================================================
# KubeRay History Server
# =============================================================================
# Post-mortem Ray Dashboard for RayClusters/RayJobs that have been deleted.
#
# 1. Ray pods opt in with spec.historyServerOptions.collectorOptions; the
#    KubeRay operator (RayClusterHistoryServer feature gate, see
#    helm-values/kuberay-operator.yaml) injects a collector sidecar that uploads
#    logs and Ray events to s3://<spark-logs bucket>/ray-history/.
#    The collector runs as the Ray pod's service account (raydata), which
#    already has read/write on this bucket via the spark_jobs policy.
# 2. The history server reads that prefix (read-only Pod Identity role) and
#    serves the Ray Dashboard API; ray-history-dashboard provides the UI.
#
# Stores logs, events, tasks, actors, jobs and Ray Data/Serve state.
# It does NOT store Prometheus metrics; those go to AMP via ADOT (adot.tf).
# =============================================================================

locals {
  ray_history_server_namespace       = "ray-history-server"
  ray_history_server_service_account = "ray-history-server"
  ray_history_server_root_dir        = "ray-history"
  ray_history_server_version         = "v1.7.1"
  ray_history_collector_image        = "quay.io/kuberay/collector:${local.ray_history_server_version}"

  ray_history_server_template = "${path.module}/manifests/ray-history-server/ray-history-server.yaml"
  ray_history_server_template_vars = {
    namespace           = local.ray_history_server_namespace
    service_account     = local.ray_history_server_service_account
    storage_root_dir    = local.ray_history_server_root_dir
    region              = local.region
    historyserver_image = "quay.io/kuberay/historyserver:${local.ray_history_server_version}"
    ray_image           = "rayproject/ray:2.56.0-py312"
  }

  # for_each keys must be known at plan time, but the bucket name is not on a
  # fresh deploy. Derive the keys from a render with a placeholder bucket and
  # take each object's body from the real render.
  ray_history_server_keys = var.enable_ray_history_server ? toset([
    for m in provider::kubernetes::manifest_decode_multi(templatefile(local.ray_history_server_template,
      merge(local.ray_history_server_template_vars, { s3_bucket = "placeholder" })
    )) : "${m.kind}/${m.metadata.name}"
  ]) : toset([])

  ray_history_server_manifests = {
    for m in provider::kubernetes::manifest_decode_multi(templatefile(local.ray_history_server_template,
      merge(local.ray_history_server_template_vars, { s3_bucket = module.s3_bucket.s3_bucket_id })
    )) : "${m.kind}/${m.metadata.name}" => m if var.enable_ray_history_server
  }
}

#---------------------------------------------------------------
# IAM: read-only access to the history prefix
#---------------------------------------------------------------
resource "aws_iam_policy" "ray_history_server_s3" {
  count = var.enable_ray_history_server ? 1 : 0

  name        = "${local.name}-ray-history-server-s3"
  description = "Read-only access for the KubeRay History Server to Ray logs and events in S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${module.s3_bucket.s3_bucket_arn}/${local.ray_history_server_root_dir}/*"]
      },
      {
        # HeadBucket needs an unconditioned s3:ListBucket: the server probes the
        # bucket at startup and exits on AccessDenied. A prefix condition would
        # block that call, so this role can list (not read) keys bucket-wide.
        # Use a dedicated bucket if key names outside ray-history/ are sensitive.
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [module.s3_bucket.s3_bucket_arn]
      }
    ]
  })

  tags = local.tags
}

module "ray_history_server_pod_identity" {
  count   = var.enable_ray_history_server ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name = "${local.name}-ray-history-server"

  additional_policy_arns = {
    s3_read = aws_iam_policy.ray_history_server_s3[0].arn
  }

  associations = {
    ray_history_server = {
      cluster_name    = module.eks.cluster_name
      namespace       = local.ray_history_server_namespace
      service_account = local.ray_history_server_service_account
    }
  }

  tags = local.tags
}

# The EKS Pod Identity webhook only injects credentials into pods created after
# it sees the association, which is eventually consistent. Without this wait the
# history server pod can start without credentials (NoCredentialProviders).
resource "time_sleep" "ray_history_server_pod_identity" {
  count = var.enable_ray_history_server ? 1 : 0

  create_duration = "30s"

  depends_on = [module.ray_history_server_pod_identity]
}

#---------------------------------------------------------------
# History Server, UI and RBAC
#---------------------------------------------------------------
resource "kubectl_manifest" "ray_history_server_namespace" {
  for_each = toset([for k in local.ray_history_server_keys : k if startswith(k, "Namespace/")])

  yaml_body = yamlencode(local.ray_history_server_manifests[each.key])

  lifecycle {
    precondition {
      condition     = var.enable_raydata
      error_message = "enable_ray_history_server requires enable_raydata = true (KubeRay operator)."
    }
  }
}

resource "kubectl_manifest" "ray_history_server" {
  for_each = toset([for k in local.ray_history_server_keys : k if !startswith(k, "Namespace/")])

  yaml_body = yamlencode(local.ray_history_server_manifests[each.key])

  depends_on = [
    kubectl_manifest.ray_history_server_namespace,
    kubectl_manifest.kuberay_operator,
    time_sleep.ray_history_server_pod_identity,
  ]
}
