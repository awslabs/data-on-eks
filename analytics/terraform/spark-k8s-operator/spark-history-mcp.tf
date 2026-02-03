#---------------------------------------------------------------
# Spark History MCP Server
# Provides AI agent access to Spark History Server for job analysis
# https://github.com/kubeflow/mcp-apache-spark-history-server
#---------------------------------------------------------------

resource "helm_release" "spark_history_mcp" {
  count = var.enable_spark_history_mcp ? 1 : 0

  name             = "spark-history-mcp"
  chart            = "${path.module}/helm-charts/spark-history-mcp"
  namespace        = "spark-history-server"
  create_namespace = false

  values = [
    templatefile("${path.module}/helm-values/spark-history-mcp-values.yaml", {
      monitoring_enabled = var.enable_amazon_prometheus
    })
  ]

  depends_on = [module.eks_data_addons]
}
