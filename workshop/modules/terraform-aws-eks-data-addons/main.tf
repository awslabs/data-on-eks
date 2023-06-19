locals {
  spark_operator_name       = "spark-operator"
  spark_operator_repository = "https://googlecloudplatform.github.io/spark-on-k8s-operator"
  spark_operator_version    = "1.1.27"

  flink_operator_name       = "flink-kubernetes-operator"
  flink_operator_repository = "https://downloads.apache.org/flink/flink-kubernetes-operator-${local.flink_operator_version}"
  flink_operator_version    = try(var.flink_operator_helm_config["version"], "1.4.0")

  nvidia_gpu_operator_name       = "nvidia-gpu-operator"
  nvidia_gpu_operator_repository = "https://helm.ngc.nvidia.com/nvidia"
  nvidia_gpu_operator_version    = "v23.3.2"

  yunikorn_name       = "yunikorn"
  yunikorn_repository = "https://apache.github.io/yunikorn-release"
  yunikorn_version    = "1.2.0"

  spark_history_server_name       = "spark-history-server"
  spark_history_server_repository = "https://hyper-mesh.github.io/spark-history-server"
  spark_history_server_version    = "1.0.0"

  prometheus_name       = "prometheus"
  prometheus_repository = "https://prometheus-community.github.io/helm-charts"
  prometheus_version    = "22.6.0"

  kubecost_name       = "kubecost"
  kubecost_repository = "oci://public.ecr.aws/kubecost"
  kubecost_version    = "1.103.2"

  grafana_name       = "grafana"
  grafana_repository = "https://grafana.github.io/helm-charts"
  grafana_version    = "6.52.4"

  emr_spark_operator_name       = "emr-spark-operator"
  emr_spark_operator_repository = "oci://${local.account_region_map[local.region]}.dkr.ecr.${local.region}.amazonaws.com"
  emr_spark_operator_version    = "1.1.26-amzn-1"

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name

  # Private ECR Account IDs for EMR Spark Operator Helm Charts
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

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
