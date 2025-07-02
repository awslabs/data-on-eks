provider "aws" {
  region = local.region
}

# ECR always authenticates with `us-east-1` region
# Docs -> https://docs.aws.amazon.com/AmazonECR/latest/public/public-registries.html
provider "aws" {
  alias  = "ecr"
  region = "us-east-1"
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubectl" {
  apply_retry_count      = 30
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  token                  = data.aws_eks_cluster_auth.this.token
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

# This ECR "registry_id" number refers to the AWS account ID for us-west-2 region
# if you are using a different region, make sure to change it, you can get the account from the link below
# https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/docker-custom-images-tag.html
data "aws_ecr_authorization_token" "token" {
  registry_id = "895885662937"
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

locals {
  name   = var.name
  region = var.region

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  tags = merge(var.tags, {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  })
}
