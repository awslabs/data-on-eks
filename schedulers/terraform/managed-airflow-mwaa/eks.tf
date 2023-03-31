#---------------------------------------------------------------
# EKS Blueprints
#---------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.10.3"

  cluster_name                   = local.name
  cluster_version                = var.eks_cluster_version
  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  kms_key_administrators = [data.aws_caller_identity.current.arn]

  # Add MWAA IAM Role to aws-auth configmap
  # aws-auth configmap
  manage_aws_auth_configmap = true

  aws_auth_roles = [
    {
      rolearn  = module.mwaa.mwaa_role_arn
      username = "mwaa-service"
      groups   = ["system:masters"]
    },
    {
      # Required for EMR on EKS virtual cluster
      rolearn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AWSServiceRoleForAmazonEMRContainers"
      username = "emr-containers"
      groups   = []
    }
  ]

  eks_managed_node_groups = {
    # EKS MANAGED NODE GROUPS
    # We recommend to have a MNG to place your critical workloads and add-ons
    # Then rely on Karpenter to scale your workloads
    # You can also make uses on nodeSelector and Taints/tolerations to spread workloads on MNG or Karpenter provisioners
    mng1 = {
      node_group_name = "core-node-grp"
      subnet_ids      = module.vpc.private_subnets

      instance_types = ["m5.xlarge"]
      ami_type       = "AL2_x86_64"
      capacity_type  = "ON_DEMAND"

      disk_size = 100
      disk_type = "gp3"

      max_size               = 9
      min_size               = 3
      desired_size           = 3
      create_launch_template = true
      launch_template_os     = "amazonlinux2eks"

      update_config = {
        max_unavailable_percentage = "50"
      }

      k8s_labels = {
        Environment   = "preprod"
        Zone          = "test"
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "core"
      }

      additional_tags = {
        Name                                                             = "core-node-grp"
        subnet_type                                                      = "private"
        "k8s.io/cluster-autoscaler/node-template/label/arch"             = "x86"
        "k8s.io/cluster-autoscaler/node-template/label/kubernetes.io/os" = "linux"
        "k8s.io/cluster-autoscaler/node-template/label/noderole"         = "core"
        "k8s.io/cluster-autoscaler/node-template/label/node-lifecycle"   = "on-demand"
        "k8s.io/cluster-autoscaler/experiments"                          = "owned"
        "k8s.io/cluster-autoscaler/enabled"                              = "true"
      }
    },
  }

  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      # Not required, but used in the example to access the nodes to inspect mounted volumes
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }

  tags = local.tags
}

#------------------------------------------------------------------------
# EMR on EKS
#------------------------------------------------------------------------
module "emr_containers" {
  source = "../../../workshop/modules/emr-eks-containers"

  eks_cluster_id        = module.eks.cluster_name
  eks_oidc_provider_arn = module.eks.oidc_provider_arn

  emr_on_eks_config = {
    emr-mwaa-team = {
      name = format("%s-%s", module.eks.cluster_name, "emr-mwaa")

      create_namespace = true
      namespace        = "emr-mwaa"

      execution_role_name            = format("%s-%s", module.eks.cluster_name, "emr-eks-mwaa-team")
      execution_iam_role_description = "EMR Execution Role for emr-eks-mwaa-team"
      execution_iam_role_additional_policies = [
        "arn:aws:iam::aws:policy/AmazonS3FullAccess"
      ] # Attach additional policies for execution IAM Role

      tags = merge(
        local.tags,
        {
          Name = "emr-mwaa"
        }
      )
    }
  }
}

#------------------------------------------------------------------------
# Kubernetes Add-on Module
#------------------------------------------------------------------------
module "eks_blueprints_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints-addons?ref=485133feaec00267f9708a9e50578454bf2a0113"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider     = module.eks.oidc_provider
  oidc_provider_arn = module.eks.oidc_provider_arn

  # EKS Managed Add-ons
  eks_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    coredns = {}
    vpc-cni = {
      service_account_role_arn = module.vpc_cni_irsa.iam_role_arn
    }
    kube-proxy = {}
  }

  enable_metrics_server     = true
  enable_cluster_autoscaler = true

  tags = local.tags
}

#------------------------------------------------------------------------
# EKS Add-ons IRSA
#------------------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.14"

  role_name_prefix = "${local.name}-ebs-csi-driver-"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

module "vpc_cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.14"

  role_name_prefix = "${local.name}-vpc-cni-"

  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }

  tags = local.tags
}

#------------------------------------------------------------------------
# Create K8s Namespace and Role for mwaa access directly
#------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "mwaa" {
  metadata {
    name = "mwaa"
  }
  depends_on = [
    module.eks_blueprints_addons
  ]
}

resource "kubernetes_role_v1" "mwaa" {
  metadata {
    name      = "mwaa-role"
    namespace = kubernetes_namespace_v1.mwaa.metadata[0].name
  }

  rule {
    api_groups = [
      "",
      "apps",
      "batch",
      "extensions",
    ]
    resources = [
      "jobs",
      "pods",
      "pods/attach",
      "pods/exec",
      "pods/log",
      "pods/portforward",
      "secrets",
      "services",
    ]
    verbs = [
      "create",
      "delete",
      "describe",
      "get",
      "list",
      "patch",
      "update",
    ]
  }
}

resource "kubernetes_role_binding_v1" "mwaa" {
  metadata {
    name      = "mwaa-role-binding"
    namespace = kubernetes_namespace_v1.mwaa.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_namespace_v1.mwaa.metadata[0].name
  }

  subject {
    kind      = "User"
    name      = "mwaa-service"
    api_group = "rbac.authorization.k8s.io"
  }
}
