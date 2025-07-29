locals {

}

#---------------------------------------------------------------
# Déploiement du ClusterIssuer Kubeflow
#---------------------------------------------------------------
module "clusterissuer_kubeflow" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/common/cert-manager/kubeflow-issuer/base"
  helminstallname ="kubeflowcertissuer"
  namespace = "kubeflow"
  createnamespace = true

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }
}

## Installation d'une Ingress GW dédiée à Kubeflow
## (Pour simplifier l'intégration avec les softs hors Kubeflow, utilisation du même SA que celle déjà en place)
## La GW est "kubeflow-ingressgateway"
resource "helm_release" "kubeflowgw" {
  name             = "kubeflow-istio-ingress"
  namespace        = "istio-ingress"
  create_namespace = false

  repository        = "https://istio-release.storage.googleapis.com/charts"
  chart             = "gateway"
  version           = "1.26.2"
  dependency_update = true
  upgrade_install   = true
  wait              = true

  values = [
    templatefile("${path.module}/helm-values/kubeflow-ingress-values.yaml", {})
  ]
}
