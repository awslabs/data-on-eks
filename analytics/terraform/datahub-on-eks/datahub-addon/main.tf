locals {
  datahub_name = "datahub"
  prereq_name  = "datahub-prerequisites"

  datahub_chart      = "datahub"
  prereq_chart       = "datahub-prerequisites"
  datahub_namespace  = "datahub"
  datahub_repository = "https://helm.DataHubproject.io/"
  datahub_version    = "0.6.8"
  prereq_version     = "0.1.15"

  datahub_merged_values_yaml = yamlencode(merge(
    yamldecode(templatefile("${path.module}/values/datahub_values.yaml", {
      es_endpoint                  = module.prereq.es_endpoint
      msk_bootstrap_brokers        = module.prereq.msk_bootstrap_brokers
      msk_zookeeper_connect_string = module.prereq.msk_zookeeper_connect_string
      msk_partitions               = length(var.vpc_private_subnets)
      datahub_rds_address          = module.prereq.rds_address
      datahub_rds_endpoint         = module.prereq.rds_endpoint
    })),
    try(yamldecode(var.datahub_helm_config.values[0]), {})
  ))

  prereq_merged_values_yaml = yamlencode(merge(
    yamldecode(templatefile("${path.module}/values/prereq_values.yaml", {
      msk_bootstrap_brokers = module.prereq.msk_bootstrap_brokers
    })),
    try(yamldecode(var.prereq_helm_config.values[0]), {})
  ))

}

module "prereq" {
  source = "./modules/prereq"

  prefix              = var.prefix
  vpc_id              = var.vpc_id
  vpc_cidr            = var.vpc_cidr
  vpc_private_subnets = var.vpc_private_subnets

}

resource "kubernetes_namespace" "datahub" {
  metadata {
    annotations = {
      name = local.datahub_namespace
    }

    labels = {
      mylabel = local.datahub_namespace
    }

    name = local.datahub_namespace
  }
}

resource "kubernetes_secret" "datahub_es_secret" {
  depends_on = [kubernetes_namespace.datahub]
  metadata {
    name      = "elasticsearch-secrets"
    namespace = local.datahub_namespace
  }

  data = {
    elasticsearch_password = module.prereq.es_password
  }

}

resource "kubernetes_secret" "datahub_rds_secret" {
  depends_on = [kubernetes_namespace.datahub]
  metadata {
    name      = "mysql-secrets"
    namespace = local.datahub_namespace
  }

  data = {
    mysql_root_password = module.prereq.rds_password
  }
}

resource "random_password" "auth_secrets" {
  length      = 32
  special     = false
  min_upper   = 0
  min_lower   = 1
  min_numeric = 1
}

resource "random_password" "auth_secrets_key" {
  length      = 32
  special     = false
  min_upper   = 0
  min_lower   = 1
  min_numeric = 1
}

resource "random_password" "auth_secrets_salt" {
  length      = 32
  special     = false
  min_upper   = 0
  min_lower   = 1
  min_numeric = 1
}

resource "random_password" "datahub_user_password" {
  length  = 16
  special = true
}

resource "kubernetes_secret" "datahub_auth_secrets" {
  depends_on = [kubernetes_namespace.datahub]
  metadata {
    name      = "datahub-auth-secrets"
    namespace = local.datahub_namespace
  }

  data = {
    system_client_secret      = random_password.auth_secrets.result
    token_service_signing_key = random_password.auth_secrets_key.result
    token_service_salt        = random_password.auth_secrets_salt.result
  }

}

resource "kubernetes_secret" "datahub_user_secret" {
  depends_on = [kubernetes_namespace.datahub]
  metadata {
    name      = "datahub-user-secret"
    namespace = local.datahub_namespace
  }

  data = {
    "user.props" = "datahub:${random_password.datahub_user_password.result}"
  }
}

