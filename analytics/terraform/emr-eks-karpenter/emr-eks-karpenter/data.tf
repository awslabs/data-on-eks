data "aws_partition" "current" {}
data "aws_eks_cluster_auth" "this" {
  name = var.name
}

data "aws_eks_cluster" "cluster" {
  name = var.name
}

data "aws_vpc" "eks_vpc" {
  id = data.aws_eks_cluster.cluster.vpc_config[0].vpc_id
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.eks_vpc.id]
  }
  filter {
    name   = "tag:aws-cdk:subnet-type"
    values = ["Private"]
  }
}
data "aws_subnet" "selectedpriv" {
  for_each = toset(data.aws_subnets.private.ids)
  id       = each.value
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.eks_vpc.id]
  }
  filter {
    name   = "tag:aws-cdk:subnet-type"
    values = ["Public"]
  }
}
data "aws_subnet" "selectedpub" {
  for_each = toset(data.aws_subnets.public.ids)
  id       = each.value
}

data "aws_iam_openid_connect_provider" "eks_oidc" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

data "aws_availability_zones" "available" {}

data "aws_caller_identity" "current" {}

# This data source can be used to get the latest AMI for Managed Node Groups
data "aws_ami" "eks" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["amazon-eks-node-1.24-*"]
  }
}

# For Grafana Password
data "aws_secretsmanager_secret_version" "admin_password_version" {
  secret_id = aws_secretsmanager_secret.grafana.id

  depends_on = [aws_secretsmanager_secret_version.grafana]
}
