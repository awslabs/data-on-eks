#---------------------------------------------------------------
# EKS Cluster
#---------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.15"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  #WARNING: Avoid using this option (cluster_endpoint_public_access = true) in preprod or prod accounts. This feature is designed for sandbox accounts, simplifying cluster deployment and testing.
  cluster_endpoint_public_access = true # if true, Your cluster API server is accessible from the internet. You can, optionally, limit the CIDR blocks that can access the public endpoint.

  vpc_id = module.vpc.vpc_id
  # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the EKS Control Plane ENIs will be created
  subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) : substr(cidr_block, 0, 4) == "100." ? subnet_id : null])

  manage_aws_auth_configmap = true
  aws_auth_roles = [
    {
      rolearn  = module.eks_blueprints_addons.karpenter.iam_role_arn
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

  eks_managed_node_groups = {
    #  We recommend to have a MNG to place your critical workloads and add-ons
    #  Then rely on Karpenter to scale your workloads
    #  You can also make uses on nodeSelector and Taints/tolerations to spread workloads on MNG or Karpenter provisioners
    core_node_group = {
      name        = "core-node-group"
      description = "EKS managed node group example launch template"
      # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the nodes/node groups will be provisioned
      subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) : substr(cidr_block, 0, 4) == "100." ? subnet_id : null])

      min_size     = 3
      max_size     = 9
      desired_size = 3

      ami_type       = "AL2_x86_64"
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
        WorkerType                       = "ON_DEMAND"
        NodeGroupType                    = "core"
        "nvidia.com/gpu.deploy.operands" = false
      }

      tags = {
        Name                     = "core-node-grp",
        "karpenter.sh/discovery" = local.name
      }
    }
    spark_driver_ng = {
      name        = "spark-driver-ng"
      description = "Spark managed node group for Driver pods with cpu and Ubuntu AMI"
      # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the nodes/node groups will be provisioned
      subnet_ids = [element(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) : substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), 0)]

      # Ubuntu image for EKs Cluster 1.26 https://cloud-images.ubuntu.com/aws-eks/
      ami_id = data.aws_ami.ubuntu.image_id

      # This will ensure the bootstrap user data is used to join the node
      # By default, EKS managed node groups will not append bootstrap script;
      # this adds it back in using the default template provided by the module
      # Note: this assumes the AMI provided is an EKS optimized AMI derivative
      enable_bootstrap_user_data = true

      min_size     = 1
      max_size     = 8
      desired_size = 1

      force_update_version = true
      instance_types       = ["m5.xlarge"] # 4 vCPU and 16GB

      ebs_optimized = true
      # This bloc device is used only for root volume. Adjust volume according to your size.
      # NOTE: Dont use this volume for Spark workloads
      block_device_mappings = {
        xvda = {
          device_name = "/dev/sda1"
          ebs = {
            volume_size = 100
            volume_type = "gp3"
          }
        }
      }

      labels = {
        WorkerType                       = "ON_DEMAND"
        NodeGroupType                    = "spark-driver-ca"
        "nvidia.com/gpu.deploy.operands" = false
      }

      taints = [{
        key    = "spark-driver-ca"
        value  = true
        effect = "NO_SCHEDULE"
      }]

      tags = {
        Name = "spark-driver-ca"
      }
    }
    spark_gpu_ng = {
      name        = "spark-gpu-ng"
      description = "Spark managed Ubuntu GPU node group for executor pods with launch template"
      # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the nodes/node groups will be provisioned
      subnet_ids = [element(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) : substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), 0)]

      # Ubuntu image for EKS Cluster 1.26 https://cloud-images.ubuntu.com/aws-eks/
      ami_id = data.aws_ami.ubuntu.image_id

      # This will ensure the bootstrap user data is used to join the node
      # By default, EKS managed node groups will not append bootstrap script;
      # this adds it back in using the default template provided by the module
      # Note: this assumes the AMI provided is an EKS optimized AMI derivative
      enable_bootstrap_user_data = true

      # NVMe instance store volumes are automatically enumerated and assigned a device
      pre_bootstrap_user_data = <<-EOT
        echo "Running a custom user data script"
        set -ex
        apt-get update
        apt-get install -y nvme-cli mdadm xfsprogs

        # Fetch the list of NVMe devices
        DEVICES=$(lsblk -d -o NAME | grep nvme)

        DISK_ARRAY=()

        for DEV in $DEVICES
        do
          # Exclude the root disk, /dev/nvme0n1, from the list of devices
          if [[ $${DEV} != "nvme0n1" ]]; then
            NVME_INFO=$(nvme id-ctrl --raw-binary "/dev/$${DEV}" | cut -c3073-3104 | tr -s ' ' | sed 's/ $//g')
            # Check if the device is Amazon EC2 NVMe Instance Storage
            if [[ $${NVME_INFO} == *"ephemeral"* ]]; then
              DISK_ARRAY+=("/dev/$${DEV}")
            fi
          fi
        done

        DISK_COUNT=$${#DISK_ARRAY[@]}

        if [ $${DISK_COUNT} -eq 0 ]; then
          echo "No NVMe SSD disks available. No further action needed."
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
      EOT

      min_size     = 8
      max_size     = 8
      desired_size = 8

      capacity_type  = "SPOT"
      instance_types = ["g5.2xlarge"]

      ebs_optimized = true
      # This block device is used only for root volume. Adjust volume according to your size.
      # NOTE: Don't use this volume for Spark workloads
      # Ubuntu uses /dev/sda1 as root volume
      block_device_mappings = {
        xvda = {
          device_name = "/dev/sda1"
          ebs = {
            volume_size = 100
            volume_type = "gp3"
          }
        }
      }

      labels = {
        WorkerType    = "SPOT"
        NodeGroupType = "spark-ubuntu-gpu-ca"
      }

      taints = [{ key = "spark-ubuntu-gpu-ca", value = true, effect = "NO_SCHEDULE" }]

      tags = {
        Name = "spark-ubuntu-gpu",
      }
    }
  }

  tags = local.tags
}
