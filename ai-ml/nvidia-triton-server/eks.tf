#---------------------------------------------------------------
# EKS Cluster
#---------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.15"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  # if true, Your cluster API server is accessible from the internet.
  # You can, optionally, limit the CIDR blocks that can access the public endpoint.
  #WARNING: Avoid using this option (cluster_endpoint_public_access = true) in preprod or prod accounts. This feature is designed for sandbox accounts, simplifying cluster deployment and testing.
  cluster_endpoint_public_access = true

  vpc_id = module.vpc.vpc_id
  # Filtering only Secondary CIDR private subnets starting with "100.".
  # Subnet IDs where the EKS Control Plane ENIs will be created
  subnet_ids = compact([
    for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
  substr(cidr_block, 0, 4) == "100." ? subnet_id : null])

  manage_aws_auth_configmap = true
  aws_auth_roles = [
    # We need to add in the Karpenter node IAM role for nodes launched by Karpenter
    {
      rolearn  = module.eks_blueprints_addons.karpenter.node_iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups = [
        "system:bootstrappers",
        "system:nodes",
      ]
    }
  ]
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

  node_security_group_additional_rules = {
    # Allows Control Plane Nodes to talk to Worker nodes on all ports.
    # Added this to simplify the example and further avoid issues with Add-ons communication with Control plane.
    # This can be restricted further to specific port based on the requirement for each Add-on
    # e.g., coreDNS 53, metrics-server 4443.
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
    # This block device is used only for root volume. Adjust volume according to your size.
    # NOTE: Don't use this volume for ML workloads
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
    #  It's recommended to use Karpenter to place your workloads instead of using Managed Node groups
    #  You can leverage nodeSelector and Taints/tolerations to distribute workloads across Managed Node group or Karpenter nodes.
    core_node_group = {
      name        = "core-node-group"
      description = "EKS Core node group for hosting system add-ons"
      # Filtering only Secondary CIDR private subnets starting with "100.".
      # Subnet IDs where the nodes/node groups will be provisioned
      subnet_ids = compact([
        for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]
      )

      # aws ssm get-parameters --names /aws/service/eks/optimized-ami/1.27/amazon-linux-2/recommended/image_id --region us-west-2
      ami_type     = "AL2_x86_64" # Use this for Graviton AL2_ARM_64
      min_size     = 2
      max_size     = 8
      desired_size = 2

      instance_types = ["m5.xlarge"]

      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "core"
      }

      tags = merge(local.tags, {
        Name = "core-node-grp"
      })
    }
  }
}
