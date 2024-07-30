################################################################################
# Network
################################################################################
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  # checkov:skip=CKV_TF_1: Modules referenced via versions
  version = "~> 5.0"

  name = local.name
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 52)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    # Tags subnets for Karpenter auto-discovery
    "karpenter.sh/discovery" = local.name
  }

  tags = local.tags
}
################################################################################
# Cluster
################################################################################
module "eks" {
  source = "terraform-aws-modules/eks/aws"
  # checkov:skip=CKV_TF_1: Modules referenced via versions
  version = "~> 20.14"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  # Give the Terraform identity admin access to the cluster
  # which will allow it to deploy resources into the cluster
  enable_cluster_creator_admin_permissions = true
  cluster_endpoint_public_access           = true
  cluster_endpoint_private_access          = true
  iam_role_additional_policies = {
    AmazonEKSServicePolicy = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  }
  cluster_addons = {
    coredns = {
      configuration_values = jsonencode({
        tolerations = [
          # Allow CoreDNS to run on the same nodes as the Karpenter controller
          # for use during cluster creation when Karpenter nodes do not yet exist
          {
            key    = "karpenter.sh/controller"
            value  = "true"
            effect = "NoSchedule"
          }
        ]
      })
    }
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {}
    aws-mountpoint-s3-csi-driver = {
      service_account_role_arn = module.s3_csi_driver_irsa.iam_role_arn
    }
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
      configuration_values = jsonencode({
        controller = {
          tolerations = [
            {
              key    = "karpenter.sh/controller"
              value  = "true"
              effect = "NoSchedule"
            }
          ]
        }
      })
    }
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets
  //cluster_additional_security_group_ids = data.aws_security_groups.this.ids
  //create_cluster_security_group = false
  //cluster_security_group_id = data.aws_security_group.cluster.id
  //create_node_security_group = false
  //node_security_group_id = data.aws_security_group.node.id
  //node_security_group_enable_recommended_rules = false
  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      # Not required, but used in the example to access the nodes to inspect mounted volumes
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }
  eks_managed_node_groups = {
    karpenter = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["m5.large"]

      min_size     = 2
      max_size     = 2
      desired_size = 2

      labels = {
        # Used to ensure Karpenter runs on nodes that it does not manage
        "karpenter.sh/controller" = "true"
      }

      taints = {
        # The pods that do not tolerate this taint should run on nodes
        # created by Karpenter
        karpenter = {
          key    = "karpenter.sh/controller"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  tags = merge(local.tags, {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = local.name
  })
}

################################################################################
# Controller & Node IAM roles, SQS Queue, Eventbridge Rules
################################################################################
module "karpenter" {
  source = "terraform-aws-modules/eks/aws//modules/karpenter"
  # checkov:skip=CKV_TF_1: Modules referenced via versions
  version = "~> 20.11"

  cluster_name = module.eks.cluster_name

  # Name needs to match role name passed to the EC2NodeClass
  node_iam_role_use_name_prefix   = false
  node_iam_role_name              = local.name
  enable_pod_identity             = true
  create_pod_identity_association = true
  node_iam_role_additional_policies = {
    ssm_session_manager_policy = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags
}



################################################################################
# Helm charts
################################################################################

resource "helm_release" "karpenter" {
  namespace           = "kube-system"
  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter"
  version             = "0.37.0"
  wait                = false

  values = [
    <<-EOT
    nodeSelector:
      karpenter.sh/controller: 'true'
    tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
      - key: karpenter.sh/controller
        operator: Exists
        effect: NoSchedule
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    EOT
  ]

  lifecycle {
    ignore_changes = [
      repository_password
    ]
  }
}

resource "aws_iam_policy" "s3_irsa_access_policy" {
  name        = "IRSAS3Access"
  path        = "/"
  description = "IRSAS3Access"

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

module "s3_csi_driver_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  # checkov:skip=CKV_TF_1: Modules referenced via versions
  version          = "~> 5.34"
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

#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  # checkov:skip=CKV_TF_1: Modules referenced via versions
  version               = "~> 5.34"
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

module "alb_controller_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  # checkov:skip=CKV_TF_1: Modules referenced via versions
  version                                = "~> 5.34"
  role_name_prefix                       = format("%s-%s-", local.name, "alb-controller")
  attach_load_balancer_controller_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
  tags = local.tags
}

resource "helm_release" "aws_load_balancer_controller" {
  name = "aws-load-balancer-controller"

  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.8.1"
  wait       = false
  values = [
    <<-EOT
    replicaCount: 1
    clusterName: ${module.eks.cluster_name}
    serviceAccount:
      name: aws-load-balancer-controller
      annotations: {
        eks.amazonaws.com/role-arn: ${module.alb_controller_irsa.iam_role_arn}
      }
    ingressClass: alb
    createIngressClassResource: true
    enableServiceMutatorWebhook: false
    EOT
  ]
}
