locals {

  emr_spark_operator_yaml = yamlencode(merge(
    yamldecode(templatefile("${path.module}/values/emr-spark-operator-values.yaml", { aws_region = local.region })),
    try(yamldecode(var.emr_spark_operator_config.values[0]), {})
  ))
}

resource "helm_release" "emr_spark_operator" {
  count = var.enable_emr_spark_operator ? 1 : 0

  name = "spark-operator"

  repository = "oci://895885662937.dkr.ecr.us-west-2.amazonaws.com"
  chart      = "spark-operator"

  version = "1.1.26-amzn-0"

  namespace = "spark-operator"

  create_namespace = true

  repository_username = var.emr_spark_operator_config["private_ecr_token_user_name"]
  repository_password = var.emr_spark_operator_config["private_ecr_token_password"]

  values = [
    local.emr_spark_operator_yaml
  ]

}
