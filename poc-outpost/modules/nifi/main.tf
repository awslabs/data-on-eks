locals {
  # Récupération locale car repo OCI non supporté par HELM actuellement dans TF
  # oci://registry-1.docker.io/bitnamicharts/zookeeper -y-> helm pull oci://registry-1.docker.io/bitnamicharts/zookeeper --version 13.8.5
  chart_zookeper     = "./charts/zookeeper-13.8.5.tgz"
  # Récupération locale car repo OCI non supporté par HELM actuellement dans TF
  # oci://ghcr.io/konpyutaika/helm-charts/nifikop -y-> helm pull oci://ghcr.io/konpyutaika/helm-charts/nifikop --version 1.14.1
  chart_nifikop     = "./charts/nifikop-1.14.1.tgz"
  zookeeper_values = file("${path.module}/helm-values/zookeeper-value.yaml") 
  nifikop_values = file("${path.module}/helm-values/nifikop-value.yaml") 
  region = "us-west-2"
}

# Data source pour le cluster EKS
data "aws_eks_cluster" "this" {
  name = var.eks_cluster_name
}
# Data source pour l'authentification (token)
data "aws_eks_cluster_auth" "this" {
  name = var.eks_cluster_name
}

output "cluster" {
    value = data.aws_eks_cluster.this.endpoint
}

##########################
# Installation Zookeeper
##########################
resource "kubernetes_namespace_v1" "zookeeper" {
  metadata {
    name = "zookeeper"
  }
}
module "zookeeper" {
  source = "./modules/helm"

  helm_releases = {
    zookeeper = {
      chart         = local.chart_zookeper
      name          = "zookeeper"
      namespace     = kubernetes_namespace_v1.zookeeper.metadata[0].name
      values =  [local.zookeeper_values]
    }
  }
}

#################################
# Installation Operateur nifikop
#################################
resource "kubernetes_namespace_v1" "nifikop" {
  metadata {
    name = "nifi"
  }
}
module "nifikop" {
  source = "./modules/helm"

  helm_releases = {
    nifikop = {
      chart         = local.chart_nifikop
      name          = "nifikop"
      namespace     = kubernetes_namespace_v1.nifikop.metadata[0].name
      values =  [local.nifikop_values]
    }
  }
}


  #################################
  # Déploiement Cluster Nifi
  #################################
resource "kubernetes_config_map_v1" "nifi_logback" {
  metadata {
    name      = "nifi-logback"
    namespace = kubernetes_namespace_v1.nifikop.metadata[0].name
  }

  data = {
    "logback.xml" = file("${path.module}/template/logback.xml")
  }
}

  # Application des manifests non variabilisés
locals {
  manifest_files = fileset("${path.module}/template", "*.yaml")
  parsed_manifests = {
    for file in local.manifest_files :
    file => yamldecode(file("${path.module}/template/${file}"))
  }
}
resource "kubernetes_manifest" "othermanifests" {
  for_each = local.parsed_manifests
  manifest = each.value
}