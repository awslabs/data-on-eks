#---------------------------------------------------------------
# EKS Cluster
#---------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.17"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  cluster_endpoint_public_access = true

  enable_efa_support = true

  # Gives Terraform identity admin access to cluster which will
  # allow deploying resources (Karpenter) into the cluster
  enable_cluster_creator_admin_permissions = true

  access_entries = var.access_entries

  vpc_id = module.vpc.vpc_id
  # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the EKS Control Plane ENIs will be created
  subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
  substr(cidr_block, 0, 4) == "100." ? subnet_id : null])

  # Combine root account, current user/role and additinoal roles to be able to access the cluster KMS key - required for terraform updates
  kms_key_administrators = distinct(concat([
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"],
    var.kms_key_admin_roles,
    [data.aws_iam_session_context.current.issuer_arn]
  ))

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
      # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the nodes/node groups will be provisioned
      subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]
      )

      # aws ssm get-parameters --names /aws/service/eks/optimized-ami/1.27/amazon-linux-2/recommended/image_id --region us-west-2
      ami_type     = "AL2_x86_64" # Use this for Graviton AL2_ARM_64
      min_size     = 3
      max_size     = 8
      desired_size = 3

      instance_types = ["m5.2xlarge"]

      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "core"
        workload      = "rayhead"
      }

      tags = merge(local.tags, {
        Name = "core-node-grp"
      })
    }

    # Code snippet to copy the Model weights from S3 to NVMe SSD disks all the nodes used in the same nodegroup
    # This example copies 800Gb model weights under 5 mins to local disk


    # Trainium node group creation can take upto 6 mins
    trn1-32xl-ng1 = {
      name        = "trn1-32xl-ng1"
      description = "Tran1 32xlarge node group for hosting ML workloads"
      # All trn1 instances should be launched into the same subnet in the preferred trn1 AZ
      # The preferred AZ is the first AZ listed in the AZ id <-> region mapping in main.tf.
      # We use index 2 to select the subnet in AZ1 with the 100.x CIDR:
      #   module.vpc.private_subnets = [AZ1_10.x, AZ2_10.x, AZ1_100.x, AZ2_100.x]
      subnet_ids = [module.vpc.private_subnets[2]]
      # aws ssm get-parameters --names /aws/service/eks/optimized-ami/1.27/amazon-linux-2-gpu/recommended/image_id --region us-west-2
      # ami_id   = "ami-0e0deb7ae582f6fe9" # Use this to pass custom AMI ID and ignore ami_type
      ami_type       = "AL2_x86_64_GPU" # Contains Neuron driver
      instance_types = ["trn1.32xlarge"]

      pre_bootstrap_user_data = <<-EOT
        # Mount instance store volumes in RAID-0 for kubelet and containerd
        # https://github.com/awslabs/amazon-eks-ami/blob/master/doc/USER_GUIDE.md#raid-0-for-kubelet-and-containerd-raid0
        /bin/setup-local-disks raid0

        # Install Neuron monitoring tools
        yum install aws-neuronx-tools-2.* -y
        export PATH=/opt/aws/neuron/bin:$PATH

        # Install latest version of aws cli
        mkdir /awscli \
        && wget https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -O /awscli/awscliv2.zip  \
        && unzip /awscli/awscliv2.zip -d /awscli/ \
        && /awscli/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update \
        && rm -rf /awscli
      EOT

      min_size     = var.trn1_32xl_min_size
      max_size     = 4
      desired_size = var.trn1_32xl_desired_size

      # This will:
      # 1. Create a placement group to place the instances close to one another
      # 2. Ignore subnets that reside in AZs that do not support the instance type
      # 3. Expose all of the available EFA interfaces on the launch template
      enable_efa_support = true

      labels = {
        "vpc.amazonaws.com/efa.present" = "true"
        instance-type                   = "trn1-32xl"
        provisioner                     = "cluster-autoscaler"
      }

      taints = [
        {
          key    = "aws.amazon.com/neuron",
          value  = true,
          effect = "NO_SCHEDULE"
        }
      ]

      tags = merge(local.tags, {
        Name = "trn1-32xl-ng1",
      })
    }

    #--------------------------------------------------
    # Trainium node group for Trn1n.32xlarge
    #--------------------------------------------------
    trn1n-32xl-ng = {
      name        = "trn1n-32xl-ng"
      description = "trn1n 32xlarge node group for hosting ML workloads"
      # All trn1 instances should be launched into the same subnet in the preferred trn1 AZ
      # The preferred AZ is the first AZ listed in the AZ id <-> region mapping in main.tf.
      # We use index 2 to select the subnet in AZ1 with the 100.x CIDR:
      #   module.vpc.private_subnets = [AZ1_10.x, AZ2_10.x, AZ1_100.x, AZ2_100.x]
      subnet_ids = [module.vpc.private_subnets[2]]
      # aws ssm get-parameters --names /aws/service/eks/optimized-ami/1.27/amazon-linux-2-gpu/recommended/image_id --region us-west-2
      # ami_id   = "ami-0e0deb7ae582f6fe9" # Use this to pass custom AMI ID and ignore ami_type
      ami_type       = "AL2_x86_64_GPU" # Contains Neuron driver
      instance_types = ["trn1n.32xlarge"]

      pre_bootstrap_user_data = <<-EOT
        # Mount instance store volumes in RAID-0 for kubelet and containerd
        # https://github.com/awslabs/amazon-eks-ami/blob/master/doc/USER_GUIDE.md#raid-0-for-kubelet-and-containerd-raid0
        /bin/setup-local-disks raid0

        # Install Neuron monitoring tools
        yum install aws-neuronx-tools-2.* -y
        export PATH=/opt/aws/neuron/bin:$PATH
      EOT

      min_size     = var.trn1n_32xl_min_size
      max_size     = 2
      desired_size = var.trn1n_32xl_desired_size

      # This will:
      # 1. Create a placement group to place the instances close to one another
      # 2. Ignore subnets that reside in AZs that do not support the instance type
      # 3. Expose all of the available EFA interfaces on the launch template
      enable_efa_support = true

      labels = {
        instance-type                   = "trn1n-32xl"
        provisioner                     = "cluster-autoscaler"
        "vpc.amazonaws.com/efa.present" = "true"
      }

      taints = [
        {
          key    = "aws.amazon.com/neuron",
          value  = true,
          effect = "NO_SCHEDULE"
        }
      ]

      tags = merge(local.tags, {
        Name = "trn1n-32xl-ng1",
      })
    }

    #--------------------------------------------------
    # Inferentia2 Spot node group
    #--------------------------------------------------
    inf2-24xl-ng = {
      name        = "inf2-24xl-ng"
      description = "inf2 24xl node group for ML inference workloads"
      # We use index 2 to select the subnet in AZ1 with the 100.x CIDR:
      #   module.vpc.private_subnets = [AZ1_10.x, AZ2_10.x, AZ1_100.x, AZ2_100.x]
      subnet_ids = [module.vpc.private_subnets[2]]

      # aws ssm get-parameters --names /aws/service/eks/optimized-ami/1.27/amazon-linux-2-gpu/recommended/image_id --region us-west-2
      # ami_id   = "ami-0e0deb7ae582f6fe9" # Use this to pass custom AMI ID and ignore ami_type
      ami_type       = "AL2_x86_64_GPU"
      capacity_type  = "ON_DEMAND" # Use SPOT for Spot instances
      instance_types = ["inf2.24xlarge"]

      pre_bootstrap_user_data = <<-EOT
        # Mount instance store volumes in RAID-0 for kubelet and containerd
        # https://github.com/awslabs/amazon-eks-ami/blob/master/doc/USER_GUIDE.md#raid-0-for-kubelet-and-containerd-raid0
        /bin/setup-local-disks raid0

        # Install Neuron monitoring tools
        yum install aws-neuronx-tools-2.* -y
        export PATH=/opt/aws/neuron/bin:$PATH
      EOT

      min_size     = var.inf2_24xl_min_size
      max_size     = 2
      desired_size = var.inf2_24xl_desired_size

      labels = {
        instanceType    = "inf2-24xl"
        provisionerType = "cluster-autoscaler"
      }

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 500
            volume_type = "gp3"
          }
        }
      }

      taints = [
        {
          key    = "aws.amazon.com/neuron",
          value  = "true",
          effect = "NO_SCHEDULE"
        }
      ]

      tags = merge(local.tags, {
        Name                     = "inf2-24xl-ng",
        "karpenter.sh/discovery" = local.name
      })
    }

    inf2-48xl-ng = {
      name        = "inf2-48xl-ng"
      description = "inf2 48x large node group for ML inference workloads"
      # We use index 2 to select the subnet in AZ1 with the 100.x CIDR:
      #   module.vpc.private_subnets = [AZ1_10.x, AZ2_10.x, AZ1_100.x, AZ2_100.x]
      subnet_ids = [module.vpc.private_subnets[2]]

      # aws ssm get-parameters --names /aws/service/eks/optimized-ami/1.27/amazon-linux-2-gpu/recommended/image_id --region us-west-2
      # ami_id   = "ami-0e0deb7ae582f6fe9" # Use this to pass custom AMI ID and ignore ami_type
      ami_type       = "AL2_x86_64_GPU"
      capacity_type  = "ON_DEMAND" # Use SPOT for Spot instances
      instance_types = ["inf2.48xlarge"]

      pre_bootstrap_user_data = <<-EOT
        # Mount instance store volumes in RAID-0 for kubelet and containerd
        # https://github.com/awslabs/amazon-eks-ami/blob/master/doc/USER_GUIDE.md#raid-0-for-kubelet-and-containerd-raid0
        /bin/setup-local-disks raid0

        # Install Neuron monitoring tools
        yum install aws-neuronx-tools-2.* -y
        export PATH=/opt/aws/neuron/bin:$PATH
      EOT

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 500
            volume_type = "gp3"
          }
        }
      }

      min_size     = var.inf2_48xl_min_size
      max_size     = 2
      desired_size = var.inf2_48xl_desired_size

      labels = {
        instanceType    = "inf2-48xl"
        provisionerType = "cluster-autoscaler"
      }

      taints = [
        {
          key    = "aws.amazon.com/neuron",
          value  = true,
          effect = "NO_SCHEDULE"
        }
      ]

      tags = merge(local.tags, {
        Name = "inf2-48xl-ng",
      })
    }
  }
}
