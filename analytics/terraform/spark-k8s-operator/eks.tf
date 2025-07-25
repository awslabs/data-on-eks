#---------------------------------------------------------------
# EKS Cluster
#---------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.33"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  #WARNING: Avoid using this option (cluster_endpoint_public_access = true) in preprod or prod accounts. This feature is designed for sandbox accounts, simplifying cluster deployment and testing.
  cluster_endpoint_public_access = true

  # Add the IAM identity that terraform is using as a cluster admin
  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true

  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
  cluster_addons = {
    coredns                = {}
    eks-pod-identity-agent = {}
    vpc-cni = {
      before_compute = true
      preserve       = true
      most_recent    = true # To ensure access to the latest settings provided
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
      most_recent              = true
    }

    aws-mountpoint-s3-csi-driver = {
      service_account_role_arn = module.s3_csi_driver_irsa.iam_role_arn
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
    #  We recommend to have a MNG to place your critical workloads and add-ons
    #  Then rely on Karpenter to scale your workloads
    #  You can also make uses on nodeSelector and Taints/tolerations to spread workloads on MNG or Karpenter provisioners
    core_node_group = {
      name        = "core-node-group"
      description = "EKS managed node group example launch template"
      # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the nodes/node groups will be provisioned
      subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]
      )

      min_size     = 3
      max_size     = 3
      desired_size = 3

      instance_types = ["m5.xlarge"]

      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "core"
      }

      tags = {
        Name                     = "core-node-grp",
        "karpenter.sh/discovery" = local.name
      }
    }

    # The following Node groups are a placeholder to create Node groups for running Spark TPC-DS benchmarks
    spark_benchmark_ebs = {
      name        = "spark_benchmark_ebs"
      description = "Managed node group for Spark Benchmarks with EBS using x86 or ARM"
      # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the nodes/node groups will be provisioned
      subnet_ids = [element(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), 0)
      ]

      # Change ami_type= AL2023_x86_64_STANDARD for x86 instances
      ami_type = "AL2023_ARM_64_STANDARD" # arm64

      # Node group will be created with zero instances when you deploy the blueprint.
      # You can change the min_size and desired_size to 6 instances
      # desired_size might not be applied through terrafrom once the node group is created so this needs to be adjusted in AWS Console.
      min_size     = 0 # Change min and desired to 6 for running benchmarks
      max_size     = 8
      desired_size = 0 # Change min and desired to 6 for running benchmarks

      # This storage is used as a shuffle for non NVMe SSD instances. e.g., r8g instances
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 300
            volume_type           = "gp3"
            iops                  = 3000
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      # Change the instance type as you desire and match with ami_type
      instance_types = ["r8g.12xlarge"] # Change Instance type to run the benchmark with various instance types

      labels = {
        NodeGroupType = "spark_benchmark_ebs"
      }

      tags = {
        Name          = "spark_benchmark_ebs"
        NodeGroupType = "spark_benchmark_ebs"
      }
    }

    spark_benchmark_ssd = {
      name        = "spark_benchmark_ssd"
      description = "Managed node group for Spark Benchmarks with NVMEe SSD using x86 or ARM"
      # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the nodes/node groups will be provisioned
      subnet_ids = [element(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), 0)
      ]

      ami_type = "AL2023_x86_64_STANDARD" # x86

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

    spark_operator_bench = {
      name        = "spark_operator_bench"
      description = "Managed node group for Spark Operator Benchmarks with EBS using x86 or ARM"
      # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the nodes/node groups will be provisioned
      subnet_ids = [element(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), 0)
      ]

      ami_type = "AL2023_x86_64_STANDARD"

      cloudinit_pre_nodeadm = [
        {
          content_type = "application/node.eks.aws"
          content      = <<-EOT
            ---
            apiVersion: node.eks.aws/v1alpha1
            kind: NodeConfig
            spec:
              kubelet:
                config:
                  maxPods: 220
          EOT
        }
      ]

      min_size     = 0
      max_size     = 200
      desired_size = 0

      instance_types = ["m6a.4xlarge"]

      labels = {
        NodeGroupType = "spark-operator-benchmark-ng"
      }

      taints = {
        benchmark = {
          key      = "spark-operator-benchmark-ng"
          effect   = "NO_SCHEDULE"
          operator = "EXISTS"
        }
      }

      tags = {
        Name          = "spark-operator-benchmark-ng"
        NodeGroupType = "spark-operator-benchmark-ng"
      }
    }
  }
}

#---------------------------------------------------------------
# EKS Amazon CloudWatch Observability Role
#---------------------------------------------------------------
resource "aws_iam_role" "cloudwatch_observability_role" {
  name = "${local.name}-eks-cw-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent",
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_observability_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.cloudwatch_observability_role.name
}

#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.55"
  role_name_prefix      = format("%s-%s-", local.name, "ebs-csi-driver")
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  tags = local.tags
}

#---------------------------------------------------------------
# IRSA for Mountpoint S3 CSI Driver
#---------------------------------------------------------------
module "s3_csi_driver_irsa" {
  source           = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version          = "~> 5.55"
  role_name_prefix = format("%s-%s-", local.name, "s3-csi-driver")
  role_policy_arns = {
    # WARNING: Demo purpose only. Bring your own IAM policy with least privileges
    s3_access = aws_iam_policy.s3_irsa_access_policy.arn
    #kms_access = "arn:aws:iam::aws:policy/AWSKeyManagementServicePowerUser"
  }
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:s3-csi-driver-sa"]
    }
  }
  tags = local.tags
}

resource "aws_iam_policy" "s3_irsa_access_policy" {
  name        = "${local.name}-S3Access"
  path        = "/"
  description = "S3 Access for Nodes"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  # checkov:skip=CKV_AWS_288: Demo purpose IAM policy
  # checkov:skip=CKV_AWS_290: Demo purpose IAM policy
  # checkov:skip=CKV_AWS_289: Demo purpose IAM policy
  # checkov:skip=CKV_AWS_355: Demo purpose IAM policy
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:*",
          "s3express:*"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}
