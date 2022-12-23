#---------------------------------------------------------------
# Kubernetes Add-ons
#---------------------------------------------------------------
module "eks_blueprints_kubernetes_addons" {
  # source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.15.0"
  source = "/home/aly/terraform-aws-eks-blueprints/modules/kubernetes-addons?ref=k8ssandra_operator"

  # eks_cluster_id = local.name
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

  # cert_manager_helm_config = {
  #   name        = "cert-manager"
  #   chart       = "cert-manager"
  #   repository  = "https://charts.jetstack.io"
  #   version     = "v1.10.0"
  #   namespace   = local.k8ssandra_operator_name
  #   description = "Cert Manager Add-on"
  # }

  # K8ssandra Operator add-on with custom helm config
  enable_k8ssandra_operator = true

  k8ssandra_operator_helm_config = {
    name             = local.k8ssandra_operator_name
    chart            = "k8ssandra-operator"
    repository       = "https://helm.k8ssandra.io/stable"
    version          = "0.39.1"
    namespace        = local.k8ssandra_operator_name
    create_namespace = true
    timeout          = 360
    values           = [templatefile("${path.module}/helm-values/values.yaml", {})]
    description      = "K8ssandra Operator to run Cassandra DB on Kubernetes"
  }
  tags = local.tags
}

#---------------------------------------------------------------
# Install kafka cluster
#---------------------------------------------------------------

resource "kubectl_manifest" "cassandra-namespace" {
  yaml_body = file("./examples/cassandra-ns.yml")
}

resource "kubectl_manifest" "cassandra-cluster" {
  yaml_body = file("./examples/cassandra-manifests/cassandra-cluster.yml")
}

# resource "kubectl_manifest" "grafana-prometheus-datasource" {
#   yaml_body = file("./kubernetes-manifests/grafana-manifests/grafana-operator-datasource-prometheus.yml")
# }

resource "kubectl_manifest" "grafana-cassandra-dashboard" {
  yaml_body = file("./examples/cassandra-manifests/grafana-dashboards.yml")
}
