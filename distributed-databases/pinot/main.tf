#---------------------------------------------------------------
# Local variables
#---------------------------------------------------------------
locals {
  name         = var.name
  region       = var.region
  cluster_name = format("%s-%s", local.name, "cluster")

  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}

#---------------------------------------------------------------
# Grafana Admin credentials resources
#---------------------------------------------------------------
data "aws_secretsmanager_secret_version" "admin_password_version" {
  secret_id  = aws_secretsmanager_secret.grafana.id
  depends_on = [aws_secretsmanager_secret_version.grafana]
}

resource "random_password" "grafana" {
  length           = 16
  special          = true
  override_special = "@_"
}

#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "grafana" {
  name                    = "${local.name}-grafana"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id     = aws_secretsmanager_secret.grafana.id
  secret_string = random_password.grafana.result
}

#---------------------------------------------------------------
# EKS Cluster
#---------------------------------------------------------------
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_availability_zones" "available" {}

#tfsec:ignore:aws-eks-enable-control-plane-logging
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.9"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_private_access = true # if true, Kubernetes API requests within your cluster's VPC (such as node to control plane communication) use the private VPC endpoint
  cluster_endpoint_public_access  = true # if true, Your cluster API server is accessible from the internet. You can, optionally, limit the CIDR blocks that can access the public endpoint.

  eks_managed_node_groups = {

    core_node_group = {
      name        = "core-node-group"
      description = "EKS Core node group for hosting system add-ons"
      subnet_ids  = module.vpc.private_subnets

      min_size     = 3
      max_size     = 8
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
    }

    # cluster configuration based on
    # https://startree.ai/blog/capacity-planning-in-apache-pinot-part-1
    # https://startree.ai/blog/capacity-planning-in-apache-pinot-part-2

    controller_node_group = {
      instance_types = ["m5.xlarge"]
      capacity_type  = "ON_DEMAND"
      max_size       = 5
      min_size       = 3
      desired_size   = 3

      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "controller"
      }
      taints = [
        {
          key    = "dedicated"
          value  = "pinot"
          effect = "NO_SCHEDULE"
        }
      ]
    }

    zookeeper_node_group = {
      instance_types = ["m5.xlarge"]
      capacity_type  = "ON_DEMAND"
      max_size       = 5
      min_size       = 3
      desired_size   = 3

      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "zookeeper"
      }
      taints = [
        {
          key    = "dedicated"
          value  = "pinot"
          effect = "NO_SCHEDULE"
        }
      ]
    }

    broker_node_group = {
      instance_types = ["m5.xlarge"]
      capacity_type  = "ON_DEMAND"
      max_size       = 5
      min_size       = 3
      desired_size   = 3

      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "broker"
      }
      taints = [
        {
          key    = "dedicated"
          value  = "pinot"
          effect = "NO_SCHEDULE"
        }
      ]
    }

    server_node_group = {
      instance_types = ["r5.xlarge"]
      capacity_type  = "ON_DEMAND"
      max_size       = 9
      min_size       = 6
      desired_size   = 6

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
        NodeGroupType = "server"
      }
      taints = [
        {
          key    = "dedicated"
          value  = "pinot"
          effect = "NO_SCHEDULE"
        }
      ]
    }

    minion_node_group = {
      instance_types = ["m5.xlarge"]
      capacity_type  = "ON_DEMAND"
      max_size       = 3
      min_size       = 1
      desired_size   = 1

      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "minion"
      }
      taints = [
        {
          key    = "dedicated"
          value  = "pinot"
          effect = "NO_SCHEDULE"
        }
      ]
    }
  }
  tags = local.tags
}
