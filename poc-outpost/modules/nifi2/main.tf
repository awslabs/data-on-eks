locals {
  # Récupération locale car repo OCI non supporté par HELM actuellement dans TF
  # En theorie
  # helm install --wait commons-operator oci://oci.stackable.tech/sdp-charts/commons-operator --version 25.7.0
  # helm install --wait secret-operator oci://oci.stackable.tech/sdp-charts/secret-operator --version 25.7.0
  # helm install --wait listener-operator oci://oci.stackable.tech/sdp-charts/listener-operator --version 25.7.0
  # helm install --wait nifi-operator oci://oci.stackable.tech/sdp-charts/nifi-operator --version 25.7.0
  chart_common     = "${path.module}/charts/commons-operator-25.7.0.tgz"
  chart_listener   = "${path.module}/charts/listener-operator-25.7.0.tgz"
  chart_secret =  "${path.module}/charts/secret-operator-25.7.0.tgz"
  chart_nifi =  "${path.module}/charts/nifi-operator-25.7.0.tgz"
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

########################################
# Installation Des opérateurs Stackable
########################################
resource "kubernetes_namespace_v1" "nifi2" {
  metadata {
    name = var.nifi_namespace
  }
}

module "common" {
  source = "../../modules/helm"

  helm_releases = {
    common-stackable = {
      chart         = local.chart_common
      name          = "common-stackable"
      namespace     = kubernetes_namespace_v1.nifi2.metadata[0].name
    }
    listener-stackable = {
      chart         = local.chart_listener
      name          = "listener-stackable"
      namespace     = kubernetes_namespace_v1.nifi2.metadata[0].name
    }
    secret-stackable = {
      chart         = local.chart_secret
      name          = "secret-stackable"
      namespace     = kubernetes_namespace_v1.nifi2.metadata[0].name
    }    
  }
}

module "nifi" {
  source = "../../modules/helm"

  helm_releases = {
    nifi-stackable = {
      chart         = local.chart_nifi
      name          = "nifi-stackable"
      namespace     = kubernetes_namespace_v1.nifi2.metadata[0].name
    }        
  }

  depends_on=[module.common]
}

# Application des templates
locals {
  # Calcul des DNS
  internal_dns_names = [
    for i in range(var.replica) :
    "${var.cluster_name}-node-default-${i}.${var.cluster_name}-node-default-headless.${var.nifi_namespace}.svc.cluster.local"
  ]
  all_dns_names = concat(
    [var.external_dns_name],
    local.internal_dns_names
  )

  manifests = {
    innerroot = yamldecode(templatefile("${path.module}/templates/CertificateInnerRoot.yaml.tpl", {
      external_dns_name = var.external_dns_name
      dns_names         = local.all_dns_names
      nifi_namespace  = var.nifi_namespace
      cluster_name = var.cluster_name
    }))
    gw = yamldecode(templatefile("${path.module}/templates/CertificatGW.yaml.tpl", {
      external_dns_name = var.external_dns_name
      dns_names         = local.all_dns_names
      nifi_namespace  = var.nifi_namespace
      cluster_name = var.cluster_name
    }))
    issuer = yamldecode(templatefile("${path.module}/templates/Issuer.yaml.tpl", {
      external_dns_name = var.external_dns_name
      dns_names         = local.all_dns_names
      nifi_namespace  = var.nifi_namespace
      cluster_name = var.cluster_name
    }))
    nificertificate = yamldecode(templatefile("${path.module}/templates/NifiCertificate.yaml.tpl", {
      external_dns_name = var.external_dns_name
      dns_names         = local.all_dns_names
      nifi_namespace  = var.nifi_namespace
      cluster_name = var.cluster_name
    }))
    selfsigned = yamldecode(templatefile("${path.module}/templates/SelfSigned.yaml.tpl", {
      external_dns_name = var.external_dns_name
      dns_names         = local.all_dns_names
      nifi_namespace  = var.nifi_namespace
      cluster_name = var.cluster_name
    }))    
    gw = yamldecode(templatefile("${path.module}/templates/Gateway.yaml.tpl", {
      external_dns_name = var.external_dns_name
      dns_names         = local.all_dns_names
      nifi_namespace  = var.nifi_namespace
      cluster_name = var.cluster_name
    }))   
    vs = yamldecode(templatefile("${path.module}/templates/VirtualService.yaml.tpl", {
      external_dns_name = var.external_dns_name
      dns_names         = local.all_dns_names
      nifi_namespace  = var.nifi_namespace
      cluster_name = var.cluster_name
    }))   
    dr = yamldecode(templatefile("${path.module}/templates/DestinationRule.yaml.tpl", {
      external_dns_name = var.external_dns_name
      dns_names         = local.all_dns_names
      nifi_namespace  = var.nifi_namespace
      cluster_name = var.cluster_name
    }))   
  }

  # Manifest pour OIDC
  oidcmanifest = {
    secret = yamldecode(templatefile("${path.module}/templates/SecretOIDC.yaml.tpl", {
      nifi_namespace  = var.nifi_namespace
      keycloak_url = var.keycloak_url
      client_keycloak = var.client_keycloak
      secret_keycloak = var.secret_keycloak
    }))
    authclass = yamldecode(templatefile("${path.module}/templates/AuthenticationClass.yaml.tpl", {
      nifi_namespace  = var.nifi_namespace
      keycloak_url = var.keycloak_url
      client_keycloak = var.client_keycloak
      secret_keycloak = var.secret_keycloak
    }))
  }

  # Manifest pour OIDC
  nificluster = {
    nifi = yamldecode(templatefile("${path.module}/templates/ClusterNifi.yaml.tpl", {
      nifi_namespace  = var.nifi_namespace
      cluster_name = var.cluster_name
      replica = var.replica
    }))
  }
}

resource "helm_release" "manifests" {
  name             = "ecosystemstackable"
  namespace        = var.nifi_namespace
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

  depends_on = [module.nifi]
}

# Creation du keystore et du truststore pour Nifi
resource "null_resource" "generate_tls_p12" {
  // En cas de changement de replica notamment
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e

# Récupération des certificats
kubectl get secret nifi2-server-tls -n ${var.nifi_namespace} -o jsonpath="{.data['tls\\.crt']}" | base64 -d > cert.pem
kubectl get secret nifi2-server-tls -n ${var.nifi_namespace} -o jsonpath="{.data['tls\\.key']}" | base64 -d > key.pem
kubectl get secret nifi-ca-keypair -n ${var.nifi_namespace} -o jsonpath="{.data['ca\\.crt']}" | base64 -d > ca.pem

# Génération des keystores
openssl pkcs12 -export -in cert.pem -inkey key.pem -certfile ca.pem -out keystore.p12 -name nifi-cert -passout pass:secret
keytool -import -alias nifi-ca -file ca.pem -keystore truststore.p12 -storetype PKCS12 -storepass secret -noprompt

# Création du secret Kubernetes
kubectl delete secret nifi2-p12-secrets --ignore-not-found=true -n ${var.nifi_namespace}
kubectl create secret generic nifi2-p12-secrets --from-file=keystore.p12 --from-file=truststore.p12 -n ${var.nifi_namespace}
# Nettoyage des fichiers temporairesnifi2-p12-secrets
rm -f cert.pem key.pem ca.pem keystore.p12 truststore.p12
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [helm_release.manifests]
}


resource "helm_release" "oidcmanifests" {
  name             = "oidc"
  namespace        = var.nifi_namespace
  create_namespace = false

  repository        = "https://bedag.github.io/helm-charts"
  chart             = "raw"
  version           = "2.0.0"
  dependency_update = true
  upgrade_install   = true
  wait              = true

  values = [
    yamlencode({
      resources = local.oidcmanifest
    })
  ] 

  depends_on = [module.nifi]
}

resource "helm_release" "nificluster" {
  name             = "nificluster"
  namespace        = var.nifi_namespace
  create_namespace = false

  repository        = "https://bedag.github.io/helm-charts"
  chart             = "raw"
  version           = "2.0.0"
  dependency_update = true
  upgrade_install   = true
  wait              = true

  values = [
    yamlencode({
      resources = local.nificluster
    })
  ] 

  depends_on = [helm_release.oidcmanifests,null_resource.generate_tls_p12,helm_release.manifests]
}
