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
