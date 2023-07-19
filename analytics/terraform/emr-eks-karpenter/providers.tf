provider "aws" {
  region = local.region
}

# provider "aws" {
#   alias = "eks"
#   assume_role {
#     role_arn = "arn:aws:iam::633458367150:role/emr-roadshow-iamrolesClusterAdmin4AAA00B8-XWARQW0CT8KG"
#   }
# }

# ECR always authenticates with `us-east-1` region
# Docs -> https://docs.aws.amazon.com/AmazonECR/latest/public/public-registries.html
provider "aws" {
  alias  = "ecr"
  region = "us-east-1"
}

provider "kubernetes" {
  # config_path = "~/.kube/config"
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    # config_path = "~/.kube/config"
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.name]
    }
  }
}

provider "kubectl" {
  apply_retry_count      = 10
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  host                   = data.aws_eks_cluster.cluster.endpoint
  load_config_file       = false
  token                  = data.aws_eks_cluster_auth.this.token
}
