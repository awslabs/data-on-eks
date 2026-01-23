locals {
  pinot_namespace      = "pinot"
  pinot_serviceaccount = "pinot"
  pinot_values = templatefile("${path.module}/helm-values/pinot.yaml", {
    name            = local.name,
    s3_bucket       = module.data_bucket.s3_bucket_id,
    s3_region       = var.region,
    service_account = "pinot"
  })

  zookeeper_manifests = provider::kubernetes::manifest_decode_multi(
    templatefile("${path.module}/manifests/pinot/zookeeper.yaml", {
      namespace = local.pinot_namespace
    })
  )

  servicemonitor_manifests = provider::kubernetes::manifest_decode_multi(
    templatefile("${path.module}/manifests/pinot/servicemonitor.yaml", {
      namespace = local.pinot_namespace
    })
  )
}

#---------------------------------------------------------------
# Pinot Namespace
#---------------------------------------------------------------
resource "kubectl_manifest" "pinot_namespace" {
  count = var.enable_pinot ? 1 : 0

  yaml_body = templatefile("${path.module}/manifests/pinot/namespace.yaml", {
    namespace = local.pinot_namespace
  })
}

#---------------------------------------------------------------
# IAM Role for Pinot Service Account
#---------------------------------------------------------------
resource "aws_iam_policy" "pinot_s3" {
  count       = var.enable_pinot ? 1 : 0
  name        = "${var.name}-pinot-s3-access"
  description = "IAM policy for Pinot to access S3 DeepStore"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          module.data_bucket.s3_bucket_arn,
          "${module.data_bucket.s3_bucket_arn}/pinot/*"
        ]
      }
    ]
  })
}

resource "aws_eks_pod_identity_association" "pinot" {
  count = var.enable_pinot ? 1 : 0

  cluster_name    = module.eks.cluster_name
  namespace       = local.pinot_namespace
  service_account = local.pinot_serviceaccount
  role_arn        = aws_iam_role.pinot[0].arn
}

resource "aws_iam_role" "pinot" {
  count = var.enable_pinot ? 1 : 0
  name  = "${var.name}-pinot-pod-identity"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "pinot_s3" {
  count      = var.enable_pinot ? 1 : 0
  role       = aws_iam_role.pinot[0].name
  policy_arn = aws_iam_policy.pinot_s3[0].arn
}

#---------------------------------------------------------------
# Zookeeper StatefulSet
#---------------------------------------------------------------
resource "kubectl_manifest" "zookeeper" {
  for_each = { for idx, manifest in local.zookeeper_manifests : idx => manifest if var.enable_pinot }

  yaml_body = yamlencode(each.value)

  depends_on = [
    helm_release.argocd,
    kubectl_manifest.pinot_namespace
  ]
}

#---------------------------------------------------------------
# Pinot Application
#---------------------------------------------------------------
resource "kubectl_manifest" "pinot" {
  count = var.enable_pinot ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/pinot.yaml", {
    user_values_yaml = indent(8, local.pinot_values)
  })

  depends_on = [
    helm_release.argocd,
    kubectl_manifest.pinot_namespace,
    kubectl_manifest.zookeeper
  ]
}

#---------------------------------------------------------------
# ServiceMonitors for Prometheus
#---------------------------------------------------------------
resource "kubectl_manifest" "pinot_servicemonitor" {
  for_each = { for idx, manifest in local.servicemonitor_manifests : idx => manifest if var.enable_pinot }

  yaml_body = yamlencode(each.value)

  depends_on = [
    kubectl_manifest.pinot,
    kubectl_manifest.kube_prometheus_stack
  ]
}
