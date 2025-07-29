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

#---------------------------------------------------------------
# Déploiement de OAuth2 proxy
#---------------------------------------------------------------
module "oauth2_proxy" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/common/oauth2-proxy/overlays/m2m-dex-and-kind"
  helminstallname ="oauth2proxy"
  namespace = "oauth2-proxy"
  createnamespace = true

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }
}

#---------------------------------------------------------------
# Déploiement de DEX
#---------------------------------------------------------------
module "dex" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/common/dex/overlays/oauth2-proxy"
  helminstallname ="dex"
  namespace = "auth"
  createnamespace = true

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }
}

#---------------------------------------------------------------
# Déploiement de Knative Serving 1/3
#---------------------------------------------------------------
module "knative1" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/common/knative/knative-crd"
  helminstallname ="knative-serving-1"
  namespace = "knative-serving"
  createnamespace = true

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.dex]
}
#---------------------------------------------------------------
# Déploiement de Knative Serving 2/3
#---------------------------------------------------------------
module "knative2" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/common/knative/knative-serving/overlays/gateways"
  helminstallname ="knative-serving-2"
  namespace = "knative-serving"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.knative1]
}
#---------------------------------------------------------------
# Déploiement de Knative Serving 3/3
#---------------------------------------------------------------
module "knative3" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/common/istio-1-24/cluster-local-gateway/base"
  helminstallname ="knative-serving-3"
  namespace = "knative-serving"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.knative2]
}

#---------------------------------------------------------------
# Déploiement des Network Policies
#---------------------------------------------------------------
module "netpol" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/common/networkpolicies/base"
  helminstallname ="netpol"
  namespace = "kubeflow"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.knative3]
}

#---------------------------------------------------------------
# Déploiement des Rôles
#---------------------------------------------------------------
module "roles" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/common/kubeflow-roles/base"
  helminstallname ="roles"
  namespace = "kubeflow"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.netpol]
}

#---------------------------------------------------------------
# Déploiement des ressources istio
#---------------------------------------------------------------
module "istioressources" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/common/istio-1-24/kubeflow-istio-resources/base"
  helminstallname ="istioressources"
  namespace = "kubeflow"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.roles]
}

#---------------------------------------------------------------
# Déploiement Metacontroller
#---------------------------------------------------------------
module "metacontroller" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/apps/pipeline/upstream/third-party/metacontroller/base"
  helminstallname ="metacontroller"
  namespace = "kubeflow"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.istioressources]
}

#---------------------------------------------------------------
# Déploiement Kubeflow Pipelines
#---------------------------------------------------------------
module "kfpipelines" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/apps/pipeline/upstream/env/cert-manager/platform-agnostic-multi-user"
  helminstallname ="kfpipelines"
  namespace = "kubeflow"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.metacontroller]
}

#---------------------------------------------------------------
# Déploiement KServer
#---------------------------------------------------------------
# module "kserve" {
#   source = "../kustomize"
#   # Variables
#   overlayfolder= "${path.module}/manifests/apps/kserve/kserve"
#   helminstallname ="kserve"
#   namespace = "kubeflow"
#   createnamespace = false

#   providers = {
#     kubernetes = kubernetes
#     kustomization = kustomization
#     helm = helm
#   }

#   depends_on = [module.kfpipelines]
# }

# #---------------------------------------------------------------
# # Déploiement Model Web Application
# #---------------------------------------------------------------
# module "modelwebapp" {
#   source = "../kustomize"
#   # Variables
#   overlayfolder= "${path.module}/manifests/ apps/kserve/models-web-app/overlays/kubeflow"
#   helminstallname ="modelwebapp"
#   namespace = "kubeflow"
#   createnamespace = false

#   providers = {
#     kubernetes = kubernetes
#     kustomization = kustomization
#     helm = helm
#   }

#   depends_on = [module.kserve]
# }