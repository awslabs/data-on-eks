#---------------------------------------------------------------
# agentgateway (OSS) — AI-aware Gateway API implementation
#
# Installs, via ArgoCD:
#   1. Kubernetes Gateway API CRDs (standard channel, incl. GRPCRoute)
#   2. agentgateway CRDs (AgentgatewayParameters/Policy/Backend/Model)
#   3. agentgateway control plane (creates the `agentgateway` GatewayClass)
#
# Gateways, routes and policies are workload config and live with the
# data stack (e.g. data-stacks/ray-on-eks/examples/agw-demo/gateway/).
# The generated proxy Service type is set per Gateway through
# AgentgatewayParameters (spec.service.spec.type) — keep it ClusterIP
# unless you deliberately want an AWS load balancer.
#
# Ref: https://agentgateway.dev/docs/kubernetes/latest/documentation/install/helm/
#---------------------------------------------------------------
locals {
  agentgateway_namespace = "agentgateway-system"
  agentgateway_version   = "1.6.0"
  gateway_api_version    = "v1.6.0"
}

# agentgateway charts are published as OCI artifacts; ArgoCD needs an
# OCI-enabled Helm repository entry to pull them.
resource "kubectl_manifest" "agentgateway_oci_repo" {
  count = var.enable_agentgateway ? 1 : 0

  yaml_body = templatefile("${path.module}/manifests/agentgateway/argocd-oci-repo.yaml", {})

  depends_on = [helm_release.argocd]
}

resource "kubectl_manifest" "gateway_api_crds" {
  count = var.enable_agentgateway ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/gateway-api-crds.yaml", {
    gateway_api_version = local.gateway_api_version
  })

  depends_on = [helm_release.argocd]
}

resource "kubectl_manifest" "agentgateway_crds" {
  count = var.enable_agentgateway ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/agentgateway-crds.yaml", {
    agentgateway_version = local.agentgateway_version
    namespace            = local.agentgateway_namespace
  })

  depends_on = [kubectl_manifest.agentgateway_oci_repo]
}

# The controller watches Gateway API and agentgateway CRDs at startup; give
# ArgoCD time to sync both CRD apps before the controller app is created.
resource "time_sleep" "agentgateway_crds" {
  count = var.enable_agentgateway ? 1 : 0

  create_duration = "60s"

  depends_on = [
    kubectl_manifest.gateway_api_crds,
    kubectl_manifest.agentgateway_crds,
  ]
}

resource "kubectl_manifest" "agentgateway" {
  count = var.enable_agentgateway ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/agentgateway.yaml", {
    agentgateway_version = local.agentgateway_version
    namespace            = local.agentgateway_namespace
    user_values_yaml     = indent(8, yamlencode(yamldecode(templatefile("${path.module}/helm-values/agentgateway.yaml", {}))))
  })

  depends_on = [time_sleep.agentgateway_crds]
}
