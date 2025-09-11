locals {
  spark_operator_name            = "spark-operator"
  spark_operator_service_account = "spark-operator-sa"
  spark_operator_values = yamldecode(templatefile("${path.module}/helm-values/spark-operator.yaml", {})
  )
}

#---------------------------------------------------------------
# Spark Operator Application
#---------------------------------------------------------------
resource "kubectl_manifest" "spark_operator" {
  count = var.enable_spark_operator ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/spark-operator.yaml", {
    user_values_yaml = indent(8, yamlencode(local.spark_operator_values))
  })

  depends_on = [
    helm_release.argocd,
    module.spark_history_server_irsa,
  ]
}
