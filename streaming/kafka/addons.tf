#---------------------------------------------------------------
# Kubernetes Add-ons
#---------------------------------------------------------------
module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.10.0"

  eks_cluster_id       = module.eks_blueprints.eks_cluster_id
  eks_cluster_endpoint = module.eks_blueprints.eks_cluster_endpoint
  eks_oidc_provider    = module.eks_blueprints.oidc_provider
  eks_cluster_version  = module.eks_blueprints.eks_cluster_version

  # EKS Addons
  enable_amazon_eks_vpc_cni            = true
  enable_amazon_eks_coredns            = true
  enable_amazon_eks_kube_proxy         = true
  enable_amazon_eks_aws_ebs_csi_driver = true

  enable_metrics_server     = true
  enable_cluster_autoscaler = true
  #  enable_aws_efs_csi_driver           = true
  enable_aws_for_fluentbit            = true
  enable_aws_load_balancer_controller = true
  enable_prometheus                   = true
  # enable_grafana                      = true

  # Kafka (Strimzi) add-on with custom helm config
  enable_kafka = true
  kafka_helm_config = {
    name             = local.strimzi_kafka_name
    chart            = local.strimzi_kafka_name
    repository       = "https://strimzi.io/charts/"
    version          = "0.31.1"
    namespace        = local.strimzi_kafka_name
    create_namespace = true
    timeout          = 360
    #    wait             = false # This is critical setting. Check this issue -> https://github.com/hashicorp/terraform-provider-helm/issues/683
    values      = [templatefile("${path.module}/values.yaml", {})]
    description = "Strimzi - Apache Kafka on Kubernetes"
  }
  tags = local.tags
}

#---------------------------------------------------------------
# Install kafka cluster
#---------------------------------------------------------------

resource "kubectl_manifest" "kafka-namespace" {
  yaml_body = file("./kubernetes-manifests/kafka-ns.yml")
}

resource "kubectl_manifest" "kafka-metric-config" {
  yaml_body = file("./kubernetes-manifests/kafka-manifests/kafka-metrics-configmap.yml")
}

resource "kubectl_manifest" "kafka-cluster" {
  yaml_body = file("./kubernetes-manifests/kafka-manifests/kafka-cluster.yml")
}

resource "kubectl_manifest" "grafana-prometheus-datasource" {
  yaml_body = file("./kubernetes-manifests/grafana-manifests/grafana-operator-datasource-prometheus.yml")
}

resource "kubectl_manifest" "grafana-kafka-dashboard" {
  yaml_body = file("./kubernetes-manifests/grafana-manifests/grafana-operator-dashboard-kafka.yml")
}

resource "kubectl_manifest" "grafana-kafka-exporter-dashboard" {
  yaml_body = file("./kubernetes-manifests/grafana-manifests/grafana-operator-dashboard-kafka-exporter.yml")
}

resource "kubectl_manifest" "grafana-kafka-zookeeper-dashboard" {
  yaml_body = file("./kubernetes-manifests/grafana-manifests/grafana-operator-dashboard-kafka-zookeeper.yml")
}

resource "kubectl_manifest" "grafana-kafka-cruise-control-dashboard" {
  yaml_body = file("./kubernetes-manifests/grafana-manifests/grafana-operator-dashboard-kafka-cruise-control.yml")
}

resource "helm_release" "grafana-operator" {

  name             = "grafana-operator"
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "grafana-operator"
  version          = "2.7.8"
  namespace        = "grafana"
  create_namespace = true

}
