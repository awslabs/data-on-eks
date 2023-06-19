module "eks_blueprints_kubernetes_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "v1.0.0"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
  eks_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
      preserve                 = true
      most_recent              = true
    }
    coredns = {
      most_recent = true
      preserve    = true
    }
    kube-proxy = {
      most_recent = true
      preserve    = true
    }
  }

  #---------------------------------------
  # Kubernetes Add-ons
  #---------------------------------------
  #---------------------------------------------------------------
  # CoreDNS Autoscaler helps to scale for large EKS Clusters
  #   Further tuning for CoreDNS is to leverage NodeLocal DNSCache -> https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/
  #---------------------------------------------------------------
  enable_cluster_proportional_autoscaler = true
  cluster_proportional_autoscaler = {
    timeout = "300"
    values = [templatefile("${path.module}/helm-values/coredns-autoscaler-values.yaml", {
      target = "deployment/coredns"
    })]
    description = "Cluster Proportional Autoscaler for CoreDNS Service"
  }

  #---------------------------------------
  # Metrics Server
  #---------------------------------------
  enable_metrics_server = true
  metrics_server = {
    timeout = "300"
    values  = [templatefile("${path.module}/helm-values/metrics-server-values.yaml", {})]
  }

  #---------------------------------------
  # VPA
  #---------------------------------------
  enable_vpa = true
  vpa = {
    timeout = "300"
  }

  #---------------------------------------
  # Cluster Autoscaler
  #---------------------------------------
  enable_cluster_autoscaler = true
  cluster_autoscaler = {
    timeout     = "300"
    create_role = true
    values = [templatefile("${path.module}/helm-values/cluster-autoscaler-values.yaml", {
      aws_region     = var.region,
      eks_cluster_id = module.eks.cluster_name
    })]
  }

  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
  enable_karpenter                  = true
  karpenter_enable_spot_termination = true
  karpenter_node = {
    create_iam_role          = true
    iam_role_use_name_prefix = false
    # We are defining role name so that we can add this to aws-auth during EKS Cluster creation
    iam_role_name = local.karpenter_iam_role_name
  }
  karpenter = {
    timeout             = "300"
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

  #---------------------------------------
  # CloudWatch metrics for EKS
  #---------------------------------------
  enable_aws_cloudwatch_metrics = var.enable_aws_cloudwatch_metrics
  aws_cloudwatch_metrics = {
    timeout = "300"
    values  = [templatefile("${path.module}/helm-values/aws-cloudwatch-metrics-values.yaml", {})]
  }

  #---------------------------------------
  # Adding AWS Load Balancer Controller
  #---------------------------------------
  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    timeout = "300"
  }

  #---------------------------------------
  # Enable FSx for Lustre CSI Driver
  #---------------------------------------
  enable_aws_fsx_csi_driver = var.enable_fsx_for_lustre
  aws_fsx_csi_driver = {
    # INFO: fsx node daemonset wont be placed on Karpenter nodes with taints without the following toleration
    values = [
      <<-EOT
        node:
          tolerations:
            - operator: Exists
      EOT
    ]
  }

  tags = local.tags

}

#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
# NOTE: This module will be moved to a dedicated repo and the source will be changed accordingly.
module "kubernetes_data_addons" {
  # Please note that local source will be replaced once the below repo is public
  # source = "https://github.com/aws-ia/terraform-aws-kubernetes-data-addons"
  source            = "../../../workshop/modules/terraform-aws-eks-data-addons"
  oidc_provider_arn = module.eks.oidc_provider_arn


  #---------------------------------------------------------------
  # Apache YuniKorn Add-on
  #---------------------------------------------------------------
  enable_yunikorn = var.enable_yunikorn
  yunikorn_helm_config = {
    values = [templatefile("${path.module}/helm-values/yunikorn-values.yaml", {
      image_version = "1.2.0"
    })]
  }

  #---------------------------------------------------------------
  # EMR Spark Operator
  #---------------------------------------------------------------
  enable_emr_spark_operator = var.enable_emr_spark_operator
  emr_spark_operator_helm_config = {
    repository_username = data.aws_ecr_authorization_token.token.user_name
    repository_password = data.aws_ecr_authorization_token.token.password
    values = [templatefile("${path.module}/helm-values/emr-spark-operator-values.yaml", {
      aws_region = var.region
    })]
  }

