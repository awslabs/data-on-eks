# Valkey runs in replication mode. The official chart does not have cluster mode yet
# (valkey-helm issue #18).
# The restore AWS resources are always created, so you can set restore.enabled
# in helm-values/valkey.yaml without a Terraform run.

locals {
  valkey_namespace       = "valkey"
  valkey_service_account = "valkey-sa"

  valkey_values_rendered = templatefile("${path.module}/helm-values/valkey.yaml", {
    namespace            = local.valkey_namespace
    service_account_name = local.valkey_service_account
    region               = local.region
  })
}

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

# The chart reads the passwords from auth.usersExistingSecret. Each Secret key is an ACL user name.
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

# For a migration from EC2, data-stacks/valkey-on-eks/examples/migration/ec2-bgsave-to-s3.sh
# writes dump.rdb to this bucket. The restore initContainer reads it at first start.
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

# The restore initContainer runs in the Valkey pod, so it uses this association.
module "valkey_restore_pod_identity" {
  count = var.enable_valkey ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.9.0"

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
