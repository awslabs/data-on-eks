#---------------------------------------------------------------
# Providers
#---------------------------------------------------------------

provider "aws" {
  region = local.region
}

# Used for Karpenter Helm chart
provider "aws" {
  region = "us-east-1"
  alias  = "ecr_public_region"
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

provider "kubectl" {
  apply_retry_count      = 5
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

#---------------------------------------------------------------
# Data Sources
#---------------------------------------------------------------

data "aws_availability_zones" "available" {}

# Used for Karpenter Helm chart
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr_public_region
}

#---------------------------------------------------------------
# Locals
#---------------------------------------------------------------

locals {
  name   = var.name
  region = var.region

  vpc_cidr           = "10.0.0.0/16"
  secondary_vpc_cidr = "100.64.0.0/16"
  azs                = slice(data.aws_availability_zones.available.names, 0, 3)

  cluster_version = var.eks_cluster_version

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}

#---------------------------------------------------------------
# EKS Cluster
#---------------------------------------------------------------

#tfsec:ignore:aws-eks-enable-control-plane-logging
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.15"

  cluster_name    = local.name
  cluster_version = local.cluster_version
  #WARNING: Avoid using this option (cluster_endpoint_public_access = true) in preprod or prod accounts. This feature is designed for sandbox accounts, simplifying cluster deployment and testing.
  cluster_endpoint_public_access = true

  vpc_id = module.vpc.vpc_id
  # We only want to assign the 10.0.* range subnets to the data plane
  subnet_ids               = slice(module.vpc.private_subnets, 0, 3)
  control_plane_subnet_ids = module.vpc.intra_subnets

  # Update aws-auth configmap with Karpenter node role so they
  # can join the cluster
  manage_aws_auth_configmap = true
  aws_auth_roles = [
    {
      rolearn  = module.karpenter.role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups = [
        "system:bootstrappers",
        "system:nodes",
      ]
    },
  ]

  # EKS Addons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      # The VPC CNI addon should be deployed before compute to ensure
      # the addon is configured before data plane compute resources are created
      # See README for further details
      before_compute = true
      most_recent    = true # To ensure access to the latest settings provided
      preserve       = true
      configuration_values = jsonencode({
        env = {
          # Reference https://aws.github.io/aws-eks-best-practices/reliability/docs/networkmanagement/#cni-custom-networking
          AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG = "true"
          ENI_CONFIG_LABEL_DEF               = "topology.kubernetes.io/zone"

          # Reference docs https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
  }

  # This MNG will be used to host infrastructure add-ons for
  # logging, monitoring, ingress controllers, kuberay-operator,
  # etc.
  eks_managed_node_groups = {
    infra = {
      instance_types = ["m5.large"]
      min_size       = 3
      max_size       = 3
      desired_size   = 3
    }
  }

  tags = merge(local.tags, {
    "karpenter.sh/discovery" = local.name
  })
}

#---------------------------------------------------------------
# VPC-CNI Custom Networking ENIConfig
#---------------------------------------------------------------

resource "kubectl_manifest" "eni_config" {
  for_each = zipmap(local.azs, slice(module.vpc.private_subnets, 3, 6))

  yaml_body = yamlencode({
    apiVersion = "crd.k8s.amazonaws.com/v1alpha1"
    kind       = "ENIConfig"
    metadata = {
      name = each.key
    }
    spec = {
      securityGroups = [
        module.eks.cluster_primary_security_group_id,
        module.eks.node_security_group_id,
      ]
      subnet = each.value
    }
  })
}

#---------------------------------------------------------------
# Karpenter Infrastructure
#---------------------------------------------------------------

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 19.15"

  cluster_name                 = module.eks.cluster_name
  irsa_oidc_provider_arn       = module.eks.oidc_provider_arn
  create_irsa                  = false # IRSA will be created by the kubernetes-addons module
  iam_role_additional_policies = {
    additional_policy = module.karpenter_policy.arn
  }

  tags = local.tags
}

# We have to augment default the karpenter node IAM policy with
# permissions we need for Ray Jobs to run until IRSA is added
# upstream in kuberay-operator. See issue
# https://github.com/ray-project/kuberay/issues/746
module "karpenter_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "~> 5.20"

  name        = "KarpenterS3ReadOnlyPolicy"
  description = "IAM Policy to allow read from an S3 bucket for karpenter nodes"

  policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "ListObjectsInBucket"
          Effect   = "Allow"
          Action   = ["s3:ListBucket"]
          Resource = ["arn:aws:s3:::air-example-data-2"]
        },
        {
          Sid      = "AllObjectActions"
          Effect   = "Allow"
          Action   = "s3:Get*"
          Resource = ["arn:aws:s3:::air-example-data-2/*"]
        }
      ]
    }
  )
}

#---------------------------------------------------------------
# Operational Add-Ons using EKS Blueprints
#---------------------------------------------------------------

module "eks_blueprints_addons" {
  # Users should pin the version to the latest available release
  # tflint-ignore: terraform_module_pinned_source
  source = "github.com/aws-ia/terraform-aws-eks-blueprints-addons?ref=08650fd2b4bc894bde7b51313a8dc9598d82e925"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider     = module.eks.oidc_provider
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_cloudwatch_metrics = true

  enable_aws_for_fluentbit = true
  aws_for_fluentbit_helm_config = {
    aws_for_fluent_bit_cw_log_group           = "/${local.name}/worker-fluentbit-logs"
    aws_for_fluentbit_cwlog_retention_in_days = 7 #days
    values = [
      yamlencode({
        name              = "kubernetes"
        match             = "kube.*"
        kubeURL           = "https://kubernetes.default.svc.cluster.local:443"
        mergeLog          = "On"
        mergeLogKey       = "log_processed"
        keepLog           = "On"
        k8sLoggingParser  = "On"
        k8sLoggingExclude = "Off"
        bufferSize        = "0"
        hostNetwork       = "true"
        dnsPolicy         = "ClusterFirstWithHostNet"
        filter = {
          extraFilters = <<-EOT
            Kube_Tag_Prefix     application.var.log.containers.
            Labels              Off
            Annotations         Off
            Use_Kubelet         true
            Kubelet_Port        10250
            Kube_CA_File        /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
            Kube_Token_File     /var/run/secrets/kubernetes.io/serviceaccount/token
          EOT
        }
        cloudWatch = {
          enabled         = "true"
          match           = "*"
          region          = local.region
          logGroupName    = "/${local.name}/worker-fluentbit-logs"
          logStreamPrefix = "fluentbit-"
          autoCreateGroup = "false"
        }
      })
    ]
  }

  enable_karpenter = true
  karpenter_helm_config = {
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }
  karpenter_node_iam_instance_profile        = module.karpenter.instance_profile_name
  karpenter_enable_spot_termination_handling = true

  tags = local.tags
}

#---------------------------------------------------------------
# KubeRay Operator using Helm Release
#---------------------------------------------------------------

resource "helm_release" "kuberay_operator" {
  namespace        = "kuberay-operator"
  create_namespace = true
  name             = "kuberay-operator"
  repository       = "https://ray-project.github.io/kuberay-helm/"
  chart            = "kuberay-operator"
  version          = "0.4.0"

  depends_on = [
    module.eks
  ]
}
