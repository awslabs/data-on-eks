provider "aws" {
  region = local.region
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", local.eks_cluster]
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", local.eks_cluster]
    }
  }
}

data "aws_eks_cluster" "this" {
  name = local.eks_cluster
}

locals {
  region      = var.region
  name        = "pytorch"
  eks_cluster = "ray-cluster"
}

module "pytorch_cluster" {
  source = "../../../modules/ray-cluster"

  namespace        = local.name
  ray_cluster_name = local.name
  eks_cluster_name = local.eks_cluster

  helm_values = [
    yamlencode({
      image = {
        repository = "rayproject/ray-ml"
        # This is a different version than the xgboost version
        tag        = "2.3.0"
        pullPolicy = "IfNotPresent"
      }
      head = {
        enableInTreeAutoscaling = "True"
        resources = {
          limits = {
            cpu    = "4"
            memory = "24G"
          }
          requests = {
            cpu    = "4"
            memory = "12G"
          }
        }
        tolerations = [
          {
            key      = local.name
            effect   = "NoSchedule"
            operator = "Exists"
          }
        ]
        containerEnv = [
          {
            name  = "RAY_LOG_TO_STDERR"
            value = "1"
          },
          {
            # workaround for protobuf protoc >= 3.19.0 issue
            name  = "PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION"
            value = "python"
          }
        ]
      }
      worker = {
        resources = {
          limits = {
            cpu    = "8"
            memory = "24G"
          }
          requests = {
            cpu    = "4"
            memory = "12G"
          }
        }
        tolerations = [
          {
            key      = local.name
            effect   = "NoSchedule"
            operator = "Exists"
          }
        ]
        replicas    = "0"
        minReplicas = "0"
        maxReplicas = "30"
        containerEnv = [
          {
            name  = "RAY_LOG_TO_STDERR"
            value = "1"
          },
          {
            # workaround for protobuf protoc >= 3.19.0 issue
            name  = "PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION"
            value = "python"
          }
        ]
      }
    })
  ]
}
