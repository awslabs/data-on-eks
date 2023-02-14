#---------------------------------------------------------------
# Providers
#---------------------------------------------------------------

provider "aws" {
  region = local.region
}

provider "aws" {
  region = "us-east-1"
  alias  = "virginia"
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
  apply_retry_count      = 10
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
}

#---------------------------------------------------------------
# Data Sources
#---------------------------------------------------------------

data "aws_availability_zones" "available" {}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

#---------------------------------------------------------------
# Locals
#---------------------------------------------------------------

locals {
  name      = var.name
  region    = var.region
  namespace = "ray-cluster"

  vpc_cidr = var.vpc_cidr
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  cluster_version = var.eks_cluster_version

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}

#---------------------------------------------------------------
# VPC
#---------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]
  # Control plane subnet
  intra_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 52)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = local.name
  }

  tags = merge(local.tags, {
    "karpenter.sh/discovery" = local.name
  })
}


#---------------------------------------------------------------
# EKS Cluster
#---------------------------------------------------------------

#tfsec:ignore:aws-eks-enable-control-plane-logging
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.7"

  cluster_name                   = local.name
  cluster_version                = local.cluster_version
  cluster_endpoint_public_access = true

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

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

module "karpenter_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "~> 5.11.1"

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

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 19.7"


  cluster_name                 = module.eks.cluster_name
  irsa_oidc_provider_arn       = module.eks.oidc_provider_arn
  iam_role_additional_policies = [module.karpenter_policy.arn]
  tags                         = local.tags
}

resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter"
  version             = "v0.24.0"

  values = [
    yamlencode({
      settings = {
        aws = {
          clusterName            = module.eks.cluster_name
          clusterEndpoint        = module.eks.cluster_endpoint
          defaultInstanceProfile = module.karpenter.instance_profile_name
          interruptionQueueName  = module.karpenter.queue_name
        }
      }
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = module.karpenter.irsa_arn
        }
      }
    })
  ]
}

resource "kubectl_manifest" "karpenter_provisioner" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1alpha5"
    kind       = "Provisioner"
    metadata = {
      name = "default"
    }
    spec = {
      requirements = [
        {
          key      = "karpenter.sh/capacity-type"
          operator = "In"
          values   = ["spot", "on-demand"]
        }
      ]
      limits = {
        resources = {
          cpu = "1000"
        }
      }
      providerRef = {
        name = "default"
      }
      ttlSecondsAfterEmpty = 30
      taints = [
        {
          key    = "RayClusterNodes"
          value  = "true"
          effect = "NoSchedule"
        }
      ]
    }
  })

  depends_on = [
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "karpenter_node_template" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1alpha1"
    kind       = "AWSNodeTemplate"
    metadata = {
      name = "default"
    }
    spec = {
      subnetSelector = {
        "karpenter.sh/discovery" = "${module.eks.cluster_name}"
      }
      securityGroupSelector = {
        "karpenter.sh/discovery" = "${module.eks.cluster_name}"
      }
      tags = {
        "karpenter.sh/discovery" = "${module.eks.cluster_name}"
      }
      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "1000Gi"
            volumeType          = "gp3"
            deleteOnTermination = true
          }
        }
      ]
    }
  })

  depends_on = [
    helm_release.karpenter
  ]
}

#---------------------------------------------------------------
# Operational Add-Ons
#---------------------------------------------------------------

