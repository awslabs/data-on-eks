#---------------------------------------------------------------
# Déploiement du ClusterIssuer Kubeflow
#---------------------------------------------------------------
provider "kustomization" {
  kubeconfig_path = "~/.kube/config"
}

# Déploiement Kubeflow
module "kubeflow" {
  source = "./modules/kubeflow"

  dex_client_secret = var.dex_client_secret

  depends_on = [
    module.istio
  ]

  providers = {
    kustomization = kustomization
    kubernetes    = kubernetes
    helm          = helm
  }
}