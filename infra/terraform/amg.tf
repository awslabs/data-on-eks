#------------------------------------------
# Amazon Managed Grafana
#------------------------------------------
# Workspace for shared dashboards on top of Amazon Managed Prometheus and
# AWS X-Ray. Users sign in with IAM Identity Center, which must be enabled in
# the account. Admins come from amg_admin_user_ids / amg_admin_group_ids
# (IAM Identity Center IDs). After deployment:
#   1. Add the AMP workspace as a data source (Apps > AWS Data Sources > Amazon Managed Service for Prometheus)
#   2. Import dashboards
# See the Ray observability guide in the website docs for the full steps.
module "amg" {
  count = var.enable_amazon_managed_grafana ? 1 : 0

  source  = "terraform-aws-modules/managed-service-grafana/aws"
  version = "~> 2.3"

  name                     = "${local.name}-amg"
  description              = "Amazon Managed Grafana for ${local.name}"
  grafana_version          = "12.4"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"

  # Grants the workspace IAM role read access to these services
  data_sources = ["PROMETHEUS", "XRAY", "CLOUDWATCH"]

  # Not placed in the VPC, so no security group is needed
  create_security_group = false

  # The module defaults to a paid Grafana Enterprise license; not needed here
  associate_license = false

  role_associations = {
    for role in ["ADMIN"] : role => {
      user_ids  = length(var.amg_admin_user_ids) > 0 ? var.amg_admin_user_ids : null
      group_ids = length(var.amg_admin_group_ids) > 0 ? var.amg_admin_group_ids : null
    } if length(concat(var.amg_admin_user_ids, var.amg_admin_group_ids)) > 0
  }

  tags = local.tags
}
