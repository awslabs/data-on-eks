data "aws_eks_cluster_auth" "this" {
  name = module.eks_blueprints.eks_cluster_id
}

data "aws_availability_zones" "available" {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_secretsmanager_secret_version" "admin_password_version" {
  secret_id = aws_secretsmanager_secret.grafana.id

  depends_on = [aws_secretsmanager_secret_version.grafana]
}


#---------------------------------------------------------------
# IAM policy for Spark job execution
#---------------------------------------------------------------
data "aws_iam_policy_document" "fluent_bit" {
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${aws_s3_bucket.this.id}/*"]

    actions = [
      "s3:ListBucket",
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:GetObject",
      "s3:GetObjectAcl",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion"
    ]
  }
}

data "aws_acm_certificate" "issued" {
  domain   = var.acm_certificate_domain
  statuses = ["ISSUED"]
}

data "aws_secretsmanager_secret_version" "nifi_login_password_version" {
  secret_id = aws_secretsmanager_secret.nifi_login_password.id

  depends_on = [aws_secretsmanager_secret_version.nifi_login_password]
}

data "aws_secretsmanager_secret_version" "nifi_truststore_password_version" {
  secret_id = aws_secretsmanager_secret.nifi_truststore_password.id

  depends_on = [aws_secretsmanager_secret_version.nifi_truststore_password]
}

data "aws_secretsmanager_secret_version" "nifi_keystore_password_version" {
  secret_id = aws_secretsmanager_secret.nifi_keystore_password.id

  depends_on = [aws_secretsmanager_secret_version.nifi_keystore_password]
}
