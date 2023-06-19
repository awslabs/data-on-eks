data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

# This ECR "registry_id" number refers to the AWS account ID for us-west-2 region
# if you are using a different region, make sure to change it, you can get the account from the link below
# https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/docker-custom-images-tag.html
data "aws_ecr_authorization_token" "token" {
  registry_id = "895885662937"
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

data "aws_availability_zones" "available" {}

data "aws_caller_identity" "current" {}

data "aws_eks_addon_version" "this" {
  addon_name         = "vpc-cni"
  kubernetes_version = var.eks_cluster_version
  most_recent        = true
}

# This data source can be used to get the latest AMI for Managed Node Groups
data "aws_ami" "x86" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["amazon-eks-node-${module.eks.cluster_version}-*"] # Update this for ARM ["amazon-eks-arm64-node-${module.eks.cluster_version}-*"]
  }
}
