# EKS Cluster using terraform-aws-modules/eks/aws
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.name
  cluster_version = local.cluster_version

  # Avoid below option in production. It's just for POC purpose and to easier testing
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  access_entries = var.access_entries

  # Combine root account, current user/role and additinoal roles to be able to access the cluster KMS key - required for terraform updates
  kms_key_administrators = distinct(concat([
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"],
    var.kms_key_admin_roles,
    [data.aws_iam_session_context.current.issuer_arn]
  ))

  cluster_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    coredns                = {}
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {}
  }

  #---------------------------------------
  # Note: This can further restricted to specific required for each Add-on and your application
  #---------------------------------------
  # Extend cluster security group rules
  cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  # Extend node-to-node security group rules
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    # Allows Control Plane Nodes to talk to Worker nodes on all ports. Added this to simplify the example and further avoid issues with Add-ons communication with Control plane.
    # This can be restricted further to specific port based on the requirement for each Add-on e.g., metrics-server 4443, spark-operator 8080, karpenter 8443 etc.
    # Change this according to your security requirements if needed
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
  }

  vpc_id                   = module.vpc.vpc_id
  control_plane_subnet_ids = module.vpc.public_subnets
  subnet_ids               = module.outpost_subnet.subnet_id

  self_managed_node_groups = {
    outposts-ng = {
      name          = "outposts-ng"
      ami_type      = "AL2023_x86_64_STANDARD"
      instance_type = "r5.2xlarge"

      min_size     = 6
      max_size     = 10
      desired_size = 6

      bootstrap_extra_args = "--kubelet-extra-args '--node-labels=eks.amazonaws.com/compute-type=ec2'"

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 20
            volume_type           = "gp2"
            delete_on_termination = true
            encrypted             = true
          }
        }
      }

      labels = {
        NodeGroupType = "doeks"
      }

      subnet_ids = module.outpost_subnet.subnet_id
    }
  }

  # Cluster access entry
  # To add the current caller identity as an administrator
  enable_cluster_creator_admin_permissions = true

  node_security_group_tags = merge(local.tags, {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = local.name
  })

  tags = local.tags

  depends_on = [module.vpc]
}