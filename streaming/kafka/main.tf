data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}
data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name   = var.name
  region = var.region

  cluster_version = var.eks_cluster_version

  kafka_namespace = "kafka"

  vpc_cidr = var.vpc_cidr
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}

################################################################################
# Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.15"

  cluster_name    = local.name
  cluster_version = local.cluster_version
  #WARNING: Avoid using this option (cluster_endpoint_public_access = true) in preprod or prod accounts. This feature is designed for sandbox accounts, simplifying cluster deployment and testing.
  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  manage_aws_auth_configmap = true

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

  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      # Not required, but used in the example to access the nodes to inspect mounted volumes
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }

  eks_managed_node_groups = {
    core_node_group = {
      name        = "core-node-group"
      description = "EKS managed node group example launch template"

      min_size     = 1
      max_size     = 9
      desired_size = 3

      instance_types = ["m5.xlarge"]

      ebs_optimized = true
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 100
            volume_type = "gp3"
          }
        }
      }
      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "core"
      }
      tags = {
        Name = "core-node-grp"
      }
    }
    kafka_node_group = {
      name        = "kafka-node-group"
      description = "EKS managed node group example launch template"

      min_size     = 3
      max_size     = 12
      desired_size = 5

      instance_types = ["r6i.2xlarge"]
      ebs_optimized  = true
      # This is the root filesystem Not used by the brokers
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 100
            volume_type = "gp3"
          }
        }
      }
      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "kafka"
      }
      taints = [
        {
          key    = "dedicated"
          value  = "kafka"
          effect = "NO_SCHEDULE"
        }
      ]
      tags = {
        Name = "kafka-node-grp"
      }
    }
  }

  tags = local.tags
}
