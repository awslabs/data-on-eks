import {
  to = aws_route53_zone.main
  id = "Z05779363BJIUL4KDL4V1"
}

resource "aws_route53_zone" "main" {
  name = local.main_domain

  lifecycle {
    prevent_destroy = true
  }
}