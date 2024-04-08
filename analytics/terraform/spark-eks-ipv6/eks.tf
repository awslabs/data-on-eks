module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.15"

  cluster_name                   = local.name
  cluster_version                = var.eks_cluster_version
  cluster_endpoint_public_access = true

  # IPV6
  cluster_ip_family          = "ipv6"
  create_cni_ipv6_iam_policy = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

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
    # NVMe instance store volumes are automatically enumerated and assigned a device
    pre_bootstrap_user_data = <<-EOT
      cat <<-EOF > /etc/profile.d/bootstrap.sh
      #!/bin/sh
      # Configure the NVMe volumes in RAID0 configuration in the bootstrap.sh call.
      # https://github.com/awslabs/amazon-eks-ami/blob/master/files/bootstrap.sh#L35
      # This will create a RAID volume and mount it at /mnt/k8s-disks/0
      #   then mount that volume to /var/lib/kubelet, /var/lib/containerd, and /var/log/pods
      #   this allows the container daemons and pods to write to the RAID0 by default without needing PersistentVolumes
      export LOCAL_DISKS='raid0'
      EOF
      # Source extra environment variables in bootstrap script
      sed -i '/^set -o errexit/a\\nsource /etc/profile.d/bootstrap.sh' /etc/eks/bootstrap.sh
    EOT
    ebs_optimized           = true
    # This block device is used only for root volume. Adjust volume according to your size.
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
    core-node-group = {
      name           = "core-node-group"
      description    = "EKS managed node group example launch template"
      instance_types = ["m5.xlarge"]

      min_size     = 3
      max_size     = 9
      desired_size = 3

      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "core-nodes"
      }

      tags = {
        Name          = "core-node-group"
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "core-nodes"
      }
    }
  }

  tags = local.tags
}
