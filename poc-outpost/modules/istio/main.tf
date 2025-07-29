# Creation du namespace
resource "kubernetes_namespace_v1" "istio_system" {
  metadata {
    name = var.namespace
  }
}

locals {
  istio_chart_url     = "https://istio-release.storage.googleapis.com/charts"
  istio_chart_version = "1.26.2"
  region              = var.region
}

# Data source pour le cluster EKS
data "aws_eks_cluster" "this" {
  name = var.eks_cluster_name
}
# Data source pour l'authentification (token)
data "aws_eks_cluster_auth" "this" {
  name = var.eks_cluster_name
}

module "istio" {
  source = "../helm"

  helm_releases = {
    istio-cni = {
      chart         = "cni"
      chart_version = local.istio_chart_version
      repository    = local.istio_chart_url
      name          = "istio-cni"
      namespace     = kubernetes_namespace_v1.istio_system.metadata[0].name
    }
    istio-base = {
      chart         = "base"
      chart_version = local.istio_chart_version
      repository    = local.istio_chart_url
      name          = "istio-base"
      namespace     = kubernetes_namespace_v1.istio_system.metadata[0].name
    }
    istiod = {
      chart         = "istiod"
      chart_version = local.istio_chart_version
      repository    = local.istio_chart_url
      name          = "istiod"
      namespace     = kubernetes_namespace_v1.istio_system.metadata[0].name
      values = [
          yamlencode({
            meshConfig = {
              accessLogFile           = "/dev/stdout"
              enablePrometheusMerge   = true
              rootNamespace           = "istio-system"
              tcpKeepalive = {
                interval = "5s"
                probes   = 3
                time     = "10s"
              }
              trustDomain = "cluster.local"
              defaultConfig = {
                discoveryAddress = "istiod.istio-system.svc:15012"
                proxyMetadata    = {}
                tracing          = {}
              }
              extensionProviders = [
                {
                  name = "oauth2-proxy"
                  envoyExtAuthzHttp = {
                    service  = "oauth2-proxy.oauth2-proxy.svc.cluster.local"
                    port     = 80
                    includeRequestHeadersInCheck = [
                      "authorization",
                      "cookie"
                    ]
                    headersToUpstreamOnAllow = [
                      "authorization",
                      "path",
                      "x-auth-request-email",
                      "x-auth-request-groups",
                      "x-auth-request-user"
                    ]
                    headersToDownstreamOnDeny = [
                      "content-type",
                      "set-cookie"
                    ]
                  }
                }
              ]
            }
            meshNetworks = {
              networks = {}
            }
          })
        ]
    }
    istio-ingress = {
      chart            = "gateway"
      chart_version    = local.istio_chart_version
      repository       = local.istio_chart_url
      name             = "istio-ingress"
      namespace        = "istio-ingress" # per https://github.com/istio/istio/blob/master/manifests/charts/gateways/istio-ingress/values.yaml#L2
      create_namespace = true

      values = [
        yamlencode(
          {
            labels = {
              istio = "ingressgateway"
            }
            service = {
              annotations = {
                "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
                "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
                "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
                "service.beta.kubernetes.io/aws-load-balancer-attributes"      = "load_balancing.cross_zone.enabled=true"
              }
            }
          }
        )
      ]
    }
  }
}
