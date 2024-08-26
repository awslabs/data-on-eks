################################################################################
# EKS Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.eks_cluster_name
  cluster_version = var.eks_cluster_version

  #WARNING: Avoid using this option (cluster_endpoint_public_access = true) in preprod or prod accounts. This feature is designed for sandbox accounts, simplifying cluster deployment and testing. Set the correct value in your variables file.
  cluster_endpoint_public_access  = var.eks_public_cluster_endpoint
  cluster_endpoint_private_access = var.eks_private_cluster_endpoint
  vpc_id                          = module.vpc.vpc_id
  subnet_ids                      = module.vpc.private_subnets

  # Cluster access entry
  authentication_mode = "API_AND_CONFIG_MAP"
  # To add the current caller identity as an administrator
  enable_cluster_creator_admin_permissions = true
  # Enable IRSA for service accounts
  enable_irsa = true

  # Create a Managed node group
  eks_managed_node_group_defaults = {
    ami_type       = "AL2023_x86_64_STANDARD"
    instance_types = ["m5.large"]
    disk_size      = 10
    # Add the CloudWatch additional policy to the cluster IAM role
    iam_role_additional_policies = {
      xray       = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
      cloudwatch = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
    }
  }

  eks_managed_node_groups = {
    default = {
      desired_size = 2
      min_capacity = 2
      max_capacity = 10
      tags         = local.tags
    }
  }

  # EKS add-ons
  cluster_addons = {
    vpc-cni = {
      version = "latest"
    }
    kube-proxy = {
      version = "latest"

    }
    coredns = {
      version = "latest"
    }
    aws-ebs-csi-driver = {
      version                  = "latest"
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn

    }
    amazon-cloudwatch-observability = {
      version                  = "latest"
      resolve_conflicts        = "OVERWRITE"
      service_account_role_arn = module.cloudwatch_irsa_role.iam_role_arn
      configuration_values = jsonencode(
        {
          "agent" : {
            "config" : {
              "logs" : {
                "metrics_collected" : {
                  "app_signals" : {},
                  "kubernetes" : {
                    "accelerated_compute_metrics" : false, "enhanced_container_insights" : false
                  }
                }
              },
              "containerLogs" : {
                "enabled" : true
              }
            }
          },
          "tolerations" : [{
            "key" : "batch.amazonaws.com/batch-node",
            "operator" : "Exists"
          }]
        }
      )
    }
  }
  tags       = local.tags
  depends_on = [module.vpc]
}



###############################################################################
# K8s resources to enable AWS Batch
###############################################################################

resource "kubernetes_namespace" "doeks_batch_namespace" {
  metadata {
    annotations = {
      name = "aws-batch"
    }

    labels = {
      name = "aws-batch"
    }

    name = var.aws_batch_doeks_namespace
  }
  depends_on = [module.eks]
}

resource "kubernetes_cluster_role" "batch_cluster_role" {
  metadata {
    name = "aws-batch-cluster-role"
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["get"]
  }
  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["daemonsets", "deployments", "statefulsets", "replicasets"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["clusterroles", "clusterrolebindings"]
    verbs      = ["get", "list"]
  }
  depends_on = [module.eks]

}

resource "kubernetes_cluster_role_binding" "batch_cluster_role_binding" {
  metadata {
    name = "aws-batch-cluster-role-binding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.batch_cluster_role.metadata[0].name
  }
  subject {
    kind      = "User"
    name      = "aws-batch"
    api_group = "rbac.authorization.k8s.io"
    namespace = ""
  }
  depends_on = [module.eks]
}

resource "kubernetes_role" "batch_compute_env_role" {
  metadata {
    name      = "aws-batch-compute-environment-role"
    namespace = kubernetes_namespace.doeks_batch_namespace.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["create", "get", "list", "watch", "delete", "patch"]
  }
  rule {
    api_groups = [""]
    resources  = ["serviceaccounts"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["roles", "rolebindings"]
    verbs      = ["get", "list"]
  }
  depends_on = [module.eks]

}

resource "kubernetes_role_binding" "batch_compute_env_role_binding" {
  metadata {
    name      = "aws-batch-compute-environment-role-binding"
    namespace = kubernetes_namespace.doeks_batch_namespace.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.batch_compute_env_role.metadata[0].name
  }
  subject {
    kind      = "User"
    name      = "aws-batch"
    api_group = "rbac.authorization.k8s.io"
    namespace = ""
  }
  depends_on = [module.eks]
}

# Manage the AWS Batch aws-auth ConfigMap entries
module "eks_auth" {
  source  = "terraform-aws-modules/eks/aws//modules/aws-auth"
  version = "~> 20.0"

  manage_aws_auth_configmap = true
  aws_auth_roles = [
    {
      rolearn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AWSServiceRoleForBatch"
      username = "aws-batch"
      groups   = []
    },
    {
      rolearn  = module.eks.eks_managed_node_groups["default"].iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    },
    {
      rolearn  = aws_iam_role.batch_eks_instance_role.arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    }
  ]
  depends_on = [
    module.eks,
    kubernetes_namespace.doeks_batch_namespace,
    kubernetes_cluster_role.batch_cluster_role,
    kubernetes_cluster_role_binding.batch_cluster_role_binding,
    kubernetes_role.batch_compute_env_role,
    kubernetes_role_binding.batch_compute_env_role_binding
  ]
}
