import {
  to = aws_route53_zone.main
  id = var.hosted_zone_id
}

# Récupération de l'entrée NameServer de Route53
resource "aws_route53_zone" "main" {
  name = local.main_domain

  lifecycle {
    prevent_destroy = true
  }
}

# --------------------------------------------------------------------------------------------
# Récupération du Load Balancer Network créé par le déploiement de l'ingress controller Istio
# --------------------------------------------------------------------------------------------
data "aws_lbs" "all" {}

# Extraction des noms des LoadBalancers, puis du NLB de type network
locals {
  lb_names_from_arns = [
    for arn in data.aws_lbs.all.arns :
    split("/", arn)[2]
  ]

  nlb_arns = [
    for arn, lb in data.aws_lb.all_details :
    arn
    if lb.load_balancer_type == "network"
  ]

  selected_nlb_arn = try(local.nlb_arns[0], null)

  selected_nlb = try(data.aws_lb.all_details[local.selected_nlb_arn], null)
}

# Récupération du détail des Load Balancers
data "aws_lb" "all_details" {
  for_each = toset(local.lb_names_from_arns)
  name     = each.key
}

# --------------------------------------------------------------------------------------------
# Création des alias DNS vers LN Network pour les domaines définis en variable
# --------------------------------------------------------------------------------------------
resource "aws_route53_record" "nlb_alias" {
  # Crée une entrée pour chaque nom de domaine, si un NLB a été trouvé
  for_each = local.selected_nlb != null ? {
    for name in var.domaine_name_route53 : name => name
  } : {}

  zone_id = local.zone_id
  name    = each.key
  type    = "A"

  alias {
    name                   = local.selected_nlb.dns_name
    zone_id                = local.selected_nlb.zone_id
    evaluate_target_health = false
  }
}


locals {

  zone_id = aws_route53_zone.main.zone_id
  #zone_id = "Z05779363BJIUL4KDL4V1"
}