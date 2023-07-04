locals {
  grafana_service_account = "grafana-sa"
  grafana_create_irsa     = var.enable_grafana && try(var.grafana_helm_config.create_irsa, false)
  grafana_namespace       = try(var.grafana_helm_config["namespace"], local.grafana_name)
  grafana_set_values = local.grafana_create_irsa ? [
    {
      name  = "serviceAccount.create"
      value = true
    },
    {
      name  = "serviceAccount.name"
      value = local.grafana_service_account
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = module.grafana_irsa[0].iam_role_arn
    }
  ] : []

  grafana_merged_values_yaml = yamlencode(merge(
    yamldecode(templatefile("${path.module}/helm-values/grafana.yaml", { region = local.region })),
    try(yamldecode(var.grafana_helm_config.values[0]), {})
  ))
}

resource "helm_release" "grafana" {
  count = var.enable_grafana ? 1 : 0

  name                       = try(var.grafana_helm_config["name"], local.grafana_name)
  repository                 = try(var.grafana_helm_config["repository"], local.grafana_repository)
  chart                      = try(var.grafana_helm_config["chart"], local.grafana_name)
  version                    = try(var.grafana_helm_config["version"], local.grafana_version)
  timeout                    = try(var.grafana_helm_config["timeout"], 300)
  values                     = [local.grafana_merged_values_yaml]
  create_namespace           = try(var.grafana_helm_config["create_namespace"], true)
  namespace                  = local.grafana_namespace
  lint                       = try(var.grafana_helm_config["lint"], false)
  description                = try(var.grafana_helm_config["description"], "")
  repository_key_file        = try(var.grafana_helm_config["repository_key_file"], "")
  repository_cert_file       = try(var.grafana_helm_config["repository_cert_file"], "")
  repository_username        = try(var.grafana_helm_config["repository_username"], "")
  repository_password        = try(var.grafana_helm_config["repository_password"], "")
  verify                     = try(var.grafana_helm_config["verify"], false)
  keyring                    = try(var.grafana_helm_config["keyring"], "")
  disable_webhooks           = try(var.grafana_helm_config["disable_webhooks"], false)
  reuse_values               = try(var.grafana_helm_config["reuse_values"], false)
  reset_values               = try(var.grafana_helm_config["reset_values"], false)
  force_update               = try(var.grafana_helm_config["force_update"], false)
  recreate_pods              = try(var.grafana_helm_config["recreate_pods"], false)
  cleanup_on_fail            = try(var.grafana_helm_config["cleanup_on_fail"], false)
  max_history                = try(var.grafana_helm_config["max_history"], 0)
  atomic                     = try(var.grafana_helm_config["atomic"], false)
  skip_crds                  = try(var.grafana_helm_config["skip_crds"], false)
  render_subchart_notes      = try(var.grafana_helm_config["render_subchart_notes"], true)
  disable_openapi_validation = try(var.grafana_helm_config["disable_openapi_validation"], false)
  wait                       = try(var.grafana_helm_config["wait"], true)
  wait_for_jobs              = try(var.grafana_helm_config["wait_for_jobs"], false)
  dependency_update          = try(var.grafana_helm_config["dependency_update"], false)
  replace                    = try(var.grafana_helm_config["replace"], false)

  postrender {
    binary_path = try(var.grafana_helm_config["postrender"], "")
  }

  dynamic "set" {
    iterator = each_item
    for_each = distinct(concat(try(var.grafana_helm_config.set, []), local.grafana_set_values))

    content {
      name  = each_item.value.name
      value = each_item.value.value
      type  = try(each_item.value.type, null)
    }
  }

  dynamic "set_sensitive" {
    iterator = each_item
    for_each = try(var.grafana_helm_config["set_sensitive"], [])

    content {
      name  = each_item.value.name
      value = each_item.value.value
      type  = try(each_item.value.type, null)
    }
  }
}

# IRSA module
module "grafana_irsa" {
  source = "./irsa"
  count  = local.grafana_create_irsa ? 1 : 0

  # IAM role for service account (IRSA)
  create_role                   = try(var.grafana_helm_config.create_role, true)
  role_name                     = try(var.grafana_helm_config.role_name, local.grafana_name)
  role_name_use_prefix          = try(var.grafana_helm_config.role_name_use_prefix, true)
  role_path                     = try(var.grafana_helm_config.role_path, "/")
  role_permissions_boundary_arn = try(var.grafana_helm_config.role_permissions_boundary_arn, null)
  role_description              = try(var.grafana_helm_config.role_description, "IRSA for ${local.grafana_name} project")

  role_policy_arns = merge(
    try(var.grafana_helm_config.role_policy_arns, {}),
    { GrafanaPolicy = try(aws_iam_policy.grafana[0].arn, null) }
  )

  oidc_providers = {
    this = {
      provider_arn    = var.oidc_provider_arn
      namespace       = local.grafana_namespace
      service_account = local.grafana_service_account
    }
  }
}

resource "aws_iam_policy" "grafana" {
  count = local.grafana_create_irsa ? 1 : 0

  description = "IAM policy for Grafana Pod"
  name_prefix = try(var.grafana_helm_config.role_name, local.grafana_name)
  path        = try(var.grafana_helm_config.role_path, "/")
  policy      = data.aws_iam_policy_document.this[0].json
}

# IAM Policy for Grafana
data "aws_iam_policy_document" "this" {
  count = local.grafana_create_irsa ? 1 : 0

  statement {
    sid       = "AllowReadingMetricsFromCloudWatch"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics"
    ]
  }

  statement {
    sid       = "AllowGetInsightsCloudWatch"
    effect    = "Allow"
    resources = ["arn:${local.partition}:cloudwatch:${local.region}:${local.account_id}:insight-rule/*"]

    actions = [
      "cloudwatch:GetInsightRuleReport",
    ]
  }

  statement {
    sid       = "AllowReadingAlarmHistoryFromCloudWatch"
    effect    = "Allow"
    resources = ["arn:${local.partition}:cloudwatch:${local.region}:${local.account_id}:alarm:*"]

    actions = [
      "cloudwatch:DescribeAlarmHistory",
      "cloudwatch:DescribeAlarms",
    ]
  }

  statement {
    sid       = "AllowReadingLogsFromCloudWatch"
    effect    = "Allow"
    resources = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:*:log-stream:*"]

    actions = [
      "logs:DescribeLogGroups",
      "logs:GetLogGroupFields",
      "logs:StartQuery",
      "logs:StopQuery",
      "logs:GetQueryResults",
      "logs:GetLogEvents",
    ]
  }

  statement {
    sid       = "AllowReadingTagsInstancesRegionsFromEC2"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "ec2:DescribeTags",
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
    ]
  }

  statement {
    sid       = "AllowReadingResourcesForTags"
    effect    = "Allow"
    resources = ["*"]
    actions   = ["tag:GetResources"]
  }

  statement {
    sid    = "AllowListApsWorkspaces"
    effect = "Allow"
    resources = [
      "arn:${local.partition}:aps:${local.region}:${local.account_id}:/*",
      "arn:${local.partition}:aps:${local.region}:${local.account_id}:workspace/*",
      "arn:${local.partition}:aps:${local.region}:${local.account_id}:workspace/*/*",
    ]
    actions = [
      "aps:ListWorkspaces",
      "aps:DescribeWorkspace",
      "aps:GetMetricMetadata",
      "aps:GetSeries",
      "aps:QueryMetrics",
    ]
  }
}
