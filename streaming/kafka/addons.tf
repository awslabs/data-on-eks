#---------------------------------------------------------------
# Kubernetes Add-ons
#---------------------------------------------------------------
module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.15.0"

  eks_cluster_id       = module.eks_blueprints.eks_cluster_id
  eks_cluster_endpoint = module.eks_blueprints.eks_cluster_endpoint
  eks_oidc_provider    = module.eks_blueprints.oidc_provider
  eks_cluster_version  = module.eks_blueprints.eks_cluster_version

  enable_amazon_eks_vpc_cni    = true
  enable_amazon_eks_kube_proxy = true
  enable_amazon_eks_coredns    = true

  #---------------------------------------------------------------
  # Self managed EBS CSI Driver
  # Used self_managed_aws_ebs_csi_driver to define the Node Tolerations `tolerateAllTaints: true`
  #---------------------------------------------------------------
  enable_self_managed_aws_ebs_csi_driver = true
  self_managed_aws_ebs_csi_driver_helm_config = {
    name        = local.csi_name
    description = "The Amazon Elastic Block Store Container Storage Interface (CSI) Driver provides a CSI interface used by Container Orchestrators to manage the lifecycle of Amazon EBS volumes."
    chart       = local.csi_name
    version     = "2.12.1"
    repository  = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
    namespace   = local.csi_namespace
    values = [
      <<-EOT
      image:
        repository: public.ecr.aws/ebs-csi-driver/aws-ebs-csi-driver
      controller:
        k8sTagClusterId: ${module.eks_blueprints.eks_cluster_id}
      node:
        tolerateAllTaints: true
      EOT
    ]
  }

  #---------------------------------------------------------------
  # AWS Load Balancer Controller
  #---------------------------------------------------------------
  enable_aws_load_balancer_controller = true

  #---------------------------------------------------------------
  # Metrics Server
  #---------------------------------------------------------------
  enable_metrics_server = true
  metrics_server_helm_config = {
    name       = "metrics-server"
    repository = "https://kubernetes-sigs.github.io/metrics-server/" # (Optional) Repository URL where to locate the requested chart.
    chart      = "metrics-server"
    version    = "3.8.2"
    namespace  = "kube-system"
    timeout    = "300"
    values = [templatefile("${path.module}/helm-values/metrics-server-values.yaml", {
      operating_system = "linux"
      node_group_type  = "core"
    })]
  }

  #---------------------------------------------------------------
  # Cluster Autoscaler
  #---------------------------------------------------------------
  enable_cluster_autoscaler = true
  cluster_autoscaler_helm_config = {
    name       = "cluster-autoscaler"
    repository = "https://kubernetes.github.io/autoscaler" # (Optional) Repository URL where to locate the requested chart.
    chart      = "cluster-autoscaler"
    version    = "9.15.0"
    namespace  = "kube-system"
    timeout    = "300"
    values = [templatefile("${path.module}/helm-values/cluster-autoscaler-values.yaml", {
      aws_region       = var.region,
      eks_cluster_id   = local.name,
      operating_system = "linux"
      node_group_type  = "core"
    })]
  }

  #---------------------------------------------------------------
  # Logging with FluentBit
  #---------------------------------------------------------------
  enable_aws_for_fluentbit                 = true
  aws_for_fluentbit_cw_log_group_retention = 30
  aws_for_fluentbit_helm_config = {
    name                            = "aws-for-fluent-bit"
    chart                           = "aws-for-fluent-bit"
    repository                      = "https://aws.github.io/eks-charts"
    version                         = "0.1.19"
    namespace                       = "logging"
    timeout                         = "300"
    aws_for_fluent_bit_cw_log_group = "/${module.eks_blueprints.eks_cluster_id}/worker-fluentbit-logs" # Optional
    create_namespace                = true
    values = [templatefile("${path.module}/helm-values/aws-for-fluentbit-values.yaml", {
      region                    = data.aws_region.current.id
      aws_for_fluent_bit_cw_log = "/${module.eks_blueprints.eks_cluster_id}/worker-fluentbit-logs"
    })]
    set = [
      {
        name  = "nodeSelector.kubernetes\\.io/os"
        value = "linux"
      }
    ]
  }

  #---------------------------------------------------------------
  # Amazon Managed Prometheus
  #---------------------------------------------------------------
  enable_amazon_prometheus             = true
  amazon_prometheus_workspace_endpoint = module.managed_prometheus.workspace_prometheus_endpoint

  #---------------------------------------------------------------
  # Prometheus Server Add-on
  #---------------------------------------------------------------
  enable_prometheus = true
  prometheus_helm_config = {
    name       = "prometheus"
    repository = "https://prometheus-community.github.io/helm-charts"
    chart      = "prometheus"
    version    = "15.10.1"
    namespace  = "prometheus"
    timeout    = "300"
    values = [templatefile("${path.module}/helm-values/prometheus-values.yaml", {
      operating_system = "linux"
      node_group_type  = "core"
    })]
  }

  #---------------------------------------------------------------
  # Kafka (Strimzi) Add-on
  #---------------------------------------------------------------
  enable_strimzi_kafka_operator = true
  strimzi_kafka_operator_helm_config = {
    name             = local.strimzi_kafka_name
    chart            = local.strimzi_kafka_name
    repository       = "https://strimzi.io/charts/"
    version          = "0.31.1"
    namespace        = local.strimzi_kafka_name
    create_namespace = true
    timeout          = 300
    #    wait             = false # This is critical setting. Check this issue -> https://github.com/hashicorp/terraform-provider-helm/issues/683
    values = [templatefile("${path.module}/helm-values/kafka-values.yaml", {
      operating_system = "linux"
      node_group_type  = "core"
    })]
    description = "Strimzi - Apache Kafka on Kubernetes"
  }
  tags = local.tags
}

