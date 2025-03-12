
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

###############################################################################
# IAM role and instance profile for EKS nodes managed by AWS Batch.
# These are the set of managed policies added to the role:
#   - AmazonEKSWorkerNodePolicy
#   - AmazonEC2ContainerRegistryReadOnly
#   - AmazonEKS_CNI_Policy
#   - AmazonSSMManagedInstanceCore
#   - AWSXrayWriteOnlyAccess
#   - CloudWatchAgentServerPolicy
###############################################################################

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "batch_eks_instance_role" {
  name               = join("_", [var.eks_cluster_name, "batch_instance_role"])
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  ]
  depends_on = [data.aws_iam_policy_document.ec2_assume_role]
}

resource "aws_iam_instance_profile" "batch_eks_instance_profile" {
  name       = join("_", [var.eks_cluster_name, "batch_instance_profile"])
  role       = aws_iam_role.batch_eks_instance_role.name
  depends_on = [aws_iam_role.batch_eks_instance_role]
}

###############################################################################
# AWS Batch On-Demand EC2 compute environment
###############################################################################
resource "aws_batch_compute_environment" "doeks_ondemand_ce" {
  compute_environment_name = join("_", [var.aws_batch_doeks_ce_name, "OD"])
  type                     = "MANAGED"
  state                    = "ENABLED"

  eks_configuration {
    eks_cluster_arn      = module.eks.cluster_arn
    kubernetes_namespace = "doeks-aws-batch"
  }

  compute_resources {
    type                = "EC2"
    allocation_strategy = "BEST_FIT_PROGRESSIVE"

    min_vcpus = var.aws_batch_min_vcpus
    max_vcpus = var.aws_batch_max_vcpus

    instance_type = var.aws_batch_instance_types
    instance_role = aws_iam_instance_profile.batch_eks_instance_profile.arn

    security_group_ids = [
      module.eks.node_security_group_id
    ]
    subnets = tolist(module.vpc.private_subnets)
  }

  depends_on = [
    module.eks,
    module.eks_auth,
    kubernetes_namespace.doeks_batch_namespace,
    kubernetes_role_binding.batch_compute_env_role_binding,
    kubernetes_cluster_role_binding.batch_cluster_role_binding,
    aws_iam_instance_profile.batch_eks_instance_profile
  ]
}

###############################################################################
# AWS Batch Spot EC2 compute environment
###############################################################################

resource "aws_batch_compute_environment" "doeks_spot_ce" {
  compute_environment_name = join("_", [var.aws_batch_doeks_ce_name, "SPOT"])
  type                     = "MANAGED"
  state                    = "ENABLED"

  eks_configuration {
    eks_cluster_arn      = module.eks.cluster_arn
    kubernetes_namespace = "doeks-aws-batch"
  }

  compute_resources {
    type                = "SPOT"
    allocation_strategy = "SPOT_PRICE_CAPACITY_OPTIMIZED"

    min_vcpus = var.aws_batch_min_vcpus
    max_vcpus = var.aws_batch_max_vcpus

    instance_type = var.aws_batch_instance_types
    instance_role = aws_iam_instance_profile.batch_eks_instance_profile.arn

    security_group_ids = [
      module.eks.node_security_group_id
    ]
    subnets = tolist(module.vpc.private_subnets)
  }

  depends_on = [
    module.eks,
    module.eks_auth,
    kubernetes_namespace.doeks_batch_namespace,
    kubernetes_role_binding.batch_compute_env_role_binding,
    kubernetes_cluster_role_binding.batch_cluster_role_binding,
    aws_iam_instance_profile.batch_eks_instance_profile
  ]
}
###############################################################################
# AWS Batch On-Demand Job Queue
###############################################################################
resource "aws_batch_job_queue" "doeks_ondemand_jq" {
  name     = join("_", [var.aws_batch_doeks_jq_name, "OD"])
  state    = "ENABLED"
  priority = 1
  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.doeks_ondemand_ce.arn
  }
  depends_on = [aws_batch_compute_environment.doeks_ondemand_ce]
}

###############################################################################
# AWS Batch Spot Job Queue
###############################################################################
resource "aws_batch_job_queue" "doeks_spot_jq" {
  name     = join("_", [var.aws_batch_doeks_jq_name, "SPOT"])
  state    = "ENABLED"
  priority = 1
  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.doeks_spot_ce.arn
  }
  depends_on = [aws_batch_compute_environment.doeks_spot_ce]
}


###############################################################################
# Batch Job Definition
###############################################################################
resource "aws_batch_job_definition" "doeks_hello_world" {
  name = var.aws_batch_doeks_jd_name
  type = "container"
  eks_properties {
    pod_properties {
      host_network = true
      containers {
        name  = "application-hello"
        image = "public.ecr.aws/amazonlinux/amazonlinux:2023"
        command = [
          "/bin/sh", "-c",
          "sleep 30 && echo 'Hello World!'"
        ]
        resources {
          limits = {
            cpu    = "1"
            memory = "1024Mi"
          }
        }
      }
      metadata {
        labels = {
          environment = "data-on-eks-sample"
        }
      }
    }
  }
}
