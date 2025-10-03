locals {
  superset_name      = "superset"
  superset_namespace = "superset"

  superset_values = file("${path.module}/helm-values/superset.yaml")

  superset_postgresql_manifests = provider::kubernetes::manifest_decode_multi(
    templatefile("${path.module}/manifests/superset/postgresql.yaml", {
      namespace = local.superset_namespace
    })
  )

  superset_redis_manifests = provider::kubernetes::manifest_decode_multi(
    templatefile("${path.module}/manifests/superset/redis.yaml", {
      namespace = local.superset_namespace
    })
  )
}

#---------------------------------------------------------------
# Superset Namespace
#---------------------------------------------------------------
resource "kubernetes_namespace" "superset" {
  count = var.enable_superset ? 1 : 0
  metadata {
    name = local.superset_namespace
  }
}

#---------------------------------------------------------------
# Database Secrets
#---------------------------------------------------------------
resource "kubernetes_secret" "superset_postgresql_secrets" {
  count = var.enable_superset ? 1 : 0
  metadata {
    name      = "postgresql-secrets"
    namespace = local.superset_namespace
  }

  data = {
    password   = random_password.superset_postgres.result
    secret-key = random_password.superset_secret_key.result
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace.superset]
}

resource "random_password" "superset_postgres" {
  length  = 16
  special = true
}

resource "random_password" "superset_secret_key" {
  length  = 42
  special = true
}

#---------------------------------------------------------------
# Redis Deployment and Service
#---------------------------------------------------------------
resource "kubectl_manifest" "superset_redis" {
  count = var.enable_superset ? length(local.superset_redis_manifests) : 0

  yaml_body = yamlencode(local.superset_redis_manifests[count.index])

  depends_on = [
    kubernetes_namespace.superset
  ]
}

#---------------------------------------------------------------
# PostgreSQL StatefulSet and Service
#---------------------------------------------------------------
resource "kubectl_manifest" "superset_postgresql" {
  count = var.enable_superset ? length(local.superset_postgresql_manifests) : 0

  yaml_body = yamlencode(local.superset_postgresql_manifests[count.index])

  depends_on = [
    kubernetes_namespace.superset,
    kubernetes_secret.superset_postgresql_secrets
  ]
}

#---------------------------------------------------------------
# Apache Superset Application
#---------------------------------------------------------------
resource "kubectl_manifest" "superset" {
  count = var.enable_superset ? 1 : 0

  yaml_body = templatefile("${path.module}/argocd-applications/superset.yaml", {
    user_values_yaml = indent(8, local.superset_values)
  })

  depends_on = [
    helm_release.argocd,
    kubectl_manifest.superset_postgresql,
    kubectl_manifest.superset_redis
  ]
}
