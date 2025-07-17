# ---------------------------------------------------------------
# certificat
# ---------------------------------------------------------------
resource "kubectl_manifest" "certificate" {

  yaml_body = templatefile("${path.module}/helm-values/certificate.yaml", {
    name = var.virtual_service_name
    cluster_issuer_name = var.cluster_issuer_name
    dns_name = var.dns_name
  })
}

# ---------------------------------------------------------------
# gateway
# ---------------------------------------------------------------
resource "kubectl_manifest" "gateway" {

  yaml_body = templatefile("${path.module}/helm-values/gateway.yaml", {
    name = var.virtual_service_name
    namespace = var.namespace
    secret_certificate_name = kubectl_manifest.certificate.name
    dns_name = var.dns_name
  })

  depends_on = [
    kubectl_manifest.certificate
  ]
}

# ---------------------------------------------------------------
# virtual service
# ---------------------------------------------------------------
resource "kubectl_manifest" "virtual_service" {

  yaml_body = templatefile("${path.module}/helm-values/virtualService.yaml", {
    name = var.virtual_service_name
    namespace = var.namespace
    secret_certificate_name = kubectl_manifest.certificate.name
    gateway_name = kubectl_manifest.gateway.name
    dns_name = var.dns_name
    service_name = var.service_name
    service_port = var.service_port
  })

  depends_on = [
    kubectl_manifest.gateway
  ]
}


locals {

  tags = var.tags
}

