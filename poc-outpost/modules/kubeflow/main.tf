locals {
  dex_configmap_patch = <<-EOT
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: dex
      namespace: auth
    data:
      config.yaml: |
        issuer: https://${var.kubeflow_domain}/dex
        storage:
          type: kubernetes
          config:
            inCluster: true
        web:
          http: 0.0.0.0:5556
        logger:
          level: "debug"
          format: text
        oauth2:
          skipApprovalScreen: true
        enablePasswordDB: false
        connectors:
        - type: oidc
          id: keycloak
          name: keycloak
          config:
            issuer: https://${var.keycloak_domain}/realms/${var.keycloak_realm}
            clientID: ${var.dex_client_id}
            clientSecret: ${var.dex_client_secret}
            redirectURI: https://${var.kubeflow_domain}/dex/callback
        staticClients:
        - idEnv: OIDC_CLIENT_ID
          redirectURIs: ["/oauth2/callback"]
          name: 'Dex Login Application'
          secretEnv: OIDC_CLIENT_SECRET
  EOT
}

locals {
  oauth2proxy_cfg = <<-EOT
    provider = "oidc"
    oidc_issuer_url = "http://${var.kubeflow_domain}/dex"
    scope = "profile email groups openid"
    email_domains = [ "*" ]
    upstreams = [ "static://200" ]
    skip_auth_routes = [
      "^/dex/",
    ]
    api_routes = [
      "/api/",
      "/apis/",
      "^/ml_metadata",
    ]
    skip_oidc_discovery = true
    login_url = "/dex/auth"
    redeem_url = "http://${var.kubeflow_domain}/dex/token"
    oidc_jwks_url = "http://${var.kubeflow_domain}/dex/keys"
    skip_provider_button = false
    provider_display_name = "Dex"
    custom_sign_in_logo = "/custom-theme/kubeflow-logo.svg"
    banner = "-"
    footer = "-"
    prompt = "none"
    set_authorization_header = true
    set_xauthrequest = true
    cookie_name = "oauth2_proxy_kubeflow"
    cookie_expire = "24h"
    cookie_refresh = 0
    code_challenge_method = "S256"
    redirect_url = "/oauth2/callback"
    relative_redirect_url = true
  EOT
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

# Génération des fichiers pour kubeflow
# Fichier modules/kubeflow/manifests/common/oauth2-proxy/base-otl/oauth2_proxy.cfg
# Fichier modules/kubeflow/manifests/common/dex/overlays/oauth2-proxy/config-map
resource "local_file" "dex_patch" {
  content  = local.dex_configmap_patch
  filename = "${path.module}/manifests/common/dex/overlays/oauth2-proxy/config-map.yaml"
}

resource "local_file" "oauth2proxy_cfg" {
  content  = local.oauth2proxy_cfg
  filename = "${path.module}/manifests/common/oauth2-proxy/base/oauth2_proxy.cfg"
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

  depends_on = [local_file.dex_patch,local.oauth2proxy_cfg]
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

  depends_on = [local_file.dex_patch,local.oauth2proxy_cfg]
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
# Déploiement KServer 1/2
#---------------------------------------------------------------
module "kserve1" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/apps/kserve/kserve"
  helminstallname ="kserve1"
  namespace = "kubeflow"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.kfpipelines]
}

#---------------------------------------------------------------
# Déploiement KServer 2/2
#---------------------------------------------------------------
module "kserve2" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/apps/kserve/kserver-clusterressources"
  helminstallname ="kserve2"
  namespace = "kubeflow"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.kserve1]
}

#---------------------------------------------------------------
# Déploiement Model Web Application
#---------------------------------------------------------------
module "modelwebapp" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/apps/kserve/models-web-app/overlays/kubeflow"
  helminstallname ="modelwebapp"
  namespace = "kubeflow"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.kserve2]
}

#---------------------------------------------------------------
# Déploiement Katib
#---------------------------------------------------------------
module "katib" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/apps/katib/upstream/installs/katib-with-kubeflow"
  helminstallname ="katib"
  namespace = "kubeflow"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.modelwebapp]
}

#---------------------------------------------------------------
# Déploiement Dashboard
#---------------------------------------------------------------
module "dashboard" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/apps/centraldashboard/overlays/oauth2-proxy"
  helminstallname ="dashboard"
  namespace = "kubeflow"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.katib]
}

