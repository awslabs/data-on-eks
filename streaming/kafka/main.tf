provider "aws" {
  region = local.region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate  = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate  = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubectl" {
  apply_retry_count      = 10
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate  = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file         = false
  token                  = data.aws_eks_cluster_auth.this.token
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_availability_zones" "available" {}

data "aws_ami" "eks" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["amazon-eks-node-${module.eks.cluster_version}-*"]
  }
}

locals {
  name   = "kafka-on-eks"
  region = var.region

  cluster_version = "1.27"

  vpc_cidr = "10.1.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
  
  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}

################################################################################
# Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.13"

  cluster_name                   = local.name
  cluster_version                = local.cluster_version
  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  manage_aws_auth_configmap = true
  
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  eks_managed_node_groups = {
    core_node_group = {
      name        = "core-node-group"
      description = "EKS managed node group example launch template"
      ami_id = data.aws_ami.eks.image_id
      enable_bootstrap_user_data = true
      # Optional - This is to show how you can pass pre bootstrap data
      pre_bootstrap_user_data = <<-EOT
        echo "Node bootstrap process started by Data on EKS"
      EOT
      # Optional - Post bootstrap data to verify anything
      post_bootstrap_user_data = <<-EOT
        echo "Bootstrap complete.Ready to Go!"
      EOT
#      subnet_ids = module.vpc.private_subnets
      min_size     = 1
      max_size     = 9
      desired_size = 3
      force_update_version = true
      instance_types       = ["m5.xlarge"]
      ebs_optimized = true
      # This is the root filesystem
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
      tags = {
        Name = "core-node-grp"
      }
    }
    kafka_node_group = {
      name        = "kafka-node-group"
      description = "EKS managed node group example launch template"
      ami_id = data.aws_ami.eks.image_id
      enable_bootstrap_user_data = true
      # Optional - This is to show how you can pass pre bootstrap data
      pre_bootstrap_user_data = <<-EOT
        echo "Node bootstrap process started by Data on EKS"
      EOT
      # Optional - Post bootstrap data to verify anything
      post_bootstrap_user_data = <<-EOT
        echo "Bootstrap complete.Ready to Go!"
      EOT
#      subnet_ids = module.vpc.private_subnets
      min_size     = 1
      max_size     = 12
      desired_size = 3
      force_update_version = true
      instance_types       = ["r6i.2xlarge"]
      ebs_optimized = true
      # This is the root filesystem Not used by the brokers
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
        NodeGroupType = "kafka"
      }
      taints = [
        { 
          key = "dedicated"
          value = "kafka" 
          effect = "NO_SCHEDULE" 
        }
      ]
      tags = {
        Name = "kafka-node-grp"
      }
    }
  }

  tags = local.tags
}

################################################################################
# Kubernetes Addons
################################################################################

module "eks_blueprints_addons" {
  source = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  # Add-ons
  eks_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    coredns    = {
      most_recent = true
    }
    vpc-cni    = {
      most_recent = true
      before_compute = true
      service_account_role_arn = module.vpc_cni_ipv4_irsa.iam_role_arn
    }
    kube-proxy = {
      most_recent = true
    }
  }
  
  enable_metrics_server        = true
  metrics_server = {
    values = [templatefile("${path.module}/helm-values/kafka-values.yaml", {
      operating_system = "linux"
      node_group_type  = "core"
    })]
  }
  
  enable_cert_manager          = true
  enable_cluster_autoscaler    = true

  #---------------------------------------------------------------
  # Install Kafka Montoring Stack with Prometheus and Grafana
  # 1- Grafana port-forward `kubectl port-forward svc/kube-prometheus-stack-grafana 8080:80 -n strimzi-kafka-operator`
  # 2- Grafana Admin user: admin
  # 3- Get admin user password: `kubectl get secret kube-prometheus-stack-grafana -n strimzi-kafka-operator -o jsonpath="{.data.admin-password}" | base64 --decode ; echo`
  #---------------------------------------------------------------
  enable_kube_prometheus_stack = true
  kube_prometheus_stack = {
    namespace = "strimzi-kafka-operator" 
    values     = [templatefile("${path.module}/helm-values/prom-grafana-values.yaml", {})]
  }

  helm_releases = {
    strimzi-operator = {
      description = "Strimzi - Apache Kafka on Kubernetes"
      namespace = "strimzi-kafka-operator"
      create_namespace = true
      chart = "strimzi-kafka-operator"
      chart_version = "0.35.1"
      repository = "https://strimzi.io/charts/"
      values = [templatefile("${path.module}/helm-values/kafka-values.yaml", {
        operating_system = "linux"
        node_group_type  = "core"
      })] 
    }
  }

  tags = local.tags
}

