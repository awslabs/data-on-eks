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
    # values      = ["${path.module}/helm-values/metrics-server-values.yaml"]
    # set {
    #     name  = "tolerations"
    #     value = [{ key = "dedicated", value = "cassandra", effect = "NO_SCHEDULE" }]
    # }
  depends_on = [module.eks.cluster_id]
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

  depends_on = [module.eks.cluster_id]
}

#---------------------------------------------------------------
# Install K8ssandra Operator
#---------------------------------------------------------------

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
  depends_on = [module.eks.cluster_id]
}

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

resource "helm_release" "k8ssandra_operator" {
  name  = "k8ssandra-operator"
  chart = "k8ssandra-operator"
  repository  = "https://helm.k8ssandra.io/stable"
  version     = "0.39.1"
  namespace   = "k8ssandra-operator"
  create_namespace = true
  description = "K8ssandra Operator to run Cassandra DB on Kubernetes"
  wait        = true
  values      = [templatefile("${path.module}/helm-values/values.yaml", {})]
  depends_on = [helm_release.cert_manager]
}

#---------------------------------------------------------------
# Install Cassandra Cluster
#---------------------------------------------------------------

resource "kubectl_manifest" "cassandra_namespace" {
  
  yaml_body = file("./examples/cassandra-manifests/cassandra-ns.yml")
  depends_on = [helm_release.k8ssandra_operator]
}

resource "kubectl_manifest" "cassandra_cluster" {
  yaml_body = file("./examples/cassandra-manifests/cassandra-cluster.yml")
  depends_on = [helm_release.k8ssandra_operator]
}

resource "kubectl_manifest" "grafana_cassandra_dashboard" {
  yaml_body = file("./examples/cassandra-manifests/grafana-dashboards.yml")
  depends_on = [helm_release.k8ssandra_operator]
}
