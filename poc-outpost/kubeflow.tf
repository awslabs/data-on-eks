#---------------------------------------------------------------
# Déploiement du ClusterIssuer Kubeflow
#---------------------------------------------------------------
provider "kustomization" {
  kubeconfig_path= "~/.kube/config"
}

# Déploiement Kubeflow
module "kubeflow" {
  source = "./modules/kubeflow"

  depends_on = [
    module.istio
  ]

  providers = {
    kustomization = kustomization
    kubernetes    = kubernetes
    helm= helm
  }
}