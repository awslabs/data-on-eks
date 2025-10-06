data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_partition" "current" {}
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

locals {

  name       = var.name
  region     = var.region
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  tags = merge(var.tags, {
    Blueprint     = local.name
    GithubRepo    = "github.com/awslabs/data-on-eks"
    DeploymentId  = var.deployment_id
  })

  base_addons = {
    for name, enabled in var.enable_cluster_addons :
    name => {} if enabled
  }

  # Extended configurations used for specific addons with custom settings
  addon_overrides = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
      preserve       = true
      most_recent    = true
      configuration_values = jsonencode({
        env = {
          # Reference docs https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }

    eks-pod-identity-agent = {
      before_compute = true
    }

    aws-ebs-csi-driver = {
      # Pod Identity used instead of service_account_role_arn
      most_recent = true
      pod_identity_association = [
        {
          role_arn        = aws_iam_role.ebs_csi_pod_identity_role.arn
          service_account = "ebs-csi-controller-sa"
        }
      ]
    }

    amazon-cloudwatch-observability = {
      preserve = true
      pod_identity_association = [
        {
          role_arn        = aws_iam_role.cloudwatch_observability_role.arn
          service_account = "cloudwatch-agent"
          namespace       = "amazon-cloudwatch"
        }
      ]
    }

    aws-mountpoint-s3-csi-driver = {
      preserve = true
      pod_identity_association = [
        {
          role_arn        = aws_iam_role.s3_csi_pod_identity_role.arn
          service_account = "s3-csi-driver-sa"
        }
      ]
    }
  }

  # Merge base with overrides
  cluster_addons = {
    for name, config in local.base_addons :
    name => merge(config, lookup(local.addon_overrides, name, {}))
  }

  # Define the default core node group configuration
  default_node_groups = {
    core_node_group = {
      name        = "core-node-group"
      description = "EKS Core node group for hosting system add-ons"
      subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]
      )
      ami_type     = "AL2023_x86_64_STANDARD"
      min_size     = 4
      max_size     = 8
      desired_size = 4

      instance_types = ["m6a.xlarge"]

      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "core"
      }

      tags = merge(local.tags, {
        Name = "core-node-grp"
      })
    }
  }

  # Private ECR Account IDs for EMR Spark Operator Helm Charts
  account_region_map = {
    ap-northeast-1 = "059004520145"
    ap-northeast-2 = "996579266876"
    ap-south-1     = "235914868574"
    ap-southeast-1 = "671219180197"
    ap-southeast-2 = "038297999601"
    ca-central-1   = "351826393999"
    eu-central-1   = "107292555468"
    eu-north-1     = "830386416364"
    eu-west-1      = "483788554619"
    eu-west-2      = "118780647275"
    eu-west-3      = "307523725174"
    sa-east-1      = "052806832358"
    us-east-1      = "755674844232"
    us-east-2      = "711395599931"
    us-west-1      = "608033475327"
    us-west-2      = "895885662937"
  }

}

# ECR always authenticates with `us-east-1` region
# Docs -> https://docs.aws.amazon.com/AmazonECR/latest/public/public-registries.html
provider "aws" {
  alias  = "ecr"
  region = "us-east-1"
}

provider "aws" {
  region = local.region
  default_tags {
    tags = local.tags
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
provider "kubectl" {
  apply_retry_count      = 30
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
}

