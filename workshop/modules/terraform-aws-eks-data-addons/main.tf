locals {
  spark_operator_name       = "spark-operator"
  spark_operator_repository = "https://googlecloudplatform.github.io/spark-on-k8s-operator"
  spark_operator_version    = "1.1.27"

  flink_operator_name       = "flink-kubernetes-operator"
  flink_operator_repository = "https://downloads.apache.org/flink/flink-kubernetes-operator-${local.flink_operator_version}"
  flink_operator_version    = try(var.flink_operator_helm_config["version"], "1.4.0")

  yunikorn_name       = "yunikorn"
  yunikorn_repository = "https://apache.github.io/yunikorn-release"
  yunikorn_version    = "1.2.0"

  spark_history_server_name       = "spark-history-server"
  spark_history_server_repository = "https://hyper-mesh.github.io/spark-history-server"
  spark_history_server_version    = "1.0.0"

  prometheus_name       = "prometheus"
  prometheus_repository = "https://prometheus-community.github.io/helm-charts"
  prometheus_version    = "15.17.0"

  kubecost_name       = "kubecost"
  kubecost_repository = "oci://public.ecr.aws/kubecost"
  kubecost_version    = "1.97.0"

  grafana_name       = "grafana"
  grafana_repository = "https://grafana.github.io/helm-charts"
  grafana_version    = "6.52.4"

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name
}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
