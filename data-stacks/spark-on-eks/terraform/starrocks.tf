locals {
  starrocks_namespace = "starrocks"
  starrocks_sa        = "starrocks-sa"
}

#---------------------------------------------------------------
# S3 Bucket for StarRocks Shared-Data Storage
#---------------------------------------------------------------
module "starrocks_s3_bucket" {
  count   = var.enable_starrocks ? 1 : 0
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.0"

  bucket_prefix = "${local.name}-starrocks-data-"
  force_destroy = true

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }
}

#---------------------------------------------------------------
# IAM Policy for StarRocks S3 Access
#---------------------------------------------------------------
data "aws_iam_policy_document" "starrocks_s3_access" {
  count = var.enable_starrocks ? 1 : 0

  statement {
    sid    = "StarRocksDataBucketAccess"
    effect = "Allow"
    resources = [
      "arn:aws:s3:::${module.starrocks_s3_bucket[0].s3_bucket_id}",
      "arn:aws:s3:::${module.starrocks_s3_bucket[0].s3_bucket_id}/*"
    ]
    actions = ["s3:Get*", "s3:List*", "s3:*Object*"]
  }

  statement {
    sid       = "StarRocksGeneralS3Access"
    effect    = "Allow"
    resources = ["*"]
    actions   = ["s3:ListAllMyBuckets", "s3:GetBucketLocation"]
  }
}

resource "aws_iam_policy" "starrocks_s3_policy" {
  count  = var.enable_starrocks ? 1 : 0
  name   = "${local.name}-starrocks-s3-policy"
  policy = data.aws_iam_policy_document.starrocks_s3_access[0].json
  tags   = local.tags
}

#---------------------------------------------------------------
# Pod Identity for StarRocks
#---------------------------------------------------------------
module "starrocks_pod_identity" {
  count   = var.enable_starrocks ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name = "starrocks"

  additional_policy_arns = {
    s3_policy = aws_iam_policy.starrocks_s3_policy[0].arn
  }

  associations = {
    starrocks = {
      cluster_name    = module.eks.cluster_name
      namespace       = local.starrocks_namespace
      service_account = local.starrocks_sa
    }
  }
}

#---------------------------------------------------------------
# StarRocks Operator via ArgoCD
#---------------------------------------------------------------
resource "kubectl_manifest" "starrocks_operator" {
  count = var.enable_starrocks ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/starrocks-operator.yaml", {
    user_values_yaml = indent(8, yamlencode(yamldecode(templatefile("${path.module}/helm-values/starrocks-operator.yaml", {
      starrocks_sa = local.starrocks_sa
      irsa_arn     = module.starrocks_pod_identity[0].iam_role_arn
    }))))
  })

  depends_on = [
    helm_release.argocd,
    module.starrocks_pod_identity,
    module.starrocks_s3_bucket
  ]
}

#---------------------------------------------------------------
# gp3-starrocks StorageClass
#---------------------------------------------------------------
resource "kubectl_manifest" "starrocks_storageclass" {
  count     = var.enable_starrocks ? 1 : 0
  yaml_body = templatefile("${path.module}/manifests/starrocks/storageclass.yaml", {})

  depends_on = [
    kubectl_manifest.starrocks_operator
  ]
}

#---------------------------------------------------------------
# Prometheus PodMonitors for StarRocks metrics
# Scrapes FE (port 8030), BE (port 8040), CN (port 8040)
# Automatically extracts cluster name from operator labels
#---------------------------------------------------------------
locals {
  starrocks_pod_monitors = var.enable_starrocks ? provider::kubernetes::manifest_decode_multi(
    file("${path.module}/manifests/starrocks/pod-monitors.yaml")
  ) : []
}

resource "kubectl_manifest" "starrocks_pod_monitors" {
  for_each = { for idx, manifest in local.starrocks_pod_monitors : idx => manifest }

  yaml_body = yamlencode(each.value)

  depends_on = [
    kubectl_manifest.starrocks_operator
  ]
}

#---------------------------------------------------------------
# KEDA ScaledObject for CN Autoscaling (Shared-Data, Optional)
#
# Scales CN nodes based on StarRocks query rate from Prometheus.
# Supports scale-to-zero during idle periods.
#
# NOTE: When this ScaledObject is active, the StarRocksCluster CR
# MUST NOT set `replicas` under `starRocksCnSpec`. KEDA/HPA manages
# the replica count. If `replicas` is set, there will be a conflict.
#
# Deploys automatically when var.enable_starrocks = true.
#---------------------------------------------------------------
resource "kubectl_manifest" "starrocks_cn_keda_scaledobject" {
  count = var.enable_starrocks ? 1 : 0

  yaml_body = templatefile("${path.module}/manifests/starrocks/cn-keda-scaledobject.yaml", {
    starrocks_namespace = local.starrocks_namespace
    prometheus_url      = "http://prometheus-prometheus.monitoring:9090"
  })

  depends_on = [
    kubectl_manifest.starrocks_operator,
    kubectl_manifest.keda_operator
  ]
}

#---------------------------------------------------------------
# Outputs
#---------------------------------------------------------------
output "starrocks_s3_bucket_id" {
  description = "StarRocks S3 data bucket ID"
  value       = var.enable_starrocks ? module.starrocks_s3_bucket[0].s3_bucket_id : ""
}