module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.23.0"

  eks_cluster_id       = module.eks.cluster_name
  eks_cluster_endpoint = module.eks.cluster_endpoint
  eks_oidc_provider    = module.eks.oidc_provider
  eks_cluster_version  = module.eks.cluster_version

  # Wait on the node group(s) before provisioning addons
  data_plane_wait_arn = join(",", [for group in module.eks.eks_managed_node_groups : group.node_group_arn])

  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller_helm_config = {
    version = "1.4.7"
  }

  enable_self_managed_aws_ebs_csi_driver = true
  self_managed_aws_ebs_csi_driver_helm_config = {
    set_values = [
      {
        name  = "node.tolerateAllTaints"
        value = "true"
    }]
  }

  enable_aws_cloudwatch_metrics = true
  aws_cloudwatch_metrics_helm_config = {
    version = "0.0.8"
  }

  enable_aws_for_fluentbit = true
  aws_for_fluentbit_helm_config = {
    version                                   = "0.1.22"
    namespace                                 = "aws-for-fluent-bit"
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
          region          = "${local.region}"
          logGroupName    = "/${local.name}/worker-fluentbit-logs"
          logStreamPrefix = "fluentbit-"
          autoCreateGroup = "false"
        }
      })
    ]
  }

  tags = local.tags
}

#---------------------------------------------------------------
# KubeRay Operator
#---------------------------------------------------------------

resource "helm_release" "kuberay_operator" {
  namespace        = "kuberay-operator"
  create_namespace = true
  name             = "kuberay-operator"
  repository       = "https://ray-project.github.io/kuberay-helm/"
  chart            = "kuberay-operator"
  version          = "0.4.0"

  depends_on = [
    module.eks_blueprints_kubernetes_addons
  ]
}

#---------------------------------------------------------------
# Ray Cluster
#---------------------------------------------------------------

resource "helm_release" "ray_cluster" {
  namespace        = "ray-cluster"
  create_namespace = true
  name             = "ray-cluster"
  repository       = "https://ray-project.github.io/kuberay-helm/"
  chart            = "ray-cluster"
  version          = "0.4.0"

  values = [
    yamlencode({
      image = {
        repository = "rayproject/ray-ml"
        tag        = "2.0.0"
        pullPolicy = "IfNotPresent"
      }
      head = {
        enableInTreeAutoscaling = "True"
        resources = {
          limits = {
            cpu               = "14"
            memory            = "54Gi"
            ephemeral-storage = "700Gi"
          }
          requests = {
            cpu               = "14"
            memory            = "54Gi"
            ephemeral-storage = "700Gi"
          }
        }
        tolerations = [
          {
            key      = "RayClusterNodes"
            effect   = "NoSchedule"
            operator = "Exists"
          }
        ]
        containerEnv = [
          {
            name  = "RAY_LOG_TO_STDERR"
            value = "1"
          }
        ]
      }
      worker = {
        resources = {
          limits = {
            cpu               = "14"
            memory            = "54Gi"
            ephemeral-storage = "700Gi"
          }
          requests = {
            cpu               = "14"
            memory            = "54Gi"
            ephemeral-storage = "700Gi"
          }
        }
        tolerations = [
          {
            key      = "RayClusterNodes"
            effect   = "NoSchedule"
            operator = "Exists"
          }
        ]
        replicas    = "0"
        minReplicas = "0"
        maxReplicas = "9"
        containerEnv = [
          {
            name  = "RAY_LOG_TO_STDERR"
            value = "1"
          }
        ]
      }
    })
  ]

  depends_on = [
    helm_release.kuberay_operator
  ]
}

# Note: TLS
resource "kubectl_manifest" "ray_cluster_ingress" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "ray-cluster-ingress"
      namespace = "ray-cluster"
      annotations = {
        "alb.ingress.kubernetes.io/load-balancer-name" = "ray-cluster"
        "alb.ingress.kubernetes.io/scheme"             = "internet-facing" #private
        "alb.ingress.kubernetes.io/tags"               = join(",", [for key, value in local.tags : "${key}=${value}"])
        "alb.ingress.kubernetes.io/target-type"        = "ip"
      }
    }
    spec = {
      ingressClassName = "alb"
      rules = [
        {
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "ray-cluster-kuberay-head-svc"
                    port = {
                      number : 8265
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  })

  depends_on = [
    helm_release.ray_cluster
  ]
}