################################################################################
# Supporting Resources
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 10)]

  enable_nat_gateway   = true
  single_nat_gateway   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.20"

  role_name_prefix = "${module.eks.cluster_name}-ebs-csi-driver-"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

module "vpc_cni_ipv4_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.20"

  role_name             = "${module.eks.cluster_name}-vpc-cni-ipv4"
  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }

  tags = local.tags
}

#---------------------------------------------------------------
# GP3 Storage Class
#---------------------------------------------------------------
resource "kubectl_manifest" "gp3_sc" {
  yaml_body = <<-YAML
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
  name: gp3
parameters:
  fsType: xfs
  type: gp3
  encrypted: "true"
allowVolumeExpansion: true
provisioner: ebs.csi.aws.com
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
YAML

  depends_on = [
    module.eks
  ]
}

#---------------------------------------------------------------
# Install Kafka cluster
# NOTE: Kafka Zookeeper and Broker pod creation may to 2 to 3 mins
#---------------------------------------------------------------
resource "kubectl_manifest" "kafka_namespace" {
  yaml_body  = file("./kafka-manifests/kafka-ns.yml")
  depends_on = [module.eks.cluster_name]
}

resource "kubectl_manifest" "kafka_cluster" {
  yaml_body  = file("./kafka-manifests/kafka-cluster.yml")
  depends_on = [module.eks_blueprints_addons]
}

resource "kubectl_manifest" "kafka_metric_config" {
  yaml_body  = file("./kafka-manifests/kafka-metrics-configmap.yml")
  depends_on = [module.eks_blueprints_addons]
}

#---------------------------------------------------------------
# Deploy Strimzi Kafka and Zookeeper dashboards in Grafana
#---------------------------------------------------------------

resource "kubectl_manifest" "podmonitor_cluster_operator_metrics" {
  yaml_body  = file("./monitoring-manifests/podmonitor-cluster-operator-metrics.yml")
  depends_on = [kubectl_manifest.kafka_namespace]
}

resource "kubectl_manifest" "podmonitor_entity_operator_metrics" {
  yaml_body  = file("./monitoring-manifests/podmonitor-entity-operator-metrics.yml")
  depends_on = [kubectl_manifest.kafka_namespace]
}

resource "kubectl_manifest" "podmonitor_kafka_resources_metrics" {
  yaml_body  = file("./monitoring-manifests/podmonitor-kafka-resources-metrics.yml")
  depends_on = [kubectl_manifest.kafka_namespace]
}

resource "kubectl_manifest" "grafana_strimzi_exporter_dashboard" {
  yaml_body  = file("./monitoring-manifests/grafana-strimzi-exporter-dashboard.yml")
  depends_on = [module.eks_blueprints_addons]
}

resource "kubectl_manifest" "grafana_strimzi_kafka_dashboard" {
  yaml_body  = file("./monitoring-manifests/grafana-strimzi-kafka-dashboard.yml")
  depends_on = [module.eks_blueprints_addons]
}

resource "kubectl_manifest" "grafana_strimzi_operators_dashboard" {
  yaml_body  = file("./monitoring-manifests/grafana-strimzi-operators-dashboard.yml")
  depends_on = [module.eks_blueprints_addons]
}

resource "kubectl_manifest" "grafana_strimzi_zookeeper_dashboard" {
  yaml_body  = file("./monitoring-manifests/grafana-strimzi-zookeeper-dashboard.yml")
  depends_on = [module.eks_blueprints_addons]
}