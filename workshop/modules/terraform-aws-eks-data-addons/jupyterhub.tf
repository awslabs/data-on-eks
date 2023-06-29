resource "helm_release" "jupyterhub" {
  count            = var.enable_jupyterhub ? 1 : 0
  name             = try(var.jupyterhub_helm_config["name"], local.jupyterhub_name)
  repository       = try(var.jupyterhub_helm_config["repository"], local.jupyterhub_repository)
  chart            = try(var.jupyterhub_helm_config["chart"], local.jupyterhub_name)
  version          = try(var.jupyterhub_helm_config["version"], local.jupyterhub_version)
  create_namespace = try(var.jupyterhub_helm_config["create_namespace"], true)
  namespace        = try(var.jupyterhub_helm_config["namespace"], local.jupyterhub_name)
  values           = try(var.jupyterhub_helm_config["values"], null)


  postrender {
    binary_path = try(var.jupyterhub_helm_config["postrender"], "")
  }

  dynamic "set" {
    iterator = each_item
    for_each = try(var.jupyterhub_helm_config["set"], [])

    content {
      name  = each_item.value.name
      value = each_item.value.value
      type  = try(each_item.value.type, null)
    }
  }

  dynamic "set_sensitive" {
    iterator = each_item
    for_each = try(var.jupyterhub_helm_config["set_sensitive"], [])

    content {
      name  = each_item.value.name
      value = each_item.value.value
      type  = try(each_item.value.type, null)
    }
  }
}