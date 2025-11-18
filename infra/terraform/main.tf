data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_partition" "current" {}
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

data "aws_caller_identity" "current" {}

locals {

  name       = var.name
  region     = var.region
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  tags = merge(var.tags, {
    Blueprint    = local.name
    GithubRepo   = "github.com/awslabs/data-on-eks"
    DeploymentId = var.deployment_id
  })

  eks_core_addons = {
    coredns    = {}
    kube-proxy = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    vpc-cni = {
      before_compute = true
      preserve       = true
      resolve_conflicts_on_create = "OVERWRITE"
      configuration_values = jsonencode({
        env = {
          # Reference docs https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
  }

  # Define the default core node group configuration
  default_node_groups = {
    core_node_group = {
      name        = "core-node-group"
      partition   = local.partition
      account_id  = local.account_id
      description = "EKS Core node group for hosting system add-ons"
      subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]
      )
      ami_type     = "AL2023_x86_64_STANDARD"
      min_size     = 4
      max_size     = 8
      desired_size = 4

      instance_types = ["m6a.xlarge"]

      iam_role_additional_policies = {
        # Not required, but used in the example to access the nodes to inspect mounted volumes
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }

      ebs_optimized = true

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 100
            volume_type = "gp3"
          }
        }
      }

      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "core"
      }

      tags = merge(local.tags, {
        Name = "core-node-grp"
      })
    }
  }

  # # Private ECR Account IDs for EMR Spark Operator Helm Charts
  # account_region_map = {
  #   ap-northeast-1 = "059004520145"
  #   ap-northeast-2 = "996579266876"
  #   ap-south-1     = "235914868574"
  #   ap-southeast-1 = "671219180197"
  #   ap-southeast-2 = "038297999601"
  #   ca-central-1   = "351826393999"
  #   eu-central-1   = "107292555468"
  #   eu-north-1     = "830386416364"
  #   eu-west-1      = "483788554619"
  #   eu-west-2      = "118780647275"
  #   eu-west-3      = "307523725174"
  #   sa-east-1      = "052806832358"
  #   us-east-1      = "755674844232"
  #   us-east-2      = "711395599931"
  #   us-west-1      = "608033475327"
  #   us-west-2      = "895885662937"
  # }
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
