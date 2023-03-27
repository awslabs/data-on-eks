#---------------------------------------------------------------
# Kubernetes Add-ons
#---------------------------------------------------------------

#---------------------------------------------------------------
# Cluster Autoscaler
#---------------------------------------------------------------

resource "helm_release" "cluster-autoscaler" {
    name       = "cluster-autoscaler"
    repository = "https://kubernetes.github.io/autoscaler" # (Optional) Repository URL where to locate the requested chart.
    chart      = "cluster-autoscaler"
    version    = "9.21.0"
    namespace  = "kube-system"
    timeout    = "300"
    values = [templatefile("${path.module}/helm-values/cluster-autoscaler-values.yaml", {
      aws_region     = var.region,
      eks_cluster_id = module.eks.cluster_name
    })]
    # depends_on = [module.eks.cluster_addons]
}

#---------------------------------------------------------------
# Metrics Server
#---------------------------------------------------------------
resource "helm_release" "metrics-server" {
    name        = "metrics-server"
    description = "The Amazon Elastic Block Store Container Storage Interface (CSI) Driver provides a CSI interface used by Container Orchestrators to manage the lifecycle of Amazon EBS volumes."
    chart       = "metrics-server"
    repository  = "https://kubernetes-sigs.github.io/metrics-server/"
    namespace   = "kube-system"
    wait        = true
    # set {
    #     name  = "tolerations"
    #     value = "[{ key = \"dedicated\", value = \"cassandra\", effect = \"NO_SCHEDULE\" }]"
    # }
  # depends_on = [module.eks.cluster_addons]
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

  # depends_on = [module.eks.cluster_addons]
}

resource "helm_release" "cert_manager" {
  name  = "cert-manager"
  chart = "cert-manager"
  repository  = "https://charts.jetstack.io"
  version     = "v1.10.0"
  namespace   = "cert-manager"
  create_namespace = true
  description = "Cert Manager Add-on"
  wait        = true
  set {
    name  = "installCRDs"
    value = true
  }
  # depends_on = [module.eks.cluster_addons]
}

#---------------------------------------------------------------
# Install Strimzi Operator
#---------------------------------------------------------------

resource "helm_release" "strimzi-operator" {
    name             = local.strimzi_kafka_name
    chart            = local.strimzi_kafka_name
    repository       = "https://strimzi.io/charts/"
    version          = "0.34.0"
    namespace        = local.strimzi_kafka_name
    create_namespace = true
    timeout          = 300
    #    wait             = false # This is critical setting. Check this issue -> https://github.com/hashicorp/terraform-provider-helm/issues/683
    values = [templatefile("${path.module}/helm-values/kafka-values.yaml", {
      operating_system = "linux"
      node_group_type  = "core"
    })]
    description = "Strimzi - Apache Kafka on Kubernetes"
    depends_on = [
      # module.eks.cluster_addons
    ]
  }

#---------------------------------------------------------------
# Install kafka cluster
# NOTE: Kafka Zookeeper and Broker pod creation may to 2 to 3 mins
#---------------------------------------------------------------
resource "kubectl_manifest" "kafka_namespace" {
  yaml_body  = file("./kafka-manifests/kafka-ns.yml")
  # depends_on = [helm_release.strimzi-operator]
}

resource "kubectl_manifest" "kafka_cluster" {
  yaml_body  = file("./kafka-manifests/kafka-cluster.yml")
  # depends_on = [kubectl_manifest.kafka_namespace, module.eks]
}

resource "kubectl_manifest" "kafka_metric_config" {
  yaml_body  = file("./kafka-manifests/kafka-metrics-configmap.yml")
  # depends_on = [kubectl_manifest.kafka_cluster]
}

resource "kubectl_manifest" "grafana_dashboards" {
  yaml_body = file("./kafka-manifests/grafana-dashboards.yml")
}

#---------------------------------------------------------------
# Grafana Dashboard for Kafka
# Login to Grafana dashboard
#1/ kubectl port-forward svc/grafana-service 3000:3000 -n grafana
#2/ Admin password: kubectl get secrets/grafana-admin-credentials --template={{.data.GF_SECURITY_ADMIN_PASSWORD}} -n grafana | base64 -D
#3/ Admin user: admin
#---------------------------------------------------------------

resource "helm_release" "kube_prometheus_stack" {
  name             = "prometheus-grafana"
  chart            = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  version          = "43.2.1"    
  namespace        = local.k8ssandra_operator_name
  create_namespace = true
  description      = "Kube Prometheus Grafana Stack Operator Chart"
  timeout          = 600
  wait             = true
  values           = [templatefile("${path.module}/helm-values/prom-grafana-values.yaml", {})]
  depends_on = [module.eks.cluster_id]
}

resource "helm_release" "grafana_operator" {
  name             = "grafana-operator"
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "grafana-operator"
  version          = "2.7.8"
  namespace        = "grafana"
  create_namespace = true
  # wait             = true
  # depends_on = [module.eks.cluster_addons]
}

#---------------------------------------------------------------
# Install Grafana Dashboards
#---------------------------------------------------------------

resource "kubectl_manifest" "grafana_prometheus_datasource" {
  yaml_body = file("./grafana-manifests/grafana-operator-datasource-prometheus.yml")

  # depends_on = [helm_release.grafana_operator]
}

resource "kubectl_manifest" "grafana_kafka_dashboard" {
  yaml_body = file("./grafana-manifests/grafana-operator-dashboard-kafka.yml")

  # depends_on = [helm_release.grafana_operator]
}

resource "kubectl_manifest" "grafana_kafka_exporter_dashboard" {
  yaml_body = file("./grafana-manifests/grafana-operator-dashboard-kafka-exporter.yml")

  # depends_on = [helm_release.grafana_operator]
}

resource "kubectl_manifest" "grafana_kafka_zookeeper_dashboard" {
  yaml_body = file("./grafana-manifests/grafana-operator-dashboard-kafka-zookeeper.yml")

  # depends_on = [helm_release.grafana_operator]
}

resource "kubectl_manifest" "grafana_kafka_cruise_control_dashboard" {
  yaml_body = file("./grafana-manifests/grafana-operator-dashboard-kafka-cruise-control.yml")

  # depends_on = [helm_release.grafana_operator]
}
