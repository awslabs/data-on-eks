################################################################################
# EKS Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.eks_cluster_name
  cluster_version = var.eks_cluster_version

  # Set the support policy to STANDARD. See https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html for more information on support policies.
  cluster_upgrade_policy = {
    support_type = "STANDARD"
  }

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

  tags       = local.tags
  depends_on = [module.vpc]
}
