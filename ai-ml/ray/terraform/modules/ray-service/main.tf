# Disclaimer!!!!
# These are organizational specific configurations for the
# karpenter Provisioner, NodeTemplate and RayCluster packaged
# as a module for convenience. These should be parameterized as
# you see fit for your use-case.

data "aws_eks_cluster" "this" {
  name = var.eks_cluster_name
}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

#---------------------------------------------------------------
# Karpenter Configuration
#---------------------------------------------------------------

resource "kubectl_manifest" "karpenter_provisioner" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1alpha5"
    kind       = "Provisioner"
    metadata = {
      name = var.ray_cluster_name
    }
    spec = {
      ttlSecondsAfterEmpty = 30
      #ttlSecondsUntilExpired = 600
      requirements = [
        {
          key      = "karpenter.sh/capacity-type"
          operator = "In"
          values   = ["on-demand"]
        }
      ]
      limits = {
        resources = {
          cpu = "1000"
        }
      }
      providerRef = {
        name = var.ray_cluster_name
      }
      labels = {
        owner = var.ray_cluster_name
      }
    }
  })
}

resource "kubectl_manifest" "karpenter_node_template" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1alpha1"
    kind       = "AWSNodeTemplate"
    metadata = {
      name = var.ray_cluster_name
    }
    spec = {
      subnetSelector = {
        "karpenter.sh/discovery" = var.eks_cluster_name
      }
      securityGroupSelector = {
        "karpenter.sh/discovery" = var.eks_cluster_name
      }
      tags = {
        "ray-cluster/name"       = var.ray_cluster_name
        "karpenter.sh/discovery" = var.eks_cluster_name
      }
    }
  })
}


#---------------------------------------------------------------
# Namespace Resources
#---------------------------------------------------------------
resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_service_account_v1" "this" {
  metadata {
    name      = "ray-cluster"
    namespace = kubernetes_namespace_v1.this.id
    annotations = {
      "eks.amazonaws.com/role-arn" = module.external_secrets_irsa.iam_role_arn
    }
  }
}

module "external_secrets_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.14"

  attach_external_secrets_policy        = true
  external_secrets_secrets_manager_arns = ["arn:aws:secretsmanager:*:*:secret:redis-??????"]
  role_name_prefix                      = "${var.ray_cluster_name}-external-secrets-"

  oidc_providers = {
    main = {
      provider_arn               = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}"
      namespace_service_accounts = ["${var.namespace}:ray-cluster"]
    }
  }
}

resource "kubectl_manifest" "secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "SecretStore"
    metadata = {
      name      = var.ray_cluster_name
      namespace = kubernetes_namespace_v1.this.id
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.region
          auth = {
            jwt = {
              serviceAccountRef = {
                name = basename(kubernetes_service_account_v1.this.id)
              }
            }
          }
        }
      }
    }
  })
}

resource "kubectl_manifest" "external_secret" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = var.ray_cluster_name
      namespace = kubernetes_namespace_v1.this.id
    }
    spec = {
      secretStoreRef = {
        name = var.ray_cluster_name
        kind = "SecretStore"
      }
      target = {
        name           = "redis-secret"
        creationPolicy = "Owner"
      }
      dataFrom = [
        {
          extract = {
            key = "redis"
          }
        }
      ]
    }
  })
}

#---------------------------------------------------------------
# Ray Service
#---------------------------------------------------------------

locals {
  cluster_config = yamldecode(templatefile("${path.module}/manifests/ray_v1alpha1_rayservice.yaml", {
    ray_cluster_name = var.ray_cluster_name
  }))

  config = {
    apiVersion = "ray.io/v1alpha1"
    kind       = "RayService"
    metadata = {
      name      = var.ray_cluster_name
      namespace = kubernetes_namespace_v1.this.id
      annotations = {
        "ray.io/ft-enabled"                 = "true"
        "ray.io/external-storage-namespace" = var.ray_cluster_name
      }
    }
    spec = {
      serviceUnhealthySecondThreshold    = 300
      deploymentUnhealthySecondThreshold = 300
      serveConfig                        = var.serve_config
      rayClusterConfig                   = local.cluster_config
    }
  }
}

resource "kubectl_manifest" "ray_service" {
  yaml_body = yamlencode(local.config)
}


#---------------------------------------------------------------
# Cluster Ingress
#---------------------------------------------------------------

resource "kubernetes_ingress_v1" "raycluster_ingress_head_ingress" {
  metadata {
    name      = var.ray_cluster_name
    namespace = kubernetes_namespace_v1.this.id

    annotations = {
      "nginx.ingress.kubernetes.io/rewrite-target" = "/$1"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      http {
        path {
          path      = "/${var.ray_cluster_name}/(.*)"
          path_type = "Exact"

          backend {
            service {
              name = "${var.ray_cluster_name}-head-svc"

              port {
                number = 8265
              }
            }
          }
        }

        path {
          path      = "/${var.ray_cluster_name}/serve/(.*)"
          path_type = "Exact"

          backend {
            service {
              name = "${var.ray_cluster_name}-head-svc"

              port {
                number = 8000
              }
            }
          }
        }
      }
    }
  }
}

#---------------------------------------------------------------
# Pod Disruption Budget
#---------------------------------------------------------------

resource "kubernetes_pod_disruption_budget_v1" "ray_workers" {
  metadata {
    name      = "ray-worker"
    namespace = kubernetes_namespace_v1.this.id
  }
  spec {
    min_available = 2
    selector {
      match_labels = {
        "ray.io/node-type" = "worker"
      }
    }
  }
}

#---------------------------------------------------------------
# Monitoring
#---------------------------------------------------------------

resource "kubectl_manifest" "service_monitor" {
  yaml_body = templatefile("${path.module}/manifests/serviceMonitor.yaml", {
    namespace = var.namespace
  })
}

resource "kubectl_manifest" "pod_monitor" {
  yaml_body = templatefile("${path.module}/manifests/podMonitor.yaml", {
    namespace = var.namespace
  })
}