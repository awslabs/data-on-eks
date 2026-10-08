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

  # CoreDNS replicas for a 10,000-node cluster. Each replica runs on a different core node.
  coredns_replicas = 8

  eks_core_addons = {
    coredns = {
      configuration_values = jsonencode({
        replicaCount = local.coredns_replicas
        resources = {
          requests = { cpu = "1", memory = "1Gi" }
          limits   = { memory = "2Gi" }
        }
        # Run only on the core managed node group (primary CIDR), not on Karpenter data nodes.
        nodeSelector = { NodeGroupType = "core" }
        affinity = {
          nodeAffinity = {
            requiredDuringSchedulingIgnoredDuringExecution = {
              nodeSelectorTerms = [{
                matchExpressions = [
                  { key = "kubernetes.io/os", operator = "In", values = ["linux"] },
                  { key = "kubernetes.io/arch", operator = "In", values = ["amd64", "arm64"] },
                ]
              }]
            }
          }
          # Required: never put two CoreDNS replicas on the same node.
          podAntiAffinity = {
            requiredDuringSchedulingIgnoredDuringExecution = [{
              labelSelector = {
                matchExpressions = [{ key = "k8s-app", operator = "In", values = ["kube-dns"] }]
              }
              topologyKey = "kubernetes.io/hostname"
            }]
          }
        }
      })
    }
    kube-proxy = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    vpc-cni = {
      before_compute              = true
      preserve                    = true
      resolve_conflicts_on_create = "OVERWRITE"
      configuration_values = jsonencode({
        env = {
          # Reference docs https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
          # Prefix delegation: the CNI allocates /28 prefixes (16 IPs each).
          ENABLE_PREFIX_DELEGATION = "true"
          # Target about 30 pod IPs per node = 2 prefixes (32 IPs).
          # MINIMUM_IP_TARGET=30: allocate 2 prefixes when the node starts.
          # WARM_IP_TARGET=2: allocate a 3rd prefix only when fewer than 2 IPs are free
          #   (more than 30 pods with IPs on the node).
          # When WARM_IP_TARGET or MINIMUM_IP_TARGET is set, WARM_PREFIX_TARGET is not used,
          # so it is not set here.
          MINIMUM_IP_TARGET = "30"
          WARM_IP_TARGET    = "2"
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
      # Primary CIDR private subnets (one per AZ). Core add-ons run here, not in the
      # secondary CIDR subnets, which are only for data workloads (Karpenter nodes).
      subnet_ids = slice(module.vpc.private_subnets, 0, length(local.azs))
      ami_type   = "AL2023_x86_64_STANDARD"
      # Sized for a 10,000-node data plane: Karpenter, CoreDNS, Prometheus, and other add-ons.
      # CoreDNS uses required pod anti-affinity (one replica per node), so
      # min_size must be >= the CoreDNS replicaCount (local.coredns_replicas).
      min_size     = local.coredns_replicas
      max_size     = local.coredns_replicas + 4
      desired_size = local.coredns_replicas

      instance_types = ["m6a.8xlarge"]

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

  # EKS PCP Tier mapping: user-friendly names → AWS EKS API values
  # These correspond to the EKS Provisioned Control Plane capacity tiers
  # Ref: terraform-aws-modules/eks/aws v21 control_plane_scaling_config
  pcp_tier_map = {
    "XL"  = "tier-xl"
    "2XL" = "tier-2xl"
    "4XL" = "tier-4xl"
    "8XL" = "tier-8xl"
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