#---------------------------------------------------------------
# GP3 Storage Class
#---------------------------------------------------------------
resource "kubectl_manifest" "gp3_sc" {
  yaml_body = <<-YAML
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
  name: gp3
parameters:
  fsType: xfs
  type: gp3
  encrypted: "true"
allowVolumeExpansion: true
provisioner: ebs.csi.aws.com
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
YAML

  depends_on = [module.eks_blueprints.eks_cluster_id]
}

#---------------------------------------------------------------
# Amazon Prometheus Workspace
#---------------------------------------------------------------
module "managed_prometheus" {
  source  = "terraform-aws-modules/managed-service-prometheus/aws"
  version = "~> 2.1"

  workspace_alias = local.name

  tags = local.tags
}

#---------------------------------------------------------------
# Install kafka cluster
# NOTE: Kafka Zookeeper and Broker pod creation may to 2 to 3 mins
#---------------------------------------------------------------
resource "kubectl_manifest" "kafka_namespace" {
  yaml_body  = file("./kafka-manifests/kafka-ns.yml")
  depends_on = [module.eks_blueprints.eks_cluster_id]
}

resource "kubectl_manifest" "kafka_cluster" {
  yaml_body  = file("./kafka-manifests/kafka-cluster.yml")
  depends_on = [kubectl_manifest.kafka_namespace, module.eks_blueprints_kubernetes_addons]
}

resource "kubectl_manifest" "kafka_metric_config" {
  yaml_body  = file("./kafka-manifests/kafka-metrics-configmap.yml")
  depends_on = [kubectl_manifest.kafka_cluster]
}

#---------------------------------------------------------------
# Grafana Dashboard for Kafka
# Login to Grafana dashboard
#1/ kubectl port-forward svc/grafana-service 3000:3000 -n grafana
#2/ Admin password: kubectl get secrets/grafana-admin-credentials --template={{.data.GF_SECURITY_ADMIN_PASSWORD}} -n grafana | base64 -D
#3/ Admin user: admin
#---------------------------------------------------------------
resource "helm_release" "grafana_operator" {
  name             = "grafana-operator"
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "grafana-operator"
  version          = "2.7.8"
  namespace        = "grafana"
  create_namespace = true

  depends_on = [module.eks_blueprints.eks_cluster_id]
}

resource "kubectl_manifest" "grafana_prometheus_datasource" {
  yaml_body = file("./grafana-manifests/grafana-operator-datasource-prometheus.yml")

  depends_on = [helm_release.grafana_operator]
}

resource "kubectl_manifest" "grafana_kafka_dashboard" {
  yaml_body = file("./grafana-manifests/grafana-operator-dashboard-kafka.yml")

  depends_on = [helm_release.grafana_operator]
}

resource "kubectl_manifest" "grafana_kafka_exporter_dashboard" {
  yaml_body = file("./grafana-manifests/grafana-operator-dashboard-kafka-exporter.yml")

  depends_on = [helm_release.grafana_operator]
}

resource "kubectl_manifest" "grafana_kafka_zookeeper_dashboard" {
  yaml_body = file("./grafana-manifests/grafana-operator-dashboard-kafka-zookeeper.yml")

  depends_on = [helm_release.grafana_operator]
}

resource "kubectl_manifest" "grafana_kafka_cruise_control_dashboard" {
  yaml_body = file("./grafana-manifests/grafana-operator-dashboard-kafka-cruise-control.yml")

  depends_on = [helm_release.grafana_operator]
}
