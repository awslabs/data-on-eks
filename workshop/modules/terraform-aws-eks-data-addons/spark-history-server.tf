locals {
  spark_history_server_service_account = "spark-history-server-sa"
  spark_history_server_create_irsa     = var.enable_spark_history_server && try(var.spark_history_server_helm_config.create_irsa, false)
  spark_history_server_namespace       = try(var.spark_history_server_helm_config["namespace"], local.spark_history_server_name)
  spark_history_server_set_values = local.spark_history_server_create_irsa ? [
    {
      name  = "serviceAccount.create"
      value = true
    },
    {
      name  = "serviceAccount.name"
      value = local.spark_history_server_service_account
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = module.spark_history_server_irsa[0].iam_role_arn
    }
  ] : []

  spark_history_server_merged_values_yaml = yamlencode(merge(
    yamldecode(templatefile("${path.module}/values/spark-history-server.yaml", {})),
    try(yamldecode(var.spark_history_server_helm_config.values[0]), {})
  ))
}

resource "helm_release" "spark_history_server" {
  count = var.enable_spark_history_server ? 1 : 0

  name                       = try(var.spark_history_server_helm_config["name"], local.spark_history_server_name)
  repository                 = try(var.spark_history_server_helm_config["repository"], local.spark_history_server_repository)
  chart                      = try(var.spark_history_server_helm_config["chart"], local.spark_history_server_name)
  version                    = try(var.spark_history_server_helm_config["version"], local.spark_history_server_version)
  timeout                    = try(var.spark_history_server_helm_config["timeout"], 300)
  values                     = [local.spark_history_server_merged_values_yaml]
  create_namespace           = try(var.spark_history_server_helm_config["create_namespace"], true)
  namespace                  = local.spark_history_server_namespace
  lint                       = try(var.spark_history_server_helm_config["lint"], false)
  description                = try(var.spark_history_server_helm_config["description"], "")
  repository_key_file        = try(var.spark_history_server_helm_config["repository_key_file"], "")
  repository_cert_file       = try(var.spark_history_server_helm_config["repository_cert_file"], "")
  repository_username        = try(var.spark_history_server_helm_config["repository_username"], "")
  repository_password        = try(var.spark_history_server_helm_config["repository_password"], "")
  verify                     = try(var.spark_history_server_helm_config["verify"], false)
  keyring                    = try(var.spark_history_server_helm_config["keyring"], "")
  disable_webhooks           = try(var.spark_history_server_helm_config["disable_webhooks"], false)
  reuse_values               = try(var.spark_history_server_helm_config["reuse_values"], false)
  reset_values               = try(var.spark_history_server_helm_config["reset_values"], false)
  force_update               = try(var.spark_history_server_helm_config["force_update"], false)
  recreate_pods              = try(var.spark_history_server_helm_config["recreate_pods"], false)
  cleanup_on_fail            = try(var.spark_history_server_helm_config["cleanup_on_fail"], false)
  max_history                = try(var.spark_history_server_helm_config["max_history"], 0)
  atomic                     = try(var.spark_history_server_helm_config["atomic"], false)
  skip_crds                  = try(var.spark_history_server_helm_config["skip_crds"], false)
  render_subchart_notes      = try(var.spark_history_server_helm_config["render_subchart_notes"], true)
  disable_openapi_validation = try(var.spark_history_server_helm_config["disable_openapi_validation"], false)
  wait                       = try(var.spark_history_server_helm_config["wait"], true)
  wait_for_jobs              = try(var.spark_history_server_helm_config["wait_for_jobs"], false)
  dependency_update          = try(var.spark_history_server_helm_config["dependency_update"], false)
  replace                    = try(var.spark_history_server_helm_config["replace"], false)

  postrender {
    binary_path = try(var.spark_history_server_helm_config["postrender"], "")
  }

  dynamic "set" {
    iterator = each_item
    for_each = distinct(concat(try(var.spark_history_server_helm_config.set, []), local.spark_history_server_set_values))

    content {
      name  = each_item.value.name
      value = each_item.value.value
      type  = try(each_item.value.type, null)
    }
  }

  dynamic "set_sensitive" {
    iterator = each_item
    for_each = try(var.spark_history_server_helm_config["set_sensitive"], [])

    content {
      name  = each_item.value.name
      value = each_item.value.value
      type  = try(each_item.value.type, null)
    }
  }
}

#---------------------------------------------------------------
# IRSA for Spark History Server
#---------------------------------------------------------------
module "spark_history_server_irsa" {
  source = "./irsa"
  count  = local.spark_history_server_create_irsa ? 1 : 0

  # IAM role for service account (IRSA)
  create_role                   = try(var.spark_history_server_helm_config.create_role, true)
  role_name                     = try(var.spark_history_server_helm_config.role_name, local.spark_history_server_name)
  role_name_use_prefix          = try(var.spark_history_server_helm_config.role_name_use_prefix, true)
  role_path                     = try(var.spark_history_server_helm_config.role_path, "/")
  role_permissions_boundary_arn = try(var.spark_history_server_helm_config.role_permissions_boundary_arn, null)
  role_description              = try(var.spark_history_server_helm_config.role_description, "IRSA for ${local.spark_history_server_name} project")

  role_policy_arns = try(var.spark_history_server_helm_config.role_policy_arns, { "S3ReadOnlyPolicy" : "arn:${local.partition}:iam::aws:policy/AmazonS3ReadOnlyAccess" })

  oidc_providers = {
    this = {
      provider_arn    = var.oidc_provider_arn
      namespace       = local.spark_history_server_namespace
      service_account = local.spark_history_server_service_account
    }
  }
}
