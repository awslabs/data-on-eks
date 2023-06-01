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
  name        = "fruitstand"
  eks_cluster = "ray-cluster"
}

module "fruitstand_service" {
  source = "../../../modules/ray-service"

  namespace        = local.name
  ray_cluster_name = local.name
  eks_cluster_name = local.eks_cluster
  serve_config = yamldecode(<<EOF
importPath: "sleepy_pid:app"
runtimeEnv: |
  working_dir: "https://github.com/ray-project/serve_config_examples/archive/42d10bab77741b40d11304ad66d39a4ec2345247.zip"
deployments:
  - name: SleepyPid
    numReplicas: 6
    rayActorOptions:
      numCpus: 0
EOF
)
}