  #---------------------------------------------------------------
  # Kubecost Add-on
  #---------------------------------------------------------------
  enable_kubecost = var.enable_kubecost
  kubecost_helm_config = {
    values              = [templatefile("${path.module}/helm-values/kubecost-values.yaml", {})]
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

  #---------------------------------------------------------------
  # Prometheus Add-on
  #---------------------------------------------------------------
  enable_prometheus = var.enable_amazon_prometheus
  prometheus_helm_config = {
    values = [templatefile("${path.module}/helm-values/prometheus-values.yaml", {})]
    # Use only when Amazon managed Prometheus is enabled with `amp.tf` resources
    set = var.enable_amazon_prometheus ? [
      {
        name  = "serviceAccounts.server.name"
        value = local.amp_ingest_service_account
      },
      {
        name  = "serviceAccounts.server.annotations.eks\\.amazonaws\\.com/role-arn"
        value = module.amp_ingest_irsa[0].iam_role_arn
      },
      {
        name  = "server.remoteWrite[0].url"
        value = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}/api/v1/remote_write"
      },
      {
        name  = "server.remoteWrite[0].sigv4.region"
        value = local.region
      }
    ] : []
  }

  #---------------------------------------------------------------
  # Open Source Grafana Add-on
  #---------------------------------------------------------------
  enable_grafana = var.enable_grafana
  grafana_helm_config = {
    create_irsa = true # Creates IAM Role with trust policy, default IAM policy and adds service account annotation
    set_sensitive = [
      {
        name  = "adminPassword"
        value = data.aws_secretsmanager_secret_version.admin_password_version.secret_string
      }
    ]
  }
}

#---------------------------------------
# Karpenter Provisioners
#---------------------------------------
data "kubectl_path_documents" "karpenter_provisioners" {
  pattern = "${path.module}/karpenter-provisioners/spark-*.yaml"
  vars = {
    azs            = local.region
    eks_cluster_id = module.eks.cluster_name
  }
}

resource "kubectl_manifest" "karpenter_provisioner" {
  for_each  = toset(data.kubectl_path_documents.karpenter_provisioners.documents)
  yaml_body = each.value

  depends_on = [module.eks_blueprints_kubernetes_addons]
}

#---------------------------------------------------------------
# IRSA for EBS
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.14"
  role_name             = format("%s-%s", local.name, "ebs-csi-driver")
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  tags = local.tags
}

#---------------------------------------------------------------
# IRSA for VPC CNI
#---------------------------------------------------------------
module "vpc_cni_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.14"
  role_name             = format("%s-%s", local.name, "vpc-cni")
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
# VPC CNI Addon should run before the nodes are created
# Ideally VPC CNI with custom configuration values should be deployed before the nodes are created to use the correct VPC CNI config
#---------------------------------------------------------------
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "vpc-cni"
  addon_version               = data.aws_eks_addon_version.this.version
  resolve_conflicts_on_create = "OVERWRITE"
  preserve                    = true # Ensure VPC CNI is not deleted before the add-ons and nodes are deleted during the cleanup/destroy.
  service_account_role_arn    = module.vpc_cni_irsa.iam_role_arn
}

#------------------------------------------
# Amazon Prometheus
#------------------------------------------
locals {
  amp_ingest_service_account = "amp-iamproxy-ingest-service-account"
  namespace                  = "prometheus"
}

resource "aws_prometheus_workspace" "amp" {
  count = var.enable_amazon_prometheus ? 1 : 0

  alias = format("%s-%s", "amp-ws", local.name)
  tags  = local.tags
}

#---------------------------------------------------------------
# Grafana Admin credentials resources
# Login to AWS secrets manager with the same role as Terraform to extract the Grafana admin password with the secret name as "grafana"
#---------------------------------------------------------------
data "aws_secretsmanager_secret_version" "admin_password_version" {
  secret_id  = aws_secretsmanager_secret.grafana.id
  depends_on = [aws_secretsmanager_secret_version.grafana]
}

resource "random_password" "grafana" {
  length           = 16
  special          = true
  override_special = "@_"
}

#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "grafana" {
  name                    = "${local.name}-grafana"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id     = aws_secretsmanager_secret.grafana.id
  secret_string = random_password.grafana.result
}


#---------------------------------------------------------------
# IRSA for VPC CNI
#---------------------------------------------------------------
module "amp_ingest_irsa" {
  count = var.enable_amazon_prometheus ? 1 : 0

  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "~> 5.14"
  role_name = format("%s-%s", local.name, "amp-ingest")

  attach_amazon_managed_service_prometheus_policy  = true
  amazon_managed_service_prometheus_workspace_arns = [aws_prometheus_workspace.amp[0].arn]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${local.namespace}:${local.amp_ingest_service_account}"]
    }
  }
  tags = local.tags
}
