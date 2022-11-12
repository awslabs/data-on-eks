#---------------------------------------------------------------
# EKS Blueprints
#---------------------------------------------------------------
module "eks_blueprints" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.15.0"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets

  cluster_kms_key_additional_admin_arns = [data.aws_caller_identity.current.arn]

  # Add MWAA IAM Role to aws-auth configmap
  map_roles = [
    {
      rolearn  = module.mwaa.mwaa_role_arn
      username = "mwaa-service"
      groups   = ["system:masters"]
    }
  ]

  managed_node_groups = {
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

      update_config = [{
        max_unavailable_percentage = 50
      }]

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

  #---------------------------------------
  # ENABLE EMR ON EKS
  # 1. Creates namespace
  # 2. k8s role and role binding(emr-containers user) for the above namespace
  # 3. IAM role for the team execution role
  # 4. Update AWS_AUTH config map with  emr-containers user and AWSServiceRoleForAmazonEMRContainers role
  # 5. Create a trust relationship between the job execution role and the identity of the EMR managed service account
  #---------------------------------------
  enable_emr_on_eks = true
  emr_on_eks_teams = {
    emr-mwaa-team = {
      namespace               = "emr-mwaa"
      job_execution_role      = "emr-eks-mwaa-team"
      additional_iam_policies = [aws_iam_policy.emr_on_eks.arn]
    }
  }

  tags = local.tags
}

#------------------------------------------------------------------------
# Kubernetes Add-on Module
#------------------------------------------------------------------------
module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.15.0"

  eks_cluster_id       = module.eks_blueprints.eks_cluster_id
  eks_cluster_endpoint = module.eks_blueprints.eks_cluster_endpoint
  eks_oidc_provider    = module.eks_blueprints.oidc_provider
  eks_cluster_version  = module.eks_blueprints.eks_cluster_version

  # EKS Managed Add-ons
  enable_amazon_eks_vpc_cni            = true
  enable_amazon_eks_coredns            = true
  enable_amazon_eks_kube_proxy         = true
  enable_amazon_eks_aws_ebs_csi_driver = true

  enable_metrics_server     = true
  enable_cluster_autoscaler = true

  tags = local.tags
}
#---------------------------------------------------------------
# Example IAM policies for EMR job execution
#---------------------------------------------------------------
resource "aws_iam_policy" "emr_on_eks" {
  name        = format("%s-%s", local.name, "emr-job-iam-policies")
  description = "IAM policy for EMR on EKS Job execution"
  path        = "/"
  policy      = data.aws_iam_policy_document.emr_on_eks.json
}

#---------------------------------------------------------------
# Create EMR on EKS Virtual Cluster
#---------------------------------------------------------------
resource "aws_emrcontainers_virtual_cluster" "this" {
  name = format("%s-%s", module.eks_blueprints.eks_cluster_id, "emr-mwaa-team")

  container_provider {
    id   = module.eks_blueprints.eks_cluster_id
    type = "EKS"

    info {
      eks_info {
        namespace = "emr-mwaa"
      }
    }
  }
}
#------------------------------------------------------------------------
# Create K8s Namespace and Role for mwaa access directly
#------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "mwaa" {
  metadata {
    name = "mwaa"
  }
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
