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
  enable_aws_for_fluentbit            = true
  enable_aws_load_balancer_controller = true
  enable_prometheus                   = true
  enable_grafana                      = true

  # Install Cert Manager

  enable_cert_manager = true

  # Kafka (Strimzi) add-on with custom helm config
  enable_k8ssandra_operator = true

  k8ssandra_operator_helm_config = {
    name             = local.k8ssandra_operator_name
    chart            = "k8ssandra-operator"
    repository       = "https://helm.k8ssandra.io/stable"
    version          = "0.39.1"
    namespace        = local.k8ssandra_operator_name
    create_namespace = true
    timeout          = 360
    values           = [templatefile("${path.module}/values.yaml", {})]
    description      = "K8ssandra Operator to run Cassandra DB on Kubernetes"
  }
  tags = local.tags
}

#---------------------------------------------------------------
# Install kafka cluster
#---------------------------------------------------------------

resource "kubectl_manifest" "cassandra-namespace" {
  yaml_body = file("./kubernetes-manifests/cassandra-ns.yml")
}

resource "kubectl_manifest" "cassandra-cluster" {
  yaml_body = file("./kubernetes-manifests/cassandra-manifests/cassandra-cluster.yml")
}

# resource "kubectl_manifest" "grafana-prometheus-datasource" {
#   yaml_body = file("./kubernetes-manifests/grafana-manifests/grafana-operator-datasource-prometheus.yml")
# }

resource "kubectl_manifest" "grafana-cassandra-dashboard" {
  yaml_body = file("./kubernetes-manifests/cassandra-manifests/grafana-dashboards.yml")
}
