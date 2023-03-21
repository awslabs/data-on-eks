locals {
  tags = merge(var.tags, {
    Blueprint  = var.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  })
  ecr_repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  ecr_repository_password = data.aws_ecrpublic_authorization_token.token.password
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks_workshop.cluster_name
}

#---------------------------------------------------
# VPC
#---------------------------------------------------
module "vpc_workshop" {
  source = "../modules/vpc"

  name            = var.name
  region          = var.region
  vpc_cidr        = var.vpc_cidr
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
}

#---------------------------------------------------
# EKS Cluster and Core Node group
#---------------------------------------------------
module "eks_workshop" {
  source = "../modules/eks"

  name                = var.name
  region              = var.region
  eks_cluster_version = var.eks_cluster_version
  private_subnets     = module.vpc_workshop.private_subnets
  vpc_id              = module.vpc_workshop.vpc_id
}

##---------------------------------------------------
## Addons with Karpenter
##---------------------------------------------------
module "addons_workshop" {
  source = "../modules/addons"

  region            = var.region
  cluster_name      = module.eks_workshop.cluster_name
  oidc_provider     = module.eks_workshop.oidc_provider_arn
  oidc_provider_arn = module.eks_workshop.oidc_provider_arn
  cluster_endpoint  = module.eks_workshop.cluster_endpoint
  cluster_version   = module.eks_workshop.cluster_version

  ecr_repository_username             = local.ecr_repository_username
  ecr_repository_password             = local.ecr_repository_password
  karpenter_iam_instance_profile_name = module.eks_workshop.karpenter_iam_instance_profile_name

  # ENABLE ADDONS
  enable_cloudwatch_metrics = true
  enable_aws_for_fluentbit  = true
  enable_amazon_prometheus  = true
  enable_prometheus         = true
  enable_aws_fsx_csi_driver = true
  enable_yunikorn           = true
  enable_kubecost           = true
}

##---------------------------------------------------
## Karpenter Provisioners
##---------------------------------------------------
module "karpenter_provisioners" {
  source = "../modules/karpenter-provisioners"
  name   = var.name
  region = var.region
  tags   = local.tags
}

#---------------------------------------------------
# EMR EKS Module with two teams
#---------------------------------------------------
module "emr_containers_workshop" {
  source = "../modules/emr-eks-containers"

  eks_cluster_id        = module.eks_workshop.cluster_name
  eks_oidc_provider_arn = module.eks_workshop.oidc_provider_arn

  emr_on_eks_config = {
    # Example of all settings
    emr-data-team-a = {
      name = format("%s-%s", module.eks_workshop.cluster_name, "emr-data-team-a")

      create_namespace = true
      namespace        = "emr-data-team-a"

      execution_role_name                    = format("%s-%s", module.eks_workshop.cluster_name, "emr-eks-data-team-a")
      execution_iam_role_description         = "EMR Execution Role for emr-data-team-a"
      execution_iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"] # Attach additional policies for execution IAM Role

      tags = {
        Name = "emr-data-team-a"
      }
    },

    emr-data-team-b = {
      name = format("%s-%s", module.eks_workshop.cluster_name, "emr-data-team-b")

      create_namespace = true
      namespace        = "emr-data-team-b"

      execution_role_name                    = format("%s-%s", module.eks_workshop.cluster_name, "emr-eks-data-team-b")
      execution_iam_role_description         = "EMR Execution Role for emr-data-team-b"
      execution_iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"] # Attach additional policies for execution IAM Role

      tags = {
        Name = "emr-data-team-b"
      }
    }
  }
}

##---------------------------------------------------
## EMR ACK Controller
##---------------------------------------------------
##module "emr_ack" {
##  source = "../modules/emr-ack"
##
##  eks_cluster_id                 = module.eks_workshop.cluster_name
##  eks_oidc_provider_arn          = module.eks_workshop.oidc_provider_arn
##  ecr_public_repository_username = local.ecr_repository_username
##  ecr_public_repository_password = local.ecr_repository_password
##}

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
