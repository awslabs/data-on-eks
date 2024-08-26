################################################################################
# EKS add-on IAM roles for service accounts
################################################################################

module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = ">= 5.44"

  role_name = join("_", [var.eks_cluster_name, "ebs-csi"])

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# cloudwatch
module "cloudwatch_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = ">= 5.44"

  role_name = join("_", [var.eks_cluster_name, "cloudwatch"])

  attach_cloudwatch_observability_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cloudwatch-agent"]
    }
  }
}

###############################################################################
# Required IAM role and instance profile for EKS nodes used by AWS Batch.
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
