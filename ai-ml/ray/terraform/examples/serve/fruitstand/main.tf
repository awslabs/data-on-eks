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
importPath: fruit.deployment_graph
runtimeEnv: |
  working_dir: "https://github.com/ray-project/test_dag/archive/41d09119cbdf8450599f993f51318e9e27c59098.zip"
deployments:
  - name: MangoStand
    numReplicas: 1
    userConfig: |
      price: 3
    rayActorOptions:
      numCpus: 0.1
  - name: OrangeStand
    numReplicas: 1
    userConfig: |
      price: 2
    rayActorOptions:
      numCpus: 0.1
  - name: PearStand
    numReplicas: 1
    userConfig: |
      price: 1
    rayActorOptions:
      numCpus: 0.1
  - name: FruitMarket
    numReplicas: 1
    rayActorOptions:
      numCpus: 0.1
  - name: DAGDriver
    numReplicas: 1
    routePrefix: "/"
    rayActorOptions:
      numCpus: 0.1
EOF
  )
}
