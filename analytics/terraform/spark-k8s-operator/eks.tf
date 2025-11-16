#---------------------------------------------------------------
# EKS Cluster
#---------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.37.2"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  #WARNING: Avoid using this option (cluster_endpoint_public_access = true) in preprod or prod accounts. This feature is designed for sandbox accounts, simplifying cluster deployment and testing.
  cluster_endpoint_public_access = true

  # Add the IAM identity that terraform is using as a cluster admin
  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true
  enable_irsa = true

  # Enable EKS Auto Mode
  cluster_compute_config = {
    enabled    = true
    node_pools = ["system","general-purpose"]
  }

  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    vpc-cni = {
      before_compute = true
      preserve       = true
      configuration_values = jsonencode({
        env = {
          # Reference docs https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }

    kube-proxy = {}
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
      addon_version            = "v1.48.0-eksbuild.1"
      most_recent              = false
    }

    aws-mountpoint-s3-csi-driver = {
      service_account_role_arn = module.s3_csi_driver_irsa.iam_role_arn
      addon_version            = "v1.15.0-eksbuild.1"
      most_recent              = false
    }

    metrics-server = {}
    amazon-cloudwatch-observability = {
      preserve                 = true
      service_account_role_arn = aws_iam_role.cloudwatch_observability_role.arn
    }
  }

  vpc_id = module.vpc.vpc_id
  # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the EKS Control Plane ENIs will be created
  subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
    substr(cidr_block, 0, 4) == "100." ? subnet_id : null]
  )

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

    ebs_optimized = true
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
    spark_benchmark_ssd = {
      name        = "spark_benchmark_ssd"
      description = "Managed node group for Spark Benchmarks with NVMEe SSD using x86 or ARM"
      # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the nodes/node groups will be provisioned
      subnet_ids = [element(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), 0)
      ]

      ami_type = "AL2023_x86_64_STANDARD" # x86
      # ami_type = "AL2023_ARM_64_STANDARD" # arm64

      # Node group will be created with zero instances when you deploy the blueprint.
      # You can change the min_size and desired_size to 6 instances
      # desired_size might not be applied through terrafrom once the node group is created so this needs to be adjusted in AWS Console.
      min_size     = var.spark_benchmark_ssd_min_size # Change min and desired to 6 for running benchmarks
      max_size     = 8
      desired_size = var.spark_benchmark_ssd_desired_size # Change min and desired to 6 for running benchmarks

      instance_types = ["c5d.12xlarge"] # c5d.12xlarge = 2 x 900 NVMe SSD

      cloudinit_pre_nodeadm = [
        {
          content_type = "application/node.eks.aws"
          content      = <<-EOT
            ---
            apiVersion: node.eks.aws/v1alpha1
            kind: NodeConfig
            spec:
              instance:
                localStorage:
                  strategy: RAID0
          EOT
        }
      ]

      labels = {
        NodeGroupType = "spark_benchmark_ssd"
      }

      tags = {
        Name          = "spark_benchmark_ssd"
        NodeGroupType = "spark_benchmark_ssd"
      }
    }
  }
}


#---------------------------------------------------------------
# EKS Auto Mode Node Pools and Classes
#---------------------------------------------------------------
locals {
  auto_mode_nodepool_manifests = {
    for f in fileset("${path.module}/manifests/automode", "nodepool*.yaml") :
    f => templatefile("${path.module}/manifests/automode/${f}", {
      CLUSTER_NAME       = module.eks.cluster_name
      NODE_IAM_ROLE_NAME = aws_iam_role.custom_nodeclass_role.name
  })
}

  auto_mode_nodeclass_manifests = provider::kubernetes::manifest_decode_multi(
    templatefile("${path.module}/manifests/automode/nodeclass.yaml", {
      CLUSTER_NAME       = module.eks.cluster_name
      NODE_IAM_ROLE_NAME = aws_iam_role.custom_nodeclass_role.name
    })
  )
}

resource "kubectl_manifest" "auto_mode_nodeclass" {
  for_each = { for idx, manifest in local.auto_mode_nodeclass_manifests : idx => manifest }

  yaml_body = yamlencode(each.value)
}


resource "kubectl_manifest" "auto_mode_nodepools" {
  for_each = local.auto_mode_nodepool_manifests

  yaml_body = each.value
}