#---------------------------------------------------------------
# Déploiement Admission Webhook
#---------------------------------------------------------------
module "admwebhook" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/apps/admission-webhook/upstream/overlays/cert-manager"
  helminstallname ="admwebhook"
  namespace = "kubeflow"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.dashboard]
}

#---------------------------------------------------------------
# Déploiement Notebook controller
#---------------------------------------------------------------
module "notebookcontroller" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/apps/jupyter/notebook-controller/upstream/overlays/kubeflow"
  helminstallname ="notebookcontroller"
  namespace = "kubeflow"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.admwebhook]
}

#---------------------------------------------------------------
# Déploiement Jupyter
#---------------------------------------------------------------
module "jupyter" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/apps/jupyter/jupyter-web-app/upstream/overlays/istio"
  helminstallname ="jupyter"
  namespace = "kubeflow"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.notebookcontroller]
}

#---------------------------------------------------------------
# Déploiement PVCViewer
#---------------------------------------------------------------
module "pvcviewer" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/apps/pvcviewer-controller/upstream/base"
  helminstallname ="pvcviewer"
  namespace = "kubeflow"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.jupyter]
}

#---------------------------------------------------------------
# Déploiement Kube flow acccess management
#---------------------------------------------------------------
module "kfam" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/apps/profiles/upstream/overlays/kubeflow"
  helminstallname ="kfam"
  namespace = "kubeflow"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.pvcviewer]
}

#---------------------------------------------------------------
# Déploiement Volume Web app
#---------------------------------------------------------------
module "volapp" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/apps/volumes-web-app/upstream/overlays/istio"
  helminstallname ="volapp"
  namespace = "kubeflow"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.kfam]
}

#---------------------------------------------------------------
# Déploiement Tensorboard webapp
#---------------------------------------------------------------
module "tensorboardwebapp" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/apps/tensorboard/tensorboards-web-app/upstream/overlays/istio"
  helminstallname ="tensorboardwebapp"
  namespace = "kubeflow"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.volapp]
}

#---------------------------------------------------------------
# Déploiement Tensorboard Controller
#---------------------------------------------------------------
module "tensorboardcontroller" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/apps/tensorboard/tensorboard-controller/upstream/overlays/kubeflow"
  helminstallname ="tensorboardcontroller"
  namespace = "kubeflow"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.tensorboardwebapp]
}

#---------------------------------------------------------------
# Déploiement Training operator
#---------------------------------------------------------------
module "trainingoperator" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/apps/training-operator/upstream/overlays/kubeflow"
  helminstallname ="trainingoperator"
  namespace = "kubeflow"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.tensorboardcontroller]
}

#---------------------------------------------------------------
# Spark  operator (deja installé par ailleurs)
#---------------------------------------------------------------
# module "sparkoperator" {
#   source = "../kustomize"
#   # Variables
#   overlayfolder= "${path.module}/manifests/apps/spark/spark-operator/overlays/kubeflow"
#   helminstallname ="sparkoperator"
#   namespace = "kubeflow"
#   createnamespace = false

#   providers = {
#     kubernetes = kubernetes
#     kustomization = kustomization
#     helm = helm
#   }

#   depends_on = [module.trainingoperator]
# }

#---------------------------------------------------------------
# user namespaces
#---------------------------------------------------------------
module "userns" {
  source = "../kustomize"
  # Variables
  overlayfolder= "${path.module}/manifests/common/user-namespace/base"
  helminstallname ="userns"
  namespace = "kubeflow"
  createnamespace = false

  providers = {
    kubernetes = kubernetes
    kustomization = kustomization
    helm = helm
  }

  depends_on = [module.trainingoperator]
}

#---------------------------------------------------------------
# Déploiement certificat let's encrypt
#---------------------------------------------------------------
locals {
  manifests = {
    certificat = yamldecode(templatefile("${path.module}/templates/certificate.yaml.tpl", {
      kubeflow_domain = var.kubeflow_domain
    }))
  }
}
resource "helm_release" "certificatkubeflow" {
  name             = "certificatkubeflow"
  namespace        = "istio-ingress"
  create_namespace = false

  repository        = "https://bedag.github.io/helm-charts"
  chart             = "raw"
  version           = "2.0.0"
  dependency_update = true
  upgrade_install   = true
  wait              = true

  values = [
    yamlencode({
      resources = local.manifests
    })
  ]
}