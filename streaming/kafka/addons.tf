
#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.14"
  role_name             = format("%s-%s", local.name, "ebs-csi-driver")
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  tags = local.tags
}

#---------------------------------------------------------------
# IRSA for VPC CNI
#---------------------------------------------------------------
module "vpc_cni_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.14"
  role_name             = format("%s-%s", local.name, "vpc-cni")
  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }
  tags = local.tags
}

#---------------------------------------------------------------
# Kubernetes Add-ons
#---------------------------------------------------------------
resource "aws_eks_addon" "vpc_cni" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "vpc-cni"
  service_account_role_arn = module.vpc_cni_irsa.iam_role_arn
  preserve                 = true
  depends_on               = [module.eks.eks_managed_node_groups]
}

resource "aws_eks_addon" "coredns" {
  cluster_name = module.eks.cluster_name
  addon_name   = "coredns"
  preserve     = true
  depends_on   = [module.eks.eks_managed_node_groups]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = module.eks.cluster_name
  addon_name   = "kube-proxy"
  preserve     = true
  depends_on   = [module.eks.eks_managed_node_groups]
}

resource "aws_eks_addon" "aws_ebs_csi_driver" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
  depends_on               = [module.eks.eks_managed_node_groups]
}

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
  depends_on = [aws_eks_addon.vpc_cni]
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
  depends_on  = [aws_eks_addon.vpc_cni]
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

  depends_on = [
    module.eks
  ]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  chart            = "cert-manager"
  repository       = "https://charts.jetstack.io"
  version          = "v1.10.0"
  namespace        = "cert-manager"
  create_namespace = true
  description      = "Cert Manager Add-on"
  wait             = true
  set {
    name  = "installCRDs"
    value = true
  }
  depends_on = [aws_eks_addon.vpc_cni]
}

#---------------------------------------------------------------
# Install Strimzi Operator
#---------------------------------------------------------------

resource "helm_release" "strimzi_operator" {
  name             = local.strimzi_kafka_name
  chart            = local.strimzi_kafka_name
  repository       = "https://strimzi.io/charts/"
  version          = "0.35.0"
  namespace        = local.strimzi_kafka_name
  create_namespace = true
  timeout          = 300
  #    wait             = false # This is critical setting. Check this issue -> https://github.com/hashicorp/terraform-provider-helm/issues/683
  values = [templatefile("${path.module}/helm-values/kafka-values.yaml", {
    operating_system = "linux"
    node_group_type  = "core"
  })]
  description = "Strimzi - Apache Kafka on Kubernetes"
  depends_on  = [module.eks.eks_managed_node_groups]
}

#---------------------------------------------------------------
# Install kafka cluster
# NOTE: Kafka Zookeeper and Broker pod creation may to 2 to 3 mins
#---------------------------------------------------------------
resource "kubectl_manifest" "kafka_namespace" {
  yaml_body  = file("./kafka-manifests/kafka-ns.yml")
  depends_on = [module.eks.cluster_id]
}

resource "kubectl_manifest" "kafka_cluster" {
  yaml_body  = file("./kafka-manifests/kafka-cluster.yml")
  depends_on = [helm_release.strimzi_operator]
}

resource "kubectl_manifest" "kafka_metric_config" {
  yaml_body  = file("./kafka-manifests/kafka-metrics-configmap.yml")
  depends_on = [helm_release.strimzi_operator]
}

#---------------------------------------------------------------
# Install Kafka Montoring Stack with Prometheus and Grafana
# 1- Grafana port-forward `kubectl port-forward svc/prometheus-grafana 8080:80 -n strimzi-kafka-operator`
# 2- Grafana Admin user: admin
#---------------------------------------------------------------

resource "helm_release" "kube_prometheus_stack" {
  name             = "prometheus-grafana"
  chart            = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  version          = "43.2.1"
  namespace        = local.strimzi_kafka_name
  create_namespace = true
  description      = "Kube Prometheus Grafana Stack Operator Chart"
  # timeout          = 600
  wait       = true
  values     = [templatefile("${path.module}/helm-values/prom-grafana-values.yaml", {})]
  depends_on = [aws_eks_addon.vpc_cni]
}

resource "kubectl_manifest" "podmonitor_cluster_operator_metrics" {
  yaml_body  = file("./monitoring-manifests/podmonitor-cluster-operator-metrics.yml")
  depends_on = [kubectl_manifest.kafka_namespace]
}

resource "kubectl_manifest" "podmonitor_entity_operator_metrics" {
  yaml_body  = file("./monitoring-manifests/podmonitor-entity-operator-metrics.yml")
  depends_on = [kubectl_manifest.kafka_namespace]
}

resource "kubectl_manifest" "podmonitor_kafka_resources_metrics" {
  yaml_body  = file("./monitoring-manifests/podmonitor-kafka-resources-metrics.yml")
  depends_on = [kubectl_manifest.kafka_namespace]
}

resource "kubectl_manifest" "grafana_strimzi_exporter_dashboard" {
  yaml_body  = file("./monitoring-manifests/grafana-strimzi-exporter-dashboard.yml")
  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubectl_manifest" "grafana_strimzi_kafka_dashboard" {
  yaml_body  = file("./monitoring-manifests/grafana-strimzi-kafka-dashboard.yml")
  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubectl_manifest" "grafana_strimzi_operators_dashboard" {
  yaml_body  = file("./monitoring-manifests/grafana-strimzi-operators-dashboard.yml")
  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubectl_manifest" "grafana_strimzi_zookeeper_dashboard" {
  yaml_body  = file("./monitoring-manifests/grafana-strimzi-zookeeper-dashboard.yml")
  depends_on = [helm_release.kube_prometheus_stack]
}
