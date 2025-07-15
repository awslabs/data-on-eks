resource "aws_route53_zone" "main" {
  name = local.main_domain

  lifecycle {
    prevent_destroy = true
  }
}

