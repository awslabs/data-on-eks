# Disclaimer!!!!
# These are organizational specific configurations for the
# karpenter Provisioner, NodeTemplate and RayCluster packaged
# as a module for convenience. These should be parameterized as
# you see fit for your use-case.

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
      ttlSecondsAfterEmpty = 30
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
# Ray Cluster
#---------------------------------------------------------------

resource "helm_release" "ray_cluster" {
  namespace        = var.namespace
  create_namespace = true
  name             = var.ray_cluster_name
  repository       = "https://ray-project.github.io/kuberay-helm/"
  chart            = "ray-cluster"
  version          = var.ray_cluster_version

  values = var.helm_values

  depends_on = [
    kubectl_manifest.karpenter_node_template,
    kubectl_manifest.karpenter_provisioner
  ]
}
