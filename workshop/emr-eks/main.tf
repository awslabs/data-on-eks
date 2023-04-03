locals {
  tags = merge(var.tags, {
    Blueprint  = var.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  })
  ecr_repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  ecr_repository_password = data.aws_ecrpublic_authorization_token.token.password

  private_subnet_ids = var.create_vpc ? module.vpc_workshop[0].private_subnets : var.private_subnet_ids
  vpc_id             = var.create_vpc ? module.vpc_workshop[0].vpc_id : var.vpc_id

  cluster_name                        = var.create_eks ? module.eks_workshop[0].cluster_name : var.cluster_name
  oidc_provider                       = var.create_eks ? module.eks_workshop[0].oidc_provider : var.oidc_provider
  oidc_provider_arn                   = var.create_eks ? module.eks_workshop[0].oidc_provider_arn : var.oidc_provider_arn
  cluster_endpoint                    = var.create_eks ? module.eks_workshop[0].cluster_endpoint : var.cluster_endpoint
  karpenter_iam_instance_profile_name = var.create_eks ? module.eks_workshop[0].karpenter_iam_instance_profile_name : var.karpenter_iam_instance_profile_name
  cluster_certificate_authority_data  = var.create_eks ? module.eks_workshop[0].cluster_certificate_authority_data : var.cluster_certificate_authority_data
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

#---------------------------------------------------
# VPC
#---------------------------------------------------
module "vpc_workshop" {
  count  = var.create_vpc ? 1 : 0
  source = "./modules/vpc"

  name            = var.name
  vpc_cidr        = var.vpc_cidr
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
}

#---------------------------------------------------
# EKS Cluster and Core Node group
#---------------------------------------------------
module "eks_workshop" {
  count  = var.create_eks ? 1 : 0
  source = "./modules/eks"

  name                = var.cluster_name
  eks_cluster_version = var.cluster_version
  vpc_id              = local.vpc_id
  private_subnets     = local.private_subnet_ids
  region              = var.region
}

#---------------------------------------------------
# Addons with Karpenter
#---------------------------------------------------
module "addons_workshop" {
  source = "./modules/addons"

  region           = var.region
  cluster_name     = local.cluster_name
  cluster_version  = var.cluster_version
  cluster_endpoint = local.cluster_endpoint

  oidc_provider     = local.oidc_provider
  oidc_provider_arn = local.oidc_provider_arn

  ecr_repository_username             = local.ecr_repository_username
  ecr_repository_password             = local.ecr_repository_password
  karpenter_iam_instance_profile_name = local.karpenter_iam_instance_profile_name

  # ENABLE ADDONS
  enable_karpenter          = var.enable_karpenter
  enable_cloudwatch_metrics = var.enable_cloudwatch_metrics
  enable_aws_for_fluentbit  = var.enable_aws_for_fluentbit
  enable_amazon_prometheus  = var.enable_amazon_prometheus
  enable_prometheus         = var.enable_prometheus
  enable_aws_fsx_csi_driver = var.enable_aws_fsx_csi_driver
  enable_yunikorn           = var.enable_yunikorn
  enable_kubecost           = var.enable_kubecost
}

#---------------------------------------------------
# EMR EKS Module with two teams
#---------------------------------------------------
module "emr_containers_workshop" {
  source = "../modules/emr-eks-containers"

  eks_cluster_id        = local.cluster_name
  eks_oidc_provider_arn = local.oidc_provider_arn

  emr_on_eks_config = {
    # Example of all settings
    emr-data-team-a = {
      name = format("%s-%s", local.cluster_name, "emr-data-team-a")

      create_namespace       = true
      namespace              = "emr-data-team-a"
      create_virtual_cluster = var.enable_emr_ack_controller ? false : true

      execution_role_name                    = format("%s-%s", local.cluster_name, "emr-eks-data-team-a")
      execution_iam_role_description         = "EMR Execution Role for emr-data-team-a"
      execution_iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"] # Attach additional policies for execution IAM Role

      tags = {
        Name = "emr-data-team-a"
      }
    },

    emr-data-team-b = {
      name = format("%s-%s", local.cluster_name, "emr-data-team-b")

      create_namespace       = true
      namespace              = "emr-data-team-b"
      create_virtual_cluster = var.enable_emr_ack_controller ? false : true

      execution_role_name                    = format("%s-%s", local.cluster_name, "emr-eks-data-team-b")
      execution_iam_role_description         = "EMR Execution Role for emr-data-team-b"
      execution_iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"] # Attach additional policies for execution IAM Role

      tags = {
        Name = "emr-data-team-b"
      }
    }
  }
}

#---------------------------------------------------
# Use Kubectl to deploy Karpenter provisioners
# /Users/vabonthu/Documents/GITHUB/data-on-eks/workshop/emr-eks/karpenter-provisioners
#---------------------------------------------------


#---------------------------------------------------
# EMR ACK Controller
#---------------------------------------------------
module "emr_ack" {
  count  = var.enable_emr_ack_controller ? 1 : 0
  source = "../modules/emr-ack"

  eks_cluster_id                 = local.cluster_name
  eks_oidc_provider_arn          = local.oidc_provider_arn
  ecr_public_repository_username = local.ecr_repository_username
  ecr_public_repository_password = local.ecr_repository_password
}

#---------------------------------------------------
# Supporting resources
#---------------------------------------------------
#tfsec:ignore:*
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket_prefix = "emr-eks-workshop-"
  acl           = "private"

  # For example only - please evaluate for your environment
  force_destroy = true

  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}
