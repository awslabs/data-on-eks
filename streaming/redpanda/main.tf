################################################################################
# Data
################################################################################

data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}


################################################################################
# Local Variables
################################################################################
locals {
  name       = var.name
  region     = var.region
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  vpc_cidr = var.vpc_cidr
  azs      = slice(data.aws_availability_zones.available.names, 0, 2)


  tags = {

  }

}


################################################################################
# Cluster and Managed Node Group
################################################################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~>19.15"


  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  vpc_id                          = module.vpc.vpc_id
  subnet_ids                      = module.vpc.private_subnets
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }
  #---------------------------------------------------------------
  # Managed Node Group - Core Services
  #---------------------------------------------------------------

  eks_managed_node_groups = {
    core_node_group = {
      name           = "core-mng-01"
      description    = "Core EKS managed node group"
      instance_types = ["m5.xlarge"]
      min_size       = 3
      max_size       = 6
      desired_size   = 3

      #---------------------------------------------------------------
      # Managed Node Group - Redpanda
      #---------------------------------------------------------------

    }

  }

}
