data "aws_availability_zones" "available" {}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_ami" "x86" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["amazon-eks-node-${module.eks.cluster_version}-*"] # Update this for ARM ["amazon-eks-arm64-node-${module.eks.cluster_version}-*"]
  }
}

locals {
  name   = var.name
  region = var.region
  # Training and Inference instances are available in the following AZs us-east-1 and us-west-2
  # You can find the list of supported AZs here: https://aws.amazon.com/ec2/instance-types/trn1/
  azs = ["${local.region}c", "${local.region}d"]
  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}

#---------------------------------------------------------------
# EKS Cluster
#---------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.13"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  cluster_endpoint_public_access = true # if true, Your cluster API server is accessible from the internet. You can, optionally, limit the CIDR blocks that can access the public endpoint.

  vpc_id = module.vpc.vpc_id
  # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the EKS Control Plane ENIs will be created
  subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
  substr(cidr_block, 0, 4) == "100." ? subnet_id : null])

  manage_aws_auth_configmap = true
  # aws_auth_roles = [
  #   # We need to add in the Karpenter node IAM role for nodes launched by Karpenter
  #   {
  #     rolearn  = module.eks_blueprints_addons.karpenter.node_iam_role_arn
  #     username = "system:node:{{EC2PrivateDNSName}}"
  #     groups = [
  #       "system:bootstrappers",
  #       "system:nodes",
  #     ]
  #   }
  # ]
  #---------------------------------------
  # Note: This can further restricted to specific required for each Add-on and your application
  #---------------------------------------
  # Extend cluster security group rules
  cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 0
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  # security group rule from all ipv4 to nodes for port 22
  node_security_group_additional_rules = {
    ingress_efa_enabled = {
      description      = "EFA-enabled security group SSH Ingress"
      protocol         = "-1"
      from_port        = 22
      to_port          = 22
      type             = "ingress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }

    # Critical Secruity group rule for EFA enabled nodes
    ingress_efa_self_enabled = {
      description = "EFA-enabled self-referencing security group Ingress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }

    # Critical Secruity group rule for EFA enabled nodes
    egress_efa_self_enabled = {
      description = "EFA-enabled self-referencing security group Egress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      self        = true
    }

    # egress_all = {
    #   description      = "Node all egress"
    #   protocol         = "-1"
    #   from_port        = 0
    #   to_port          = 0
    #   type             = "egress"
    #   cidr_blocks      = ["0.0.0.0/0"]
    #   ipv6_cidr_blocks = ["::/0"]
    # }
    # Allows Control Plane Nodes to talk to Worker nodes on all ports. Added this to simplify the example and further avoid issues with Add-ons communication with Control plane.
    # This can be restricted further to specific port based on the requirement for each Add-on e.g., coreDNS 53, metrics-server 4443, spark-operator 8080, karpenter 8443 etc.
    # Update this according to your security requirements if needed
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      # Not required, but used in the example to access the nodes to inspect mounted volumes
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }

    ebs_optimized = true
    # This bloc device is used only for root volume. Adjust volume according to your size.
    # NOTE: Don't use this volume for Spark workloads
    block_device_mappings = {
      xvda = {
        device_name = "/dev/xvda"
        ebs = {
          volume_size = 100
          volume_type = "gp3"
        }
      }
    }
  }

  eks_managed_node_groups = {
    #  It's recommended to have a Managed Node group for hosting critical add-ons
    #  It's recommeded to use Karpenter to place your workloads instead of using Managed Node groups
    #  You can leverage nodeSelector and Taints/tolerations to distribute workloads across Managed Node group or Karpenter nodes.
    core_node_group = {
      name        = "core-node-group"
      description = "EKS Core node group for hosting system add-ons"
      # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the nodes/node groups will be provisioned
      subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]
      )

      min_size     = 2
      max_size     = 8
      desired_size = 2

      instance_types = ["m5.xlarge"]

      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "core"
      }

      tags = merge(local.tags, {
        Name                     = "core-node-grp",
        "karpenter.sh/discovery" = local.name
      })
    }

    trn1-32xl-ng1 = {
      name        = "trn1-32xl-ng1"
      description = "Tran1 32xlarge node group for hosting ML workloads"
      # The code filters the private subnets based on their CIDR blocks and selects the subnet ID if the CIDR block starts with "100." Otherwise, it assigns a null value.
      # The element(compact([...]), 0) expression ensures that only the first non-null value is included in the resulting list of subnet IDs.
      subnet_ids = [element(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), 0)
      ]

      # ami_id = data.aws_ami.x86.image_id
      # aws ssm get-parameters --names /aws/service/eks/optimized-ami/1.27/amazon-linux-2-gpu/recommended/image_id --region us-west-2
      ami_id   = "ami-0e0deb7ae582f6fe9"
      key_name = aws_key_pair.this.key_name

      enable_bootstrap_user_data = true

      bootstrap_extra_args = "--local-disks raid0"

      # NVMe Setup and EFA Setup
      pre_bootstrap_user_data = <<-EOT
        #!/bin/sh
        # EFA Setup
        export FI_EFA_USE_DEVICE_RDMA=1
        export FI_PROVIDER=efa
        export FI_EFA_FORK_SAFE=1

        curl -O https://efa-installer.amazonaws.com/aws-efa-installer-latest.tar.gz
        tar -xf aws-efa-installer-latest.tar.gz && cd aws-efa-installer
        ./efa_installer.sh -y -g
        /opt/amazon/efa/bin/fi_info -p efa
      EOT

      # Optional - Post bootstrap data to verify anything
      post_bootstrap_user_data = <<-EOT
        echo "Bootstrap complete.Ready to Go!"
      EOT

      min_size     = 1
      max_size     = 2
      desired_size = 1

      instance_types = ["trn1.32xlarge"]

      # EFA Network Interfaces configuration
      network_interfaces = [
        {
          description                 = "NetworkInterfaces Configuration For EFA and EKS"
          delete_on_termination       = true
          device_index                = 0
          network_card_index          = 0
          associate_public_ip_address = false
          interface_type              = "efa"
        },
        {
          description                 = "NetworkInterfaces Configuration For EFA and EKS"
          delete_on_termination       = true
          device_index                = 1
          network_card_index          = 1
          associate_public_ip_address = false
          interface_type              = "efa"
        },
        {
          description                 = "NetworkInterfaces Configuration For EFA and EKS"
          delete_on_termination       = true
          device_index                = 1
          network_card_index          = 2
          associate_public_ip_address = false
          interface_type              = "efa"
        },
        {
          description                 = "NetworkInterfaces Configuration For EFA and EKS"
          delete_on_termination       = true
          device_index                = 1
          network_card_index          = 3
          associate_public_ip_address = false
          interface_type              = "efa"
        },
        {
          description                 = "NetworkInterfaces Configuration For EFA and EKS"
          delete_on_termination       = true
          device_index                = 1
          network_card_index          = 4
          associate_public_ip_address = false
          interface_type              = "efa"
        },
        {
          description                 = "NetworkInterfaces Configuration For EFA and EKS"
          delete_on_termination       = true
          device_index                = 1
          network_card_index          = 5
          associate_public_ip_address = false
          interface_type              = "efa"
        },
        {
          description                 = "NetworkInterfaces Configuration For EFA and EKS"
          delete_on_termination       = true
          device_index                = 1
          network_card_index          = 6
          associate_public_ip_address = false
          interface_type              = "efa"
        },
        {
          description                 = "NetworkInterfaces Configuration For EFA and EKS"
          delete_on_termination       = true
          device_index                = 1
          network_card_index          = 7
          associate_public_ip_address = false
          interface_type              = "efa"
        }
      ]

      # EC2 Placement Group
      # placement = {
      #     spread_domain = "cluster"
      #     groupName = "trn1-32xl-ng1"
      # }

      labels = {
        WorkerType = "trn1-32xl"
      }

      # taints = [
      #   {
      #     key = "trn1-32xl-ng1",
      #     value = true,
      #     effect = "NO_SCHEDULE"
      #   }
      # ]

      tags = merge(local.tags, {
        Name                     = "trn1-32xl-ng1",
        "karpenter.sh/discovery" = local.name
      })
    }
  }
}

resource "tls_private_key" "this" {
  algorithm = "RSA"
}

resource "aws_key_pair" "this" {
  key_name   = local.name
  public_key = tls_private_key.this.public_key_openssh
}

# resource "aws_security_group" "efa" {
#   name_prefix = "${local.name}-efa"
#   vpc_id      = module.vpc.vpc_id

#   ingress {
#     from_port = 22
#     to_port   = 22
#     protocol  = "tcp"
#     cidr_blocks = [
#       "10.1.0.0/21",
#       "100.64.0.0/16"
#     ]
#   }

#   tags = local.tags
# }
