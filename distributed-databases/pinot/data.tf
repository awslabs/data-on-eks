data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_availability_zones" "available" {}

data "aws_secretsmanager_secret_version" "admin_password_version" {
  secret_id = aws_secretsmanager_secret.grafana.id

  depends_on = [aws_secretsmanager_secret_version.grafana]
}

data "aws_acm_certificate" "issued" {
  domain   = var.acm_certificate_domain
  statuses = ["ISSUED"]
}
