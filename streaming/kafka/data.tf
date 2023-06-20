#---------------------------------------------------------------
# Data resources - move to data file
#---------------------------------------------------------------
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}
data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_ami" "eks" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["amazon-eks-node-${module.eks.cluster_version}-*"]
  }
}
