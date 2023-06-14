locals {

  emr_spark_operator_yaml = yamlencode(merge(
    yamldecode(templatefile("${path.module}/values/emr-spark-operator-values.yaml", { aws_region = local.region })),
    try(yamldecode(var.emr_spark_operator_helm_config.values[0]), {})
  ))

  account_region_map = {
    ap-northeast-1 = "059004520145"
    ap-northeast-2 = "996579266876"
    ap-south-1     = "235914868574"
    ap-southeast-1 = "671219180197"
    ap-southeast-2 = "038297999601"
    ca-central-1   = "351826393999"
    eu-central-1   = "107292555468"
    eu-north-1     = "830386416364"
    eu-west-1      = "483788554619"
    eu-west-2      = "118780647275"
    eu-west-3      = "307523725174"
    sa-east-1      = "052806832358"
    us-east-1      = "755674844232"
    us-east-2      = "711395599931"
    us-west-1      = "608033475327"
    us-west-2      = "895885662937"
  }

}

resource "helm_release" "emr_spark_operator" {
  count = var.enable_emr_spark_operator ? 1 : 0

  name = try(var.emr_spark_operator_helm_config["name"], local.emr_spark_operator_name)

  repository = "oci://${local.account_region_map[local.region]}.dkr.ecr.${local.region}.amazonaws.com"
  chart      = "spark-operator"

  version = try(var.emr_spark_operator_helm_config["version"], local.emr_spark_operator_version)

  namespace = try(var.emr_spark_operator_helm_config["namespace"], local.emr_spark_operator_namespace)

  create_namespace = try(var.emr_spark_operator_helm_config["create_namespace"], true)

  repository_username = var.emr_spark_operator_helm_config["private_ecr_token_user_name"]
  repository_password = var.emr_spark_operator_helm_config["private_ecr_token_password"]

  values = [
    local.emr_spark_operator_yaml
  ]

}