resource "helm_release" "prereq" {
  depends_on = [module.prereq]

  name                       = try(var.prereq_helm_config["name"], local.prereq_name)
  repository                 = try(var.prereq_helm_config["repository"], local.datahub_repository)
  chart                      = try(var.prereq_helm_config["chart"], local.prereq_chart)
  version                    = try(var.prereq_helm_config["version"], local.prereq_version)
  timeout                    = try(var.prereq_helm_config["timeout"], 300)
  values                     = [local.prereq_merged_values_yaml]
  create_namespace           = try(var.datahub_helm_config["create_namespace"], false)
  namespace                  = local.datahub_namespace
  lint                       = try(var.datahub_helm_config["lint"], false)
  description                = try(var.datahub_helm_config["description"], "")
  repository_key_file        = try(var.datahub_helm_config["repository_key_file"], "")
  repository_cert_file       = try(var.datahub_helm_config["repository_cert_file"], "")
  repository_username        = try(var.datahub_helm_config["repository_username"], "")
  repository_password        = try(var.datahub_helm_config["repository_password"], "")
  verify                     = try(var.datahub_helm_config["verify"], false)
  keyring                    = try(var.datahub_helm_config["keyring"], "")
  disable_webhooks           = try(var.datahub_helm_config["disable_webhooks"], false)
  reuse_values               = try(var.datahub_helm_config["reuse_values"], false)
  reset_values               = try(var.datahub_helm_config["reset_values"], false)
  force_update               = try(var.datahub_helm_config["force_update"], false)
  recreate_pods              = try(var.datahub_helm_config["recreate_pods"], false)
  cleanup_on_fail            = try(var.datahub_helm_config["cleanup_on_fail"], false)
  max_history                = try(var.datahub_helm_config["max_history"], 0)
  atomic                     = try(var.datahub_helm_config["atomic"], false)
  skip_crds                  = try(var.datahub_helm_config["skip_crds"], false)
  render_subchart_notes      = try(var.datahub_helm_config["render_subchart_notes"], true)
  disable_openapi_validation = try(var.datahub_helm_config["disable_openapi_validation"], false)
  wait                       = try(var.datahub_helm_config["wait"], true)
  wait_for_jobs              = try(var.datahub_helm_config["wait_for_jobs"], false)
  dependency_update          = try(var.datahub_helm_config["dependency_update"], false)
  replace                    = try(var.datahub_helm_config["replace"], false)

  postrender {
    binary_path = try(var.prereq_helm_config["postrender"], "")
  }


  dynamic "set_sensitive" {
    iterator = each_item
    for_each = try(var.prereq_helm_config["set_sensitive"], [])

    content {
      name  = each_item.value.name
      value = each_item.value.value
      type  = try(each_item.value.type, null)
    }
  }
}

resource "helm_release" "datahub" {
  depends_on = [kubernetes_secret.datahub_es_secret, kubernetes_secret.datahub_rds_secret, kubernetes_secret.datahub_auth_secrets, kubernetes_secret.datahub_user_secret, helm_release.prereq]

  name                       = try(var.datahub_helm_config["name"], local.datahub_name)
  repository                 = try(var.datahub_helm_config["repository"], local.datahub_repository)
  chart                      = try(var.datahub_helm_config["chart"], local.datahub_chart)
  version                    = try(var.datahub_helm_config["version"], local.datahub_version)
  timeout                    = try(var.datahub_helm_config["timeout"], 300)
  values                     = [local.datahub_merged_values_yaml]
  create_namespace           = try(var.datahub_helm_config["create_namespace"], false)
  namespace                  = local.datahub_namespace
  lint                       = try(var.datahub_helm_config["lint"], false)
  description                = try(var.datahub_helm_config["description"], "")
  repository_key_file        = try(var.datahub_helm_config["repository_key_file"], "")
  repository_cert_file       = try(var.datahub_helm_config["repository_cert_file"], "")
  repository_username        = try(var.datahub_helm_config["repository_username"], "")
  repository_password        = try(var.datahub_helm_config["repository_password"], "")
  verify                     = try(var.datahub_helm_config["verify"], false)
  keyring                    = try(var.datahub_helm_config["keyring"], "")
  disable_webhooks           = try(var.datahub_helm_config["disable_webhooks"], false)
  reuse_values               = try(var.datahub_helm_config["reuse_values"], false)
  reset_values               = try(var.datahub_helm_config["reset_values"], false)
  force_update               = try(var.datahub_helm_config["force_update"], false)
  recreate_pods              = try(var.datahub_helm_config["recreate_pods"], false)
  cleanup_on_fail            = try(var.datahub_helm_config["cleanup_on_fail"], false)
  max_history                = try(var.datahub_helm_config["max_history"], 0)
  atomic                     = try(var.datahub_helm_config["atomic"], false)
  skip_crds                  = try(var.datahub_helm_config["skip_crds"], false)
  render_subchart_notes      = try(var.datahub_helm_config["render_subchart_notes"], true)
  disable_openapi_validation = try(var.datahub_helm_config["disable_openapi_validation"], false)
  wait                       = try(var.datahub_helm_config["wait"], true)
  wait_for_jobs              = try(var.datahub_helm_config["wait_for_jobs"], false)
  dependency_update          = try(var.datahub_helm_config["dependency_update"], false)
  replace                    = try(var.datahub_helm_config["replace"], false)

  postrender {
    binary_path = try(var.datahub_helm_config["postrender"], "")
  }


  dynamic "set_sensitive" {
    iterator = each_item
    for_each = try(var.datahub_helm_config["set_sensitive"], [])

    content {
      name  = each_item.value.name
      value = each_item.value.value
      type  = try(each_item.value.type, null)
    }
  }
}
