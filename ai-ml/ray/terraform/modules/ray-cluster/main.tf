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
      requirements = [
        {
          key      = "karpenter.sh/capacity-type"
          operator = "In"
          values   = ["spot"]
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
      ttlSecondsAfterEmpty = 300
      taints = [
        {
          key    = var.ray_cluster_name
          effect = "NoSchedule"
        }
      ]
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
      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "1000Gi"
            volumeType          = "gp3"
            deleteOnTermination = true
          }
        }
      ]
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
        name = "redis-secret"
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
# Ray Cluster
#---------------------------------------------------------------

resource "helm_release" "this" {
  namespace        = kubernetes_namespace_v1.this.id
  create_namespace = false
  name             = var.ray_cluster_name
  repository       = "https://ray-project.github.io/kuberay-helm/"
  chart            = "ray-cluster"
  version          = var.ray_cluster_version

  values = var.helm_values

  depends_on = [
    kubectl_manifest.karpenter_node_template,
    kubectl_manifest.karpenter_provisioner,
    kubectl_manifest.external_secret
  ]
}
