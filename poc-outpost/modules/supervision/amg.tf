# module "managed_grafana" {
#   source  = "terraform-aws-modules/managed-service-grafana/aws"
#   version = "1.10.0"
#
#   count  = var.enable_amazon_grafana ? 1 : 0
#
#   name                      = local.grafana_manager_name
#   associate_license         = false
#   description               = local.grafana_manager_description
#   account_access_type       = "CURRENT_ACCOUNT"
#   authentication_providers  = ["AWS_SSO"]
#   permission_type           = "SERVICE_MANAGED"
#   data_sources              = ["CLOUDWATCH", "PROMETHEUS", "XRAY"]
#   notification_destinations = ["SNS"]
#   stack_set_name            = local.grafana_manager_name
#
#   configuration = jsonencode({
#     unifiedAlerting = {
#       enabled = true
#     }
#   })
#
#   grafana_version = "9.4"
#
#
#   # Workspace IAM role
#   create_iam_role                = true
#   iam_role_name                  = local.grafana_manager_name
#   use_iam_role_name_prefix       = true
#   iam_role_description           = local.grafana_manager_description
#   iam_role_path                  = "/grafana/"
#   iam_role_force_detach_policies = true
#   iam_role_max_session_duration  = 7200
#   iam_role_tags                  = local.tags
#
#
#   # Workspace API keys
#   workspace_api_keys = {
#     viewer = {
#       key_name        = "viewer"
#       key_role        = "VIEWER"
#       seconds_to_live = 3600
#     }
#     editor = {
#       key_name        = "editor"
#       key_role        = "EDITOR"
#       seconds_to_live = 3600
#     }
#     admin = {
#       key_name        = "admin"
#       key_role        = "ADMIN"
#       seconds_to_live = 3600
#     }
#   }
#
#   tags = local.tags
# }
