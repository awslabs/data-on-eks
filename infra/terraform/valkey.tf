# =============================================================================
# Valkey on EKS
#
# Deploys Valkey (Redis fork) in replication mode (1 primary + N replicas)
# via the OFFICIAL valkey-io/valkey-helm chart. Cluster mode (sharded with
# gossip) is on the chart roadmap as valkey-helm issue #18 and will be
# adopted here when it ships.
#
# Single Terraform variable: `var.enable_valkey`. All per-deployment
# configuration lives in `helm-values/valkey.yaml`. AWS-side resources
# (S3 migration bucket, IAM policy, Pod Identity for the restore
# initContainer) are always provisioned when `enable_valkey = true`, so
# users can flip `restore.enabled` in helm-values without re-running
# Terraform.
#
# Out of v1 scope: scheduled backup CronJob. Document as a follow-up — the
# S3 bucket + Pod Identity created here are the foundation a CronJob would
# attach to.
# =============================================================================

locals {
  valkey_namespace       = "valkey"
  valkey_service_account = "valkey-sa"

  # Render helm-values/valkey.yaml once. Only namespace, service account,
  # and region are injected by Terraform — every other knob is plain Helm
  # values that users edit in the file directly.
  valkey_values_rendered = templatefile("${path.module}/helm-values/valkey.yaml", {
    namespace            = local.valkey_namespace
    service_account_name = local.valkey_service_account
    region               = local.region
  })
}

#---------------------------------------------------------------
# Valkey Namespace
#---------------------------------------------------------------
resource "kubectl_manifest" "valkey_namespace" {
  count = var.enable_valkey ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: ${local.valkey_namespace}
      labels:
        name: ${local.valkey_namespace}
  YAML

  depends_on = [module.eks]
}

#---------------------------------------------------------------
# AUTH passwords — generated once, stored in a Kubernetes Secret. The chart
# reads them via `auth.usersExistingSecret` keyed by ACL username, so the
# secret holds both the application user (`default`) and the user replicas
# use to authenticate to the primary (`replication-user`).
#
# Password literals never appear in helm-values/valkey.yaml.
#---------------------------------------------------------------
resource "random_password" "valkey_default_user" {
  count = var.enable_valkey ? 1 : 0

  length  = 32
  special = false
}

resource "random_password" "valkey_replication_user" {
  count = var.enable_valkey ? 1 : 0

  length  = 32
  special = false
}

resource "kubernetes_secret" "valkey_auth" {
  count = var.enable_valkey ? 1 : 0

  metadata {
    name      = "valkey-auth"
    namespace = local.valkey_namespace
  }

  data = {
    "default"          = random_password.valkey_default_user[0].result
    "replication-user" = random_password.valkey_replication_user[0].result
  }

  type = "Opaque"

  depends_on = [kubectl_manifest.valkey_namespace]
}

#---------------------------------------------------------------
# Migration S3 bucket — source for the restore initContainer when migrating
# Valkey/Redis state from EC2 into EKS. The pre-migration script
# (data-stacks/valkey-on-eks/examples/migration/ec2-bgsave-to-s3.sh) writes
# `dump.rdb` here; the restore initContainer reads from here on first boot.
#---------------------------------------------------------------
resource "aws_s3_bucket" "valkey_migration" {
  count = var.enable_valkey ? 1 : 0

  bucket = "${var.name}-valkey-migration-${data.aws_caller_identity.current.account_id}"

  tags = {
    deployment_id = var.deployment_id
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "valkey_migration" {
  count = var.enable_valkey ? 1 : 0

  bucket = aws_s3_bucket.valkey_migration[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "valkey_migration" {
  count = var.enable_valkey ? 1 : 0

  bucket = aws_s3_bucket.valkey_migration[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "valkey_migration" {
  count = var.enable_valkey ? 1 : 0

  bucket = aws_s3_bucket.valkey_migration[0].id

  versioning_configuration {
    status = "Disabled"
  }
}

#---------------------------------------------------------------
# IAM policy — restore initContainer reads RDB snapshots from the migration
# bucket. Read-only.
#---------------------------------------------------------------
resource "aws_iam_policy" "valkey_restore_s3" {
  count = var.enable_valkey ? 1 : 0

  name        = "${var.name}-valkey-restore-s3"
  description = "Allow Valkey restore initContainer to read RDB snapshots from S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Resource = [
          aws_s3_bucket.valkey_migration[0].arn,
          "${aws_s3_bucket.valkey_migration[0].arn}/*",
        ]
      },
    ]
  })

  tags = {
    deployment_id = var.deployment_id
  }
}

#---------------------------------------------------------------
# Pod Identity — associates the Valkey StatefulSet ServiceAccount
# (valkey-sa) with the restore IAM policy. The restore initContainer runs
# in the same pod and inherits this association.
#---------------------------------------------------------------
module "valkey_restore_pod_identity" {
  count = var.enable_valkey ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name = "valkey-restore"

  additional_policy_arns = {
    s3 = aws_iam_policy.valkey_restore_s3[0].arn
  }

  associations = {
    restore = {
      cluster_name    = module.eks.cluster_name
      namespace       = local.valkey_namespace
      service_account = local.valkey_service_account
    }
  }
}

#---------------------------------------------------------------
# Valkey ArgoCD Application — official valkey-io/valkey-helm chart, pinned
# version, with the rendered helm-values injected into the spec.
#---------------------------------------------------------------
resource "kubectl_manifest" "valkey" {
  count = var.enable_valkey ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/valkey.yaml", {
    user_values_yaml = indent(8, local.valkey_values_rendered)
  })

  depends_on = [
    helm_release.argocd,
    module.valkey_restore_pod_identity,
    aws_s3_bucket.valkey_migration,
    kubernetes_secret.valkey_auth,
    kubectl_manifest.valkey_namespace,
  ]
}

#---------------------------------------------------------------
# Outputs
#---------------------------------------------------------------
output "valkey_migration_bucket" {
  description = "S3 bucket used as the source for the Valkey restore initContainer (EC2-to-EKS migration). Empty when enable_valkey is false."
  value       = try(aws_s3_bucket.valkey_migration[0].id, "")
}
