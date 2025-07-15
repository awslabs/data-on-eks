data "aws_eks_cluster_auth" "this" {
  name = var.name
}


data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# data "aws_ecrpublic_authorization_token" "token" {
#   provider = aws.virginia
# }

# Retrieves the IAM session context, including the ARN of the currently logged-in user/role.
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

data "aws_route53_zone" "current" {
  name = var.main_domain
}

data "aws_lbs" "all" {}

data "aws_lb" "all" {
  for_each = toset(data.aws_lbs.all.arns)
  arn      = each.value
}

locals {
  trino_ingress = [
    for lb in data.aws_lb.all :
    {
      dns_name = lb.dns_name
      arn      = lb.arn
      name     = lb.name
      zone_id  = lb.zone_id
    }
    #if startswith(lb.name, "k8s-trino")
  ]
}

resource "aws_route53_record" "record" {
  for_each = { for ingress in local.trino_ingress : ingress.name => ingress }

  zone_id = data.aws_route53_zone.current.zone_id
  name    = "${split("-", each.value.name)[1]}.${var.main_domain}"
  type    = "A"

  alias {
    name                   = each.value.dns_name
    zone_id                = each.value.zone_id
    evaluate_target_health = true
  }
}
