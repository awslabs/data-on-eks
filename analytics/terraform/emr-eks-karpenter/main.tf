
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.9"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  cluster_endpoint_private_access = true # if true, Kubernetes API requests within your cluster's VPC (such as node to control plane communication) use the private VPC endpoint
  cluster_endpoint_public_access  = true # if true, Your cluster API server is accessible from the internet. You can, optionally, limit the CIDR blocks that can access the public endpoint.

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  manage_aws_auth_configmap = true
  aws_auth_roles = [
    # We need to add in the Karpenter node IAM role for nodes launched by Karpenter
    {
      rolearn  = module.karpenter.role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups = [
        "system:bootstrappers",
        "system:nodes",
      ]
    },
    {
      # Required for EMR on EKS virtual cluster
      rolearn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AWSServiceRoleForAmazonEMRContainers"
      username = "emr-containers"
      groups   = []
    },
  ]
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
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }

    ingress_fsx1 = {
      description = "Allows Lustre traffic between Lustre clients"
      cidr_blocks = module.vpc.private_subnets_cidr_blocks
      from_port   = 1021
      to_port     = 1023
      protocol    = "tcp"
      type        = "ingress"
    }

    ingress_fsx2 = {
      description = "Allows Lustre traffic between Lustre clients"
      cidr_blocks = module.vpc.private_subnets_cidr_blocks
      from_port   = 988
      to_port     = 988
      protocol    = "tcp"
      type        = "ingress"
    }
  }

  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      # Not required, but used in the example to access the nodes to inspect mounted volumes
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }
  eks_managed_node_groups = {
    #  We recommend to have a MNG to place your critical workloads and add-ons
    #  Then rely on Karpenter to scale your workloads
    #  You can also make uses on nodeSelector and Taints/tolerations to spread workloads on MNG or Karpenter provisioners
    core_node_group = {
      name        = "core-node-group"
      description = "EKS managed node group example launch template"

      ami_id = data.aws_ami.eks.image_id
      # This will ensure the bootstrap user data is used to join the node
      # By default, EKS managed node groups will not append bootstrap script;
      # this adds it back in using the default template provided by the module
      # Note: this assumes the AMI provided is an EKS optimized AMI derivative
      enable_bootstrap_user_data = true

      # Optional - This is to show how you can pass pre bootstrap data
      pre_bootstrap_user_data = <<-EOT
        echo "Node bootstrap process started by Data on EKS"
      EOT

      # Optional - Post bootstrap data to verify anything
      post_bootstrap_user_data = <<-EOT
        echo "Bootstrap complete.Ready to Go!"
      EOT

      subnet_ids = module.vpc.private_subnets

      min_size     = 3
      max_size     = 9
      desired_size = 3

      force_update_version = true
      instance_types       = ["m5.xlarge"]

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
        Name                     = "core-node-grp",
        "karpenter.sh/discovery" = local.name
        "cluster-autoscaler.kubernetes.io/safe-to-evict" = "false"        
      }
    },
    #spark_node_group = var.enable_spark_node_group ? {
    spark_compute_od_ng = {      
        name        = "spark-compute-od-ng"
        description = "EKS managed node group example launch template"
        subnet_ids  = [element(module.vpc.private_subnets, 0)] # Single AZ node group for Spark workloads

        ami_id = data.aws_ami.eks.image_id
        # This will ensure the bootstrap user data is used to join the node
        # By default, EKS managed node groups will not append bootstrap script;
        # this adds it back in using the default template provided by the module
        # Note: this assumes the AMI provided is an EKS optimized AMI derivative
        enable_bootstrap_user_data = true

        # format_mount_nvme_disk = true # Mounts NVMe disks to /local1, /local2 etc. 

        # Optional - This is to show how you can pass pre bootstrap data
        pre_bootstrap_user_data = <<-EOT
        echo "Node bootstrap process started by Data on EKS"
        EOT

        # Optional - Post bootstrap data to verify anything
        post_bootstrap_user_data = <<-EOT
          #!/bin/bash
          echo "Running a custom user data script"
          set -ex
          yum install mdadm -y

          DEVICES=$(lsblk -o NAME,TYPE -dsn | awk '/disk/ {print $1}')

          DISK_ARRAY=()

          for DEV in $DEVICES
          do
            DISK_ARRAY+=("/dev/$${DEV}")
          done

          DISK_COUNT=$${#DISK_ARRAY[@]}

          if [ $${DISK_COUNT} -eq 0 ]; then
            echo "No SSD disks available. No further action needed."
          else
            if [ $${DISK_COUNT} -eq 1 ]; then
              TARGET_DEV=$${DISK_ARRAY[0]}
              mkfs.xfs $${TARGET_DEV}
            else
              mdadm --create --verbose /dev/md0 --level=0 --raid-devices=$${DISK_COUNT} $${DISK_ARRAY[@]}
              mkfs.xfs /dev/md0
              TARGET_DEV=/dev/md0
            fi

            mkdir -p /local1
            echo $${TARGET_DEV} /local1 xfs defaults,noatime 1 2 >> /etc/fstab
            mount -a
            /usr/bin/chown -hR +999:+1000 /local1
          fi
          echo "Bootstrap complete.Ready to Go!"
        EOT

        min_size     = 0
        max_size     = 9
        desired_size = 0

        force_update_version = true
        # These instances were chosen based on recommendation from ec2-instance-selector
        # ec2-instance-selector --vcpus 8 --memory 16 --cpu-architecture x86_64 --instance-storage-min 100GB -r us-west-2        
        instance_types       = ["c5d.2xlarge","c5ad.2xlarge","c6id.2xlarge"]

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
        NodeGroupType = "spark-compute-od-ng"
        }

        # Checkout the docs for more details on node-template labels https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#how-can-i-scale-a-node-group-to-0
        additional_tags = {
          Name                                                             = "spark-compute-od-ng"
          subnet_type                                                      = "private"
          "k8s.io/cluster-autoscaler/node-template/label/arch"             = "x86"
          "k8s.io/cluster-autoscaler/node-template/label/kubernetes.io/os" = "linux"
          "k8s.io/cluster-autoscaler/node-template/label/noderole"         = "spark"
          "k8s.io/cluster-autoscaler/node-template/label/NodeGroupType"    = "spark-compute-od-ng"
          "NTH-managed"                                                    = "aws-node-termination-handler/managed"          
          "k8s.io/cluster-autoscaler/node-template/label/disk"             = "nvme"
          "k8s.io/cluster-autoscaler/node-template/label/node-lifecycle"   = "on-demand"
          "k8s.io/cluster-autoscaler/experiments"                          = "owned"
          "k8s.io/cluster-autoscaler/enabled"                              = "true"
        }
    },
    spark_compute_spot_ng = {      
        name        = "spark-compute-spot-ng"
        description = "EKS managed node group example launch template"
        subnet_ids  = [element(module.vpc.private_subnets, 0)] # Single AZ node group for Spark workloads

        ami_id = data.aws_ami.eks.image_id
        # This will ensure the bootstrap user data is used to join the node
        # By default, EKS managed node groups will not append bootstrap script;
        # this adds it back in using the default template provided by the module
        # Note: this assumes the AMI provided is an EKS optimized AMI derivative
        enable_bootstrap_user_data = true

        # format_mount_nvme_disk = true # Mounts NVMe disks to /local1, /local2 etc. 

        # Optional - This is to show how you can pass pre bootstrap data
        pre_bootstrap_user_data = <<-EOT
        echo "Node bootstrap process started by Data on EKS"
        EOT

        # Optional - Post bootstrap data to verify anything
        post_bootstrap_user_data = <<-EOT
          #!/bin/bash
          echo "Running a custom user data script"
          set -ex
          yum install mdadm -y

          DEVICES=$(lsblk -o NAME,TYPE -dsn | awk '/disk/ {print $1}')

          DISK_ARRAY=()

          for DEV in $DEVICES
          do
            DISK_ARRAY+=("/dev/$${DEV}")
          done

          DISK_COUNT=$${#DISK_ARRAY[@]}

          if [ $${DISK_COUNT} -eq 0 ]; then
            echo "No SSD disks available. No further action needed."
          else
            if [ $${DISK_COUNT} -eq 1 ]; then
              TARGET_DEV=$${DISK_ARRAY[0]}
              mkfs.xfs $${TARGET_DEV}
            else
              mdadm --create --verbose /dev/md0 --level=0 --raid-devices=$${DISK_COUNT} $${DISK_ARRAY[@]}
              mkfs.xfs /dev/md0
              TARGET_DEV=/dev/md0
            fi

            mkdir -p /local1
            echo $${TARGET_DEV} /local1 xfs defaults,noatime 1 2 >> /etc/fstab
            mount -a
            /usr/bin/chown -hR +999:+1000 /local1
          fi
          echo "Bootstrap complete.Ready to Go!"
        EOT

        min_size     = 0
        max_size     = 9
        desired_size = 0

        force_update_version = true
        # These instances were chosen based on recommendation from ec2-instance-selector
        # ec2-instance-selector --vcpus 8 --memory 16 --cpu-architecture x86_64 --instance-storage-min 100GB -r us-west-2
        instance_types       = ["c5d.2xlarge","c5ad.2xlarge","c6id.2xlarge"]
        capacity_type  = "SPOT"

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
        WorkerType    = "SPOT"
        NodeGroupType = "spark-compute-spot-ng"
        }

        # Checkout the docs for more details on node-template labels https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#how-can-i-scale-a-node-group-to-0
        additional_tags = {
          Name                                                             = "spark-compute-spot-ng"
          subnet_type                                                      = "private"
          "k8s.io/cluster-autoscaler/node-template/label/arch"             = "x86"
          "k8s.io/cluster-autoscaler/node-template/label/kubernetes.io/os" = "linux"
          "k8s.io/cluster-autoscaler/node-template/label/noderole"         = "spark"
          "k8s.io/cluster-autoscaler/node-template/label/NodeGroupType"    = "spark-compute-spot-ng"
          "k8s.io/cluster-autoscaler/node-template/label/disk"             = "nvme"
          "k8s.io/cluster-autoscaler/node-template/label/node-lifecycle"   = "spot"
          "k8s.io/cluster-autoscaler/experiments"                          = "owned"
          "k8s.io/cluster-autoscaler/enabled"                              = "true"
        }
    },
    spark_memory_od_ng = {      
        name        = "spark-memory-od-ng"
        description = "EKS managed node group example launch template"
        subnet_ids  = [element(module.vpc.private_subnets, 0)] # Single AZ node group for Spark workloads

        ami_id = data.aws_ami.eks.image_id
        # This will ensure the bootstrap user data is used to join the node
        # By default, EKS managed node groups will not append bootstrap script;
        # this adds it back in using the default template provided by the module
        # Note: this assumes the AMI provided is an EKS optimized AMI derivative
        enable_bootstrap_user_data = true

        # format_mount_nvme_disk = true # Mounts NVMe disks to /local1, /local2 etc. 

        # Optional - This is to show how you can pass pre bootstrap data
        pre_bootstrap_user_data = <<-EOT
        echo "Node bootstrap process started by Data on EKS"
        EOT

        # Optional - Post bootstrap data to verify anything
        post_bootstrap_user_data = <<-EOT
          #!/bin/bash
          echo "Running a custom user data script"
          set -ex
          yum install mdadm -y

          DEVICES=$(lsblk -o NAME,TYPE -dsn | awk '/disk/ {print $1}')

          DISK_ARRAY=()

          for DEV in $DEVICES
          do
            DISK_ARRAY+=("/dev/$${DEV}")
          done

          DISK_COUNT=$${#DISK_ARRAY[@]}

          if [ $${DISK_COUNT} -eq 0 ]; then
            echo "No SSD disks available. No further action needed."
          else
            if [ $${DISK_COUNT} -eq 1 ]; then
              TARGET_DEV=$${DISK_ARRAY[0]}
              mkfs.xfs $${TARGET_DEV}
            else
              mdadm --create --verbose /dev/md0 --level=0 --raid-devices=$${DISK_COUNT} $${DISK_ARRAY[@]}
              mkfs.xfs /dev/md0
              TARGET_DEV=/dev/md0
            fi

            mkdir -p /local1
            echo $${TARGET_DEV} /local1 xfs defaults,noatime 1 2 >> /etc/fstab
            mount -a
            /usr/bin/chown -hR +999:+1000 /local1
          fi
          echo "Bootstrap complete.Ready to Go!"
        EOT

        min_size     = 0
        max_size     = 9
        desired_size = 0

        force_update_version = true
        # These instances were chosen based on recommendation from ec2-instance-selector
        # ec2-instance-selector --vcpus 8 --memory 64 --cpu-architecture x86_64 --instance-storage-min 100GB -r us-west-2
        instance_types       = ["d3.2xlarge","i3en.2xlarge","i4i.2xlarge","m5zn.3xlarge","r5ad.2xlarge","r5d.2xlarge","r5dn.2xlarge","r6id.2xlarge","r6idn.2xlarge","z1d.2xlarge"]

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
        NodeGroupType = "spark-memory-od-ng"
        }

        # Checkout the docs for more details on node-template labels https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#how-can-i-scale-a-node-group-to-0
        additional_tags = {
          Name                                                             = "spark-memory-od-ng"
          subnet_type                                                      = "private"
          "k8s.io/cluster-autoscaler/node-template/label/arch"             = "x86"
          "k8s.io/cluster-autoscaler/node-template/label/kubernetes.io/os" = "linux"
          "k8s.io/cluster-autoscaler/node-template/label/noderole"         = "spark"
          "k8s.io/cluster-autoscaler/node-template/label/NodeGroupType"    = "spark-memory-od-ng"
          "NTH-managed"                                                    = "aws-node-termination-handler/managed"          
          "k8s.io/cluster-autoscaler/node-template/label/disk"             = "nvme"
          "k8s.io/cluster-autoscaler/node-template/label/node-lifecycle"   = "on-demand"
          "k8s.io/cluster-autoscaler/experiments"                          = "owned"
          "k8s.io/cluster-autoscaler/enabled"                              = "true"
        }
    },
    spark_memory_spot_ng = {      
        name        = "spark-memory-spot-ng"
        description = "EKS managed node group example launch template"
        subnet_ids  = [element(module.vpc.private_subnets, 0)] # Single AZ node group for Spark workloads

        ami_id = data.aws_ami.eks.image_id
        # This will ensure the bootstrap user data is used to join the node
        # By default, EKS managed node groups will not append bootstrap script;
        # this adds it back in using the default template provided by the module
        # Note: this assumes the AMI provided is an EKS optimized AMI derivative
        enable_bootstrap_user_data = true

        # format_mount_nvme_disk = true # Mounts NVMe disks to /local1, /local2 etc. 

        # Optional - This is to show how you can pass pre bootstrap data
        pre_bootstrap_user_data = <<-EOT
        echo "Node bootstrap process started by Data on EKS"
        EOT

        # Optional - Post bootstrap data to verify anything
        post_bootstrap_user_data = <<-EOT
          #!/bin/bash
          echo "Running a custom user data script"
          set -ex
          yum install mdadm -y

          DEVICES=$(lsblk -o NAME,TYPE -dsn | awk '/disk/ {print $1}')

          DISK_ARRAY=()

          for DEV in $DEVICES
          do
            DISK_ARRAY+=("/dev/$${DEV}")
          done

          DISK_COUNT=$${#DISK_ARRAY[@]}

          if [ $${DISK_COUNT} -eq 0 ]; then
            echo "No SSD disks available. No further action needed."
          else
            if [ $${DISK_COUNT} -eq 1 ]; then
              TARGET_DEV=$${DISK_ARRAY[0]}
              mkfs.xfs $${TARGET_DEV}
            else
              mdadm --create --verbose /dev/md0 --level=0 --raid-devices=$${DISK_COUNT} $${DISK_ARRAY[@]}
              mkfs.xfs /dev/md0
              TARGET_DEV=/dev/md0
            fi

            mkdir -p /local1
            echo $${TARGET_DEV} /local1 xfs defaults,noatime 1 2 >> /etc/fstab
            mount -a
            /usr/bin/chown -hR +999:+1000 /local1
          fi
          echo "Bootstrap complete.Ready to Go!"
        EOT

        min_size     = 0
        max_size     = 9
        desired_size = 0

        force_update_version = true
        # These instances were chosen based on recommendation from ec2-instance-selector
        # ec2-instance-selector --vcpus 8 --memory 64 --cpu-architecture x86_64 --instance-storage-min 100GB -r us-west-2
        instance_types       = ["d3.2xlarge","i3en.2xlarge","i4i.2xlarge","m5zn.3xlarge","r5ad.2xlarge","r5d.2xlarge","r5dn.2xlarge","r6id.2xlarge","r6idn.2xlarge","z1d.2xlarge"]
        capacity_type  = "SPOT"

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
        WorkerType    = "SPOT"
        NodeGroupType = "spark-memory-spot-ng"
        }

        # Checkout the docs for more details on node-template labels https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#how-can-i-scale-a-node-group-to-0
        additional_tags = {
          Name                                                             = "spark-memory-spot-ng"
          subnet_type                                                      = "private"
          "k8s.io/cluster-autoscaler/node-template/label/arch"             = "x86"
          "k8s.io/cluster-autoscaler/node-template/label/kubernetes.io/os" = "linux"
          "k8s.io/cluster-autoscaler/node-template/label/noderole"         = "spark"
          "k8s.io/cluster-autoscaler/node-template/label/NodeGroupType"    = "spark-memory-spot-ng"
          "k8s.io/cluster-autoscaler/node-template/label/disk"             = "nvme"
          "k8s.io/cluster-autoscaler/node-template/label/node-lifecycle"   = "spot"
          "k8s.io/cluster-autoscaler/experiments"                          = "owned"
          "k8s.io/cluster-autoscaler/enabled"                              = "true"
        }
    }
  }
}


#---------------------------------------
# Karpenter IAM instance profile
#---------------------------------------

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 19.9"

  cluster_name                 = module.eks.cluster_name
  irsa_oidc_provider_arn       = module.eks.oidc_provider_arn
  create_irsa                  = false # EKS Blueprints add-on module creates IRSA
  enable_spot_termination      = false # EKS Blueprints add-on module adds this feature
  tags                         = local.tags
  iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
}
